//
//  RawWrapper.h
//  Imagin Bridge
//
//  Created by Cristian Baluta on 29.01.2026.
//

#import <Foundation/Foundation.h>
#import "RawPhoto.h"

NS_ASSUME_NONNULL_BEGIN

@interface RawWrapper : NSObject

+ (instancetype)shared;
- (nullable RawPhoto *)extractRawPhoto:(NSString *)path;
- (nullable NSData *)extractEmbeddedJPEG:(NSString *)path; // Keep for backward compatibility

@end

NS_ASSUME_NONNULL_END
