#import <Foundation/Foundation.h>
#import <GTSDK/GeTuiSdk.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrappers around Getui VoIP APIs (removed from getuiflut Dart layer).
@interface HangXunGetuiVoip : NSObject

+ (void)registerVoipTokenCredentials:(NSData *)token;
+ (void)handleVoipNotification:(NSDictionary *)payload;

@end

NS_ASSUME_NONNULL_END
