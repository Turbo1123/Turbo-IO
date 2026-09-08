#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#include "NativeVoiceVAD.h"

// Observed Objective-C interface in RayneoNet v1.2.35; no Apple private API.
FOUNDATION_EXPORT NSString * _Nullable RNProbeIdentifier(NSData * _Nonnull data, BOOL connectable);
FOUNDATION_EXPORT NSString * _Nonnull RNProbeDiagnosis(void);
FOUNDATION_EXPORT NSObject * _Nullable RNProbePeripheral(NSData * _Nonnull data, CBPeripheral * _Nonnull peripheral, NSDictionary * _Nonnull advertisement, NSDictionary * _Nonnull catalog);
FOUNDATION_EXPORT const void * _Nullable RNProbeConverterAddress(void);
FOUNDATION_EXPORT const void * _Nullable RNProbeCatalogAddress(void);
FOUNDATION_EXPORT CBPeripheral * _Nullable RNProbeSDKPeripheral(NSUUID * _Nonnull identifier);
FOUNDATION_EXPORT void RNProbeSetLogSink(void (^ _Nonnull sink)(NSString * _Nonnull));
FOUNDATION_EXPORT BOOL RNProbeMessageImageMatches(void);
// Offline dispatch only, with genuine SDK objects. Never sends a transport frame.
FOUNDATION_EXPORT BOOL RNProbeDispatchSyntheticReceive(const void * _Nonnull core, const void * _Nonnull message);
