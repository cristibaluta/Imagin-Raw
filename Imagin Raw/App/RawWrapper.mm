
#import "RawWrapper.h"
#import "RawPhoto.h"
#include "../libraw/libraw.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

@implementation RawWrapper

+ (instancetype)shared {
    static RawWrapper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

+ (dispatch_queue_t)librawQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("ro.imagin.libraw", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

- (NSData *)extractEmbeddedJPEG:(NSString *)path {
    __block NSData *result = nil;

    dispatch_sync([[self class] librawQueue], ^{
        result = [self _extractEmbeddedJPEGSynchronized:path];
    });

    return result;
}

- (NSData *)_extractEmbeddedJPEGSynchronized:(NSString *)path {
    // Use heap allocation to ensure LibRaw constructor is called within serialized context
    LibRaw *raw = new LibRaw();
    NSData *result = nil;

    @try {
        int ret = raw->open_file(path.UTF8String);
        if (ret != LIBRAW_SUCCESS) {
            delete raw;
            return nil;
        }

        ret = raw->unpack_thumb();
        if (ret != LIBRAW_SUCCESS) {
            raw->recycle();
            delete raw;
            return nil;
        }

        libraw_processed_image_t *thumb = raw->dcraw_make_mem_thumb();
        if (!thumb || thumb->type != LIBRAW_IMAGE_JPEG) {
            raw->recycle();
            delete raw;
            return nil;
        }

        result = [NSData dataWithBytes:thumb->data length:thumb->data_size];

        LibRaw::dcraw_clear_mem(thumb);
        raw->recycle();
        delete raw;
    }
    @catch (NSException *exception) {
        if (raw) {
            raw->recycle();
            delete raw;
        }
        NSLog(@"LibRaw exception: %@", exception);
        result = nil;
    }

    return result;
}

- (RawPhoto *)extractRawPhoto:(NSString *)path {
    __block RawPhoto *result = nil;

    dispatch_sync([[self class] librawQueue], ^{
        result = [self _extractRawPhotoSynchronized:path];
    });

    return result;
}

- (RawPhoto *)_extractRawPhotoSynchronized:(NSString *)path {
    LibRaw *raw = new LibRaw();
    NSData *imageData = nil;
    NSMutableDictionary *exifData = [NSMutableDictionary dictionary];

    @try {
        int ret = raw->open_file(path.UTF8String);
        if (ret != LIBRAW_SUCCESS) {
            delete raw;
            return [[RawPhoto alloc] initWithImageData:nil exifData:nil];
        }

        // Extract EXIF data from LibRaw
        [self extractExifData:raw intoDict:exifData];

        // Extract embedded JPEG
        ret = raw->unpack_thumb();
        if (ret != LIBRAW_SUCCESS) {
            raw->recycle();
            delete raw;
            return [[RawPhoto alloc] initWithImageData:nil exifData:exifData];
        }

        libraw_processed_image_t *thumb = raw->dcraw_make_mem_thumb();
        if (thumb && thumb->type == LIBRAW_IMAGE_JPEG) {
            imageData = [NSData dataWithBytes:thumb->data length:thumb->data_size];
            LibRaw::dcraw_clear_mem(thumb);
        }

        raw->recycle();
        delete raw;

        return [[RawPhoto alloc] initWithImageData:imageData exifData:exifData];
    }
    @catch (NSException *exception) {
        if (raw) {
            raw->recycle();
            delete raw;
        }
        NSLog(@"LibRaw exception: %@", exception);
        return [[RawPhoto alloc] initWithImageData:nil exifData:nil];
    }
}

- (void)extractExifData:(LibRaw *)raw intoDict:(NSMutableDictionary *)exifDict {
    if (!raw || !exifDict) return;

    // Camera and lens information
    if (raw->imgdata.idata.make[0] != '\0') {
        exifDict[@"Make"] = [NSString stringWithUTF8String:raw->imgdata.idata.make];
    }
    if (raw->imgdata.idata.model[0] != '\0') {
        exifDict[@"Model"] = [NSString stringWithUTF8String:raw->imgdata.idata.model];
    }
    if (raw->imgdata.lens.Lens[0] != '\0') {
        exifDict[@"LensModel"] = [NSString stringWithUTF8String:raw->imgdata.lens.Lens];
    }

    // Shooting parameters
    exifDict[@"ISO"] = @(raw->imgdata.other.iso_speed);
    exifDict[@"FocalLength"] = @(raw->imgdata.other.focal_len);
    exifDict[@"Aperture"] = @(raw->imgdata.other.aperture);
    exifDict[@"ShutterSpeed"] = @(raw->imgdata.other.shutter);

    // Image dimensions
    exifDict[@"ImageWidth"] = @(raw->imgdata.sizes.width);
    exifDict[@"ImageHeight"] = @(raw->imgdata.sizes.height);
    exifDict[@"RawWidth"] = @(raw->imgdata.sizes.raw_width);
    exifDict[@"RawHeight"] = @(raw->imgdata.sizes.raw_height);

    // White balance
    if (raw->imgdata.color.cam_mul[0] > 0) {
        exifDict[@"WhiteBalance_R"] = @(raw->imgdata.color.cam_mul[0]);
    }
    if (raw->imgdata.color.cam_mul[1] > 0) {
        exifDict[@"WhiteBalance_G"] = @(raw->imgdata.color.cam_mul[1]);
    }
    if (raw->imgdata.color.cam_mul[2] > 0) {
        exifDict[@"WhiteBalance_B"] = @(raw->imgdata.color.cam_mul[2]);
    }

    // Timestamps (if available)
    if (raw->imgdata.other.timestamp > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:raw->imgdata.other.timestamp];
        exifDict[@"DateTime"] = date;
    }

    // Canon MakerNote: Detect Canon files
    NSString *make = exifDict[@"Make"];
    if (make && [make rangeOfString:@"Canon" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        // This is a Canon file
        exifDict[@"CanonMakerNoteDetected"] = @YES;

        // Attempt to extract rating if Canon makernotes are available
        if (raw->imgdata.makernotes.canon.SensorWidth > 0) {
            // Canon makernotes are parsed
            if (raw->imgdata.makernotes.canon.Quality > 0) {
                exifDict[@"CanonQuality"] = @(raw->imgdata.makernotes.canon.Quality);
            }
        }
    }

    // GPS data (if available)
    if (raw->imgdata.other.parsed_gps.gpsparsed) {
        NSMutableDictionary *gpsDict = [NSMutableDictionary dictionary];

        // Convert latitude from degrees, minutes, seconds to decimal degrees
        float latDegrees = raw->imgdata.other.parsed_gps.latitude[0];
        float latMinutes = raw->imgdata.other.parsed_gps.latitude[1];
        float latSeconds = raw->imgdata.other.parsed_gps.latitude[2];
        double latDecimal = latDegrees + (latMinutes / 60.0) + (latSeconds / 3600.0);
        gpsDict[@"Latitude"] = @(latDecimal);

        // Convert longitude from degrees, minutes, seconds to decimal degrees
        float longDegrees = raw->imgdata.other.parsed_gps.longitude[0];
        float longMinutes = raw->imgdata.other.parsed_gps.longitude[1];
        float longSeconds = raw->imgdata.other.parsed_gps.longitude[2];
        double longDecimal = longDegrees + (longMinutes / 60.0) + (longSeconds / 3600.0);
        gpsDict[@"Longitude"] = @(longDecimal);

        gpsDict[@"Altitude"] = @(raw->imgdata.other.parsed_gps.altitude);
        exifDict[@"GPS"] = gpsDict;
    }

    // Color profile information
    if (raw->imgdata.color.profile_length > 0) {
        exifDict[@"ColorProfileLength"] = @(raw->imgdata.color.profile_length);
    }
}

// Extract Canon in-camera rating using ImageIO framework
// Canon stores the in-camera rating in IPTC metadata as StarRating
- (NSNumber *)extractCanonRatingFromFile:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);

    if (!imageSource) {
        return nil;
    }

    NSNumber *rating = nil;

    // Get image properties including EXIF, IPTC, and MakerNote
    CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
    if (imageProperties) {
        NSDictionary *properties = (__bridge_transfer NSDictionary *)imageProperties;

        // Check IPTC dictionary for StarRating (this is where Canon stores in-camera rating)
        NSDictionary *iptcDict = properties[(NSString *)kCGImagePropertyIPTCDictionary];
        if (iptcDict) {
            NSNumber *starRating = iptcDict[@"StarRating"];
            if (starRating && [starRating intValue] > 0) {
                rating = starRating;
            }
        }

        // Fallback: Check standard EXIF rating if IPTC not found
        if (!rating) {
            NSDictionary *exifDict = properties[(NSString *)kCGImagePropertyExifDictionary];
            if (exifDict) {
                NSNumber *exifRating = exifDict[@"UserRating"];
                if (exifRating && [exifRating intValue] > 0) {
                    rating = exifRating;
                }
            }
        }
    }

    CFRelease(imageSource);
    return rating;
}

@end
