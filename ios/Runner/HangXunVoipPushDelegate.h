#import <Foundation/Foundation.h>
#import <PushKit/PushKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol HangXunVoipPushHandling <NSObject>
- (void)hangxunDidUpdateVoipToken:(NSData *)token;
- (void)hangxunDidInvalidateVoipToken;
- (void)hangxunDidReceiveVoipPayload:(PKPushPayload *)payload
                          mustReport:(BOOL)mustReport
                          completion:(void (^)(void))completion;
@end

/// ObjC PushKit delegate so iOS 26.4 can choose the metadata selector.
/// Apple DTS: do not put both incoming methods on the same Swift class.
@interface HangXunVoipPushDelegate : NSObject <PKPushRegistryDelegate>
@property (nonatomic, weak, nullable) id<HangXunVoipPushHandling> handler;
@end

NS_ASSUME_NONNULL_END
