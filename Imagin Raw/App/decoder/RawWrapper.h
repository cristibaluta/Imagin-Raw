//
//  RawWrapper.h
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

#import <Foundation/Foundation.h>
#import "RawPhoto.h"

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#elif TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface RawWrapper : NSObject

+ (instancetype)shared;
- (nullable RawPhoto *)extractRawPhoto:(NSString *)path;
- (nullable NSData *)extractEmbeddedJPEG:(NSString *)path;
- (nullable NSDictionary *)extractMetadata:(NSString *)path;
#if TARGET_OS_OSX
- (nullable NSImage *)extractFullResolution:(NSString *)path;
#elif TARGET_OS_IPHONE
- (nullable UIImage *)extractFullResolution:(NSString *)path;
#endif

@end

NS_ASSUME_NONNULL_END
