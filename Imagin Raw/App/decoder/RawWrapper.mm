
#import "RawWrapper.h"
#import "RawPhoto.h"
#include "../libraw/libraw.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

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

#if TARGET_OS_OSX
- (nullable NSImage *)extractFullResolution:(NSString *)path {
    __block NSImage *result = nil;

    dispatch_sync([[self class] librawQueue], ^{
        NSDate *t0 = [NSDate date];
        LibRaw *raw = new LibRaw();
        @try {
            if (raw->open_file(path.UTF8String) != LIBRAW_SUCCESS) {
                NSLog(@"[FullRes] open_file failed");
                delete raw; return;
            }
            NSLog(@"[FullRes] open_file: %.3fs", -[t0 timeIntervalSinceNow]);

            raw->imgdata.params.use_camera_wb  = 1;
            raw->imgdata.params.use_auto_wb    = 0;
            raw->imgdata.params.no_auto_bright = 1;
            raw->imgdata.params.output_bps     = 8;
            raw->imgdata.params.half_size      = 1; // 2x faster: demosaic at half width/height
            raw->imgdata.params.output_color   = 1; // sRGB

            if (raw->unpack() != LIBRAW_SUCCESS) {
                NSLog(@"[FullRes] unpack failed");
                raw->recycle(); delete raw; return;
            }
            NSLog(@"[FullRes] unpack: %.3fs", -[t0 timeIntervalSinceNow]);

            if (raw->dcraw_process() != LIBRAW_SUCCESS) {
                NSLog(@"[FullRes] dcraw_process failed");
                raw->recycle(); delete raw; return;
            }
            NSLog(@"[FullRes] dcraw_process: %.3fs", -[t0 timeIntervalSinceNow]);

            libraw_processed_image_t *img = raw->dcraw_make_mem_image();
            if (!img) { NSLog(@"[FullRes] dcraw_make_mem_image returned nil"); raw->recycle(); delete raw; return; }
            NSLog(@"[FullRes] make_mem_image: %.3fs  size=%ux%u colors=%d", -[t0 timeIntervalSinceNow], img->width, img->height, img->colors);

            if (img->type == LIBRAW_IMAGE_BITMAP && img->colors == 3) {
                size_t w = img->width;
                size_t h = img->height;
                size_t bytesPerRow = w * 4;
                uint8_t *buf = (uint8_t *)calloc(h * bytesPerRow, 1);
                if (buf) {
                    uint8_t *src = img->data;
                    for (size_t row = 0; row < h; row++) {
                        uint8_t *dst = buf + row * bytesPerRow;
                        uint8_t *s   = src + row * w * 3;
                        for (size_t col = 0; col < w; col++) {
                            dst[col*4+0] = s[col*3+0];
                            dst[col*4+1] = s[col*3+1];
                            dst[col*4+2] = s[col*3+2];
                            dst[col*4+3] = 255;
                        }
                    }
                    NSLog(@"[FullRes] RGB→RGBX copy: %.3fs", -[t0 timeIntervalSinceNow]);

                    // Pass the buffer directly via planes pointer array
                    uint8_t *planes[1] = { buf };
                    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                        initWithBitmapDataPlanes:planes
                        pixelsWide:(NSInteger)w
                        pixelsHigh:(NSInteger)h
                        bitsPerSample:8
                        samplesPerPixel:3
                        hasAlpha:NO
                        isPlanar:NO
                        colorSpaceName:NSDeviceRGBColorSpace
                        bytesPerRow:(NSInteger)(w * 4)
                        bitsPerPixel:32];

                    if (rep) {
                        // rep now holds a copy of buf; safe to free buf after this point
                        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize((CGFloat)w, (CGFloat)h)];
                        [image addRepresentation:rep];
                        result = image;
                        NSLog(@"[FullRes] NSImage built: %.3fs  size=%lux%lu", -[t0 timeIntervalSinceNow], w, h);
                    } else {
                        NSLog(@"[FullRes] ❌ NSBitmapImageRep init failed for size=%lux%lu bpr=%lu", w, h, w*4);
                    }
                    free(buf);
                }
            }

            LibRaw::dcraw_clear_mem(img);
            raw->recycle();
            delete raw;
            NSLog(@"[FullRes] total: %.3fs", -[t0 timeIntervalSinceNow]);
        }
        @catch (NSException *e) {
            NSLog(@"[FullRes] exception: %@", e);
            raw->recycle();
            delete raw;
        }
    });

    return result;
}
#endif

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

