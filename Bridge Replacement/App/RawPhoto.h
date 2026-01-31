//
//  RawPhoto.h
//  Imagin Bridge
//
//  Created by Cristian Baluta on 31.01.2026.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RawPhoto : NSObject

@property (nonatomic, strong, nullable) NSData *imageData;
@property (nonatomic, strong, nullable) NSDictionary *exifData;

- (instancetype)initWithImageData:(nullable NSData *)imageData exifData:(nullable NSDictionary *)exifData;

@end

NS_ASSUME_NONNULL_END