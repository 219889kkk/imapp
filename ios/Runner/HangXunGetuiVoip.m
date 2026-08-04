#import "HangXunGetuiVoip.h"

@implementation HangXunGetuiVoip

+ (void)registerPushKitToken:(NSData *)token {
    // Newer GTSDK: registerTokenCredentials:  | older: registerVoipTokenCredentials:
    Class cls = NSClassFromString(@"GeTuiSdk");
    if (cls == Nil) {
        NSLog(@"HangXun VoIP: GeTuiSdk class not found");
        return;
    }
    SEL newer = NSSelectorFromString(@"registerTokenCredentials:");
    SEL older = NSSelectorFromString(@"registerVoipTokenCredentials:");
    SEL sel = [cls respondsToSelector:newer] ? newer :
              ([cls respondsToSelector:older] ? older : NULL);
    if (sel == NULL) {
        NSLog(@"HangXun VoIP: no Getui token-credentials selector");
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [cls performSelector:sel withObject:token];
#pragma clang diagnostic pop
    NSLog(@"HangXun VoIP: Getui token credentials registered via %@", NSStringFromSelector(sel));
}

+ (void)handlePushKitPayload:(NSDictionary *)payload {
    Class cls = NSClassFromString(@"GeTuiSdk");
    if (cls == Nil) return;
    SEL newer = NSSelectorFromString(@"handleNotification:");
    SEL older = NSSelectorFromString(@"handleVoipNotification:");
    SEL sel = [cls respondsToSelector:newer] ? newer :
              ([cls respondsToSelector:older] ? older : NULL);
    if (sel == NULL) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [cls performSelector:sel withObject:payload];
#pragma clang diagnostic pop
}

@end
