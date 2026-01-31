//
//  RawPhoto.m
//  Imagin Bridge
//
//  Created by Cristian Baluta on 31.01.2026.
//

#import "RawPhoto.h"

@implementation RawPhoto

- (instancetype)initWithImageData:(nullable NSData *)imageData exifData:(nullable NSDictionary *)exifData {
    self = [super init];
    if (self) {
        _imageData = imageData;
        _exifData = exifData;
    }
    return self;
}

@end