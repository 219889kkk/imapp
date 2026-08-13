#import "HangXunVoipPushDelegate.h"

@implementation HangXunVoipPushDelegate

- (void)pushRegistry:(PKPushRegistry *)registry
didUpdatePushCredentials:(PKPushCredentials *)credentials
             forType:(PKPushType)type {
    if (![type isEqualToString:PKPushTypeVoIP]) {
        return;
    }
    [self.handler hangxunDidUpdateVoipToken:credentials.token];
}

- (void)pushRegistry:(PKPushRegistry *)registry
didInvalidatePushTokenForType:(PKPushType)type {
    (void)registry;
    (void)type;
    [self.handler hangxunDidInvalidateVoipToken];
}

/// iOS 13–26.3 (and fallback): every VoIP push must report CallKit before completion.
- (void)pushRegistry:(PKPushRegistry *)registry
didReceiveIncomingPushWithPayload:(PKPushPayload *)payload
             forType:(PKPushType)type
withCompletionHandler:(void (^)(void))completion {
    (void)registry;
    if (![type isEqualToString:PKPushTypeVoIP]) {
        if (completion) {
            completion();
        }
        return;
    }
    NSLog(@"HangXun VoIP: legacy incoming selector");
    [self.handler hangxunDidReceiveVoipPayload:payload mustReport:YES completion:completion];
}

/// iOS 26.4+: `metadata.mustReport` says whether CallKit is required.
- (void)pushRegistry:(PKPushRegistry *)registry
didReceiveIncomingVoIPPushWithPayload:(PKPushPayload *)payload
            metadata:(id)metadata
withCompletionHandler:(void (^)(void))completion {
    (void)registry;
    BOOL mustReport = YES;
    if ([metadata respondsToSelector:@selector(valueForKey:)]) {
        id value = [metadata valueForKey:@"mustReport"];
        if ([value respondsToSelector:@selector(boolValue)]) {
            mustReport = [value boolValue];
        }
    }
    NSLog(@"HangXun VoIP: iOS26 metadata mustReport=%d", mustReport ? 1 : 0);
    [self.handler hangxunDidReceiveVoipPayload:payload mustReport:mustReport completion:completion];
}

@end
