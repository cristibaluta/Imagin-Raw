//
//  RawWrapper.h
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

#import <Foundation/Foundation.h>
#import "RawPhoto.h"

NS_ASSUME_NONNULL_BEGIN

@interface RawWrapper : NSObject

+ (instancetype)shared;
- (nullable RawPhoto *)extractRawPhoto:(NSString *)path;
- (nullable NSData *)extractEmbeddedJPEG:(NSString *)path;
- (nullable NSDictionary *)extractMetadata:(NSString *)path;
- (nullable NSImage *)extractFullResolution:(NSString *)path; // Full demosaiced decode via LibRaw (half_size)

@end

NS_ASSUME_NONNULL_END
