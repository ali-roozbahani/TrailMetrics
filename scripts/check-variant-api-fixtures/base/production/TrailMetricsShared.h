#import <Foundation/NSObject.h>

@class TMSKoinHelper, TMSKotlinThrowable, TMSKotlinCancellationException;

@protocol TMSKotlinx_coroutines_coreJob, TMSKtor_ioByteReadChannel;

typedef id<TMSKoin_coreQualifier> _Nonnull Skie__TypeDef__0__id_TMSKoin_coreQualifier_ __attribute__((__swift_private__));

@protocol TMSKtor_ioByteReadChannel
@required
- (void)cancelCause:(TMSKotlinThrowable * _Nullable)cause __attribute__((swift_name("cancel(cause:)")));
@end

@protocol TMSKtor_ioByteWriteChannel
@required
- (void)cancelCause:(TMSKotlinThrowable * _Nullable)cause __attribute__((swift_name("cancel(cause:)")));
@end

@protocol TMSKotlinx_coroutines_coreJob <TMSKotlinCoroutineContextElement>
@required
- (void)cancelCause_:(TMSKotlinCancellationException * _Nullable)cause __attribute__((swift_name("cancel(cause_:)")));
@end

@protocol TMSKotlinx_coroutines_coreReceiveChannel
@required
- (void)cancelCause:(TMSKotlinCancellationException * _Nullable)cause __attribute__((swift_name("cancel(cause:)")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("KoinHelper")))
@interface TMSKoinHelper : TMSBase
- (instancetype)init __attribute__((swift_name("init()")));
+ (void)Skie_Suspend__3__loadDispatchReceiver:(id<TMSKoinHelper>)dispatchReceiver __attribute__((swift_name("Skie_Suspend__3__load(dispatchReceiver:)")));
@end
