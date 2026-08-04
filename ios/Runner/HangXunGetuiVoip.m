#import "HangXunGetuiVoip.h"
#import <GTSDK/GeTuiSdk.h>

@implementation HangXunGetuiVoip

+ (void)registerVoipTokenCredentials:(NSData *)token {
    // Avoid hard compile dependency: getuiflut 0.2.x commented out VoIP APIs.
    SEL sel = NSSelectorFromString(@"registerVoipTokenCredentials:");
    if ([GeTuiSdk respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [GeTuiSdk performSelector:sel withObject:token];
#pragma clang diagnostic pop
        NSLog(@"HangXun VoIP: GeTuiSdk.registerVoipTokenCredentials done");
    } else {
        NSLog(@"HangXun VoIP: GeTuiSdk missing registerVoipTokenCredentials:");
    }
}

+ (void)handleVoipNotification:(NSDictionary *)payload {
    SEL sel = NSSelectorFromString(@"handleVoipNotification:");
    if ([GeTuiSdk respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [GeTuiSdk performSelector:sel withObject:payload];
#pragma clang diagnostic pop
    }
}

@end
