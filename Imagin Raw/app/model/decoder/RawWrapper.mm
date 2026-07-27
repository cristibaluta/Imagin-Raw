
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

- (NSDictionary *)extractExif:(NSURL *)url {
    __block NSDictionary *result = nil;

    dispatch_sync([[self class] librawQueue], ^{
        result = [self _extractExifOnlySynchronized:url];
    });

    return result;
}

- (NSData *)_extractEmbeddedJPEGSynchronized:(NSString *)path {
    // Use heap allocation to ensure LibRaw constructor is called within serialized context
    LibRaw *raw = new LibRaw();
    NSData *result = nil;

    @try {
        NSURL *url = [NSURL URLWithString:path]; // parses the file:// URL string correctly
        NSString *filePath = url.path; // raw path: /Users/...
        int ret = raw->open_file(filePath.UTF8String);
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

//- (RawPhoto *)extractRawPhoto:(NSURL *)url {
//    __block RawPhoto *result = nil;

//    dispatch_sync([[self class] librawQueue], ^{
//        result = [self _extractRawPhotoSynchronized:url];
//    });
//
//    return result;
//}

#if TARGET_OS_OSX
- (nullable NSImage *)extractFullResolution:(NSString *)path {
    __block NSImage *result = nil;

    dispatch_sync([[self class] librawQueue], ^{
        NSDate *t0 = [NSDate date];
        LibRaw *raw = new LibRaw();
        @try {
            NSURL *url = [NSURL URLWithString:path]; // parses the file:// URL string correctly
            NSString *filePath = url.path; // raw path: /Users/...
            if (raw->open_file(filePath.UTF8String) != LIBRAW_SUCCESS) {
                NSLog(@"[FullRes] open_file failed");
                delete raw;
                return;
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
                raw->recycle();
                delete raw;
                return;
            }
            NSLog(@"[FullRes] unpack: %.3fs", -[t0 timeIntervalSinceNow]);

            if (raw->dcraw_process() != LIBRAW_SUCCESS) {
                NSLog(@"[FullRes] dcraw_process failed");
                raw->recycle();
                delete raw;
                return;
            }
            NSLog(@"[FullRes] dcraw_process: %.3fs", -[t0 timeIntervalSinceNow]);

            libraw_processed_image_t *img = raw->dcraw_make_mem_image();
            if (!img) {
                NSLog(@"[FullRes] dcraw_make_mem_image returned nil");
                raw->recycle();
                delete raw;
                return;
            }
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
                    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:planes
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

//- (RawPhoto *)_extractRawPhotoSynchronized:(NSURL *)url {
//    LibRaw *raw = new LibRaw();
//    NSData *imageData = nil;
//    NSMutableDictionary *exifData = [NSMutableDictionary dictionary];
//
//    @try {
//        int ret = raw->open_file(url.path.UTF8String);
//        if (ret != LIBRAW_SUCCESS) {
//            delete raw;
//            return [[RawPhoto alloc] initWithImageData:nil exifData:nil];
//        }
//
//        // Extract EXIF data from LibRaw
//        [self extractExifData:raw intoDict:exifData];
//
//        // Extract embedded JPEG
//        ret = raw->unpack_thumb();
//        if (ret != LIBRAW_SUCCESS) {
//            raw->recycle();
//            delete raw;
//            return [[RawPhoto alloc] initWithImageData:nil exifData:exifData];
//        }
//
//        libraw_processed_image_t *thumb = raw->dcraw_make_mem_thumb();
//        if (thumb && thumb->type == LIBRAW_IMAGE_JPEG) {
//            imageData = [NSData dataWithBytes:thumb->data length:thumb->data_size];
//            LibRaw::dcraw_clear_mem(thumb);
//        }
//
//        raw->recycle();
//        delete raw;
//
//        return [[RawPhoto alloc] initWithImageData:imageData exifData:exifData];
//    }
//    @catch (NSException *exception) {
//        if (raw) {
//            raw->recycle();
//            delete raw;
//        }
//        NSLog(@"LibRaw exception: %@", exception);
//        return [[RawPhoto alloc] initWithImageData:nil exifData:nil];
//    }
//}

- (NSDictionary *)_extractExifOnlySynchronized:(NSURL *)url {
    LibRaw *raw = new LibRaw();
    NSMutableDictionary *exifData = [NSMutableDictionary dictionary];

    @try {
        raw->imgdata.params.use_camera_wb = 0;

        // open_file() alone parses headers + maker notes — no pixel/thumb
        // decoding happens here, so this is as cheap as LibRaw gets.
        int ret = raw->open_file(url.path.UTF8String);
        if (ret != LIBRAW_SUCCESS) {
            raw->recycle();
            delete raw;
            return nil;
        }
        raw->adjust_sizes_info_only();   // computes iwidth/iheight/flip-adjusted sizes, no pixel decode
        [self extractExifData:raw intoDict:exifData];

        raw->recycle();
        delete raw;
        return exifData;
    }
    @catch (NSException *exception) {
        if (raw) {
            raw->recycle();
            delete raw;
        }
        NSLog(@"LibRaw exception (exif-only): %@", exception);
        return nil;
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
    unsigned short cw = raw->imgdata.sizes.raw_inset_crops[0].cwidth;
    unsigned short ch = raw->imgdata.sizes.raw_inset_crops[0].cheight;

    if (cw > 0 && ch > 0) {
        int flip = raw->imgdata.sizes.flip;
        BOOL isRotated90or270 = (flip == 5 || flip == 6);
        if (isRotated90or270) {
            exifDict[@"width"] = @(ch);
            exifDict[@"height"] = @(cw);
        } else {
            exifDict[@"width"] = @(cw);
            exifDict[@"height"] = @(ch);
        }
    } else {
        // Not populated for this file — fall back to LibRaw's own rotation-correct size
        exifDict[@"width"] = @(raw->imgdata.sizes.iwidth);
        exifDict[@"height"] = @(raw->imgdata.sizes.iheight);
    }

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

@end
