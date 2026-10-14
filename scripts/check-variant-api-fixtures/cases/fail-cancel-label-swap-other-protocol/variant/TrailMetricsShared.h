#import <Foundation/NSObject.h>

@class TMSUiTestScenario, TMSUiTestEntryKt, TMSUiTestControls, TMSKoinHelper, TMSKotlinThrowable, TMSKotlinCancellationException;

@protocol TMSKotlinx_coroutines_coreJob, TMSKtor_ioByteReadChannel;

typedef id<TMSKoin_coreQualifier> _Nonnull Skie__TypeDef__4__id_TMSKoin_coreQualifier_ __attribute__((__swift_private__));

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
- (void)cancelCause_:(TMSKotlinCancellationException * _Nullable)cause __attribute__((swift_name("cancel(cause_:)")));
@end

/** What a UI test reads and drives in one launch. */
__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("UiTestControls")))
@interface TMSUiTestControls : TMSBase
@property (readonly) int32_t saveCount __attribute__((swift_name("saveCount")));
- (void)releaseHeldCalls __attribute__((swift_name("releaseHeldCalls()")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("UiTestScenario")))
@interface TMSUiTestScenario : TMSKotlinEnum<TMSUiTestScenario *>
@property (class, readonly) TMSUiTestScenario *faileddelete __attribute__((swift_name("faileddelete")));
+ (TMSKotlinArray<TMSUiTestScenario *> *)values __attribute__((swift_name("values()")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("KoinHelper")))
@interface TMSKoinHelper : TMSBase
+ (void)Skie_Suspend__9__loadDispatchReceiver:(id<TMSKoinHelper>)dispatchReceiver __attribute__((swift_name("Skie_Suspend__9__load(dispatchReceiver:)")));
- (instancetype)init __attribute__((swift_name("init()")));
@end

__attribute__((objc_subclassing_restricted))
__attribute__((swift_name("UiTestEntryKt")))
@interface TMSUiTestEntryKt : TMSBase
+ (TMSUiTestControls *)doInitKoinIosForUiTestScenario:(TMSUiTestScenario *)scenario __attribute__((swift_name("doInitKoinIosForUiTest(scenario:)")));
@end