// Extract metadata (rating, width, height) using ImageIO framework
// Canon stores the in-camera rating in IPTC metadata as StarRating
- (NSDictionary *)extractMetadata:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);

    if (!imageSource) {
        return nil;
    }

    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];

    // Get image properties including EXIF, IPTC, and dimensions
    CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
    if (imageProperties) {
        NSDictionary *properties = (__bridge_transfer NSDictionary *)imageProperties;

        // Extract camera make and model
        NSDictionary *tiffDict = properties[(NSString *)kCGImagePropertyTIFFDictionary];
        if (tiffDict) {
            NSString *make = tiffDict[(NSString *)kCGImagePropertyTIFFMake];
            NSString *model = tiffDict[(NSString *)kCGImagePropertyTIFFModel];

            if (make && make.length > 0) {
                metadata[@"cameraMake"] = make;
            }
            if (model && model.length > 0) {
                metadata[@"cameraModel"] = model;
            }
        }

        // Extract rating
        // Check IPTC dictionary for StarRating (this is where Canon stores in-camera rating)
        NSDictionary *iptcDict = properties[(NSString *)kCGImagePropertyIPTCDictionary];
        if (iptcDict) {
            NSNumber *starRating = iptcDict[@"StarRating"];
            if (starRating && [starRating intValue] > 0) {
                metadata[@"rating"] = starRating;
            }
        }

        // Fallback: Check standard EXIF rating if IPTC not found
        if (!metadata[@"rating"]) {
            NSDictionary *exifDict = properties[(NSString *)kCGImagePropertyExifDictionary];
            if (exifDict) {
                NSNumber *exifRating = exifDict[@"UserRating"];
                if (exifRating && [exifRating intValue] > 0) {
                    metadata[@"rating"] = exifRating;
                }
            }
        }

        // Extract resolution
        NSNumber *width = properties[(NSString *)kCGImagePropertyPixelWidth];
        NSNumber *height = properties[(NSString *)kCGImagePropertyPixelHeight];

        if (width && height) {
            metadata[@"width"] = width;
            metadata[@"height"] = height;
        }
    }

    CFRelease(imageSource);

    // If we didn't get resolution from ImageIO, try LibRaw for RAW files
    if (!metadata[@"width"] || !metadata[@"height"]) {
        __block NSDictionary *librawResolution = nil;

        dispatch_sync([[self class] librawQueue], ^{
            LibRaw *raw = new LibRaw();

            @try {
                int ret = raw->open_file(path.UTF8String);
                if (ret == LIBRAW_SUCCESS) {
                    // Use the visible image dimensions (after cropping)
                    int width = raw->imgdata.sizes.width;
                    int height = raw->imgdata.sizes.height;

                    if (width > 0 && height > 0) {
                        librawResolution = @{@"width": @(width), @"height": @(height)};
                    }

                    raw->recycle();
                }
                delete raw;
            }
            @catch (NSException *exception) {
                if (raw) {
                    raw->recycle();
                    delete raw;
                }
                NSLog(@"LibRaw exception in extractMetadata: %@", exception);
            }
        });

        if (librawResolution) {
            metadata[@"width"] = librawResolution[@"width"];
            metadata[@"height"] = librawResolution[@"height"];
        }
    }

    return metadata.count > 0 ? metadata : nil;
}

@end
