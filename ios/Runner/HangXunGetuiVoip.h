#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrappers around Getui VoIP / PushKit token APIs.
@interface HangXunGetuiVoip : NSObject

+ (void)registerPushKitToken:(NSData *)token;
+ (void)handlePushKitPayload:(NSDictionary *)payload;

@end

NS_ASSUME_NONNULL_END
