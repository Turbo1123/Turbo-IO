#import "ProbeBridge.h"
#import <dlfcn.h>
#import <mach-o/loader.h>

// Minimal declarations recovered from CocoaLumberjack's ObjC method metadata.
@interface DDLogMessage : NSObject
@property(nonatomic, readonly) NSString *function;
@property(nonatomic, readonly) NSUInteger flag;
@property(nonatomic, readonly) NSUInteger line;
@property(nonatomic, readonly) NSString *message;
@end
@interface DDAbstractLogger : NSObject
- (void)logMessage:(DDLogMessage *)message;
@end
@interface DDLog : NSObject
+ (void)addLogger:(id)logger;
@end
@interface CoreProbeLogger : DDAbstractLogger
@property(nonatomic, copy) void (^sink)(NSString *);
@property(nonatomic, strong) NSMutableSet<NSString *> *seen;
@end
@implementation CoreProbeLogger
- (void)logMessage:(DDLogMessage *)message {
    NSString *function = message.function;
    if (!function.length || !self.sink) return;
    // Only source location and severity, NEVER message payload/credentials.
    NSString *line = [NSString stringWithFormat:@"SDK trace flag=%lu line=%lu %@", (unsigned long)message.flag, (unsigned long)message.line, function];
    if ([function isEqualToString:@"handleSendFailed(message:error:)"]) {
        // Emit only matched static error categories, never the SDK's message ID.
        for (NSString *category in @[@"peripheral not available", @"characteristic is not exist", @"write value code =", @"write data size exceeds", @"current connection state is", @"write value time out"]) {
            if ([message.message containsString:category]) line = [line stringByAppendingFormat:@" category=%@", category];
        }
    }
    if ([self.seen containsObject:line]) return;
    [self.seen addObject:line];
    void (^sink)(NSString *) = self.sink;
    dispatch_async(dispatch_get_main_queue(), ^{ sink(line); });
}
@end
void RNProbeSetLogSink(void (^sink)(NSString *)) {
    static CoreProbeLogger *logger;
    if (!logger) {
        logger = [CoreProbeLogger new];
        logger.seen = [NSMutableSet new];
        logger.sink = sink;
        [DDLog addLogger:logger];
    } else { logger.sink = sink; }
}

@protocol RNPeripheralRuntime <NSObject>
- (nullable instancetype)initWithData:(NSData *)data
                        localDevices:(nullable NSDictionary *)localDevices
                       isConnectable:(BOOL)connectable
                               error:(NSError * _Nullable * _Nullable)error;
- (NSString *)identifier;
- (void)setPeripheral:(CBPeripheral *)peripheral;
- (void)setUuid:(NSString *)uuid;
- (void)setDeviceName:(NSString *)name;
- (void)setAdvertisementData:(NSDictionary *)advertisement;
@end

static NSString *probeDiagnosis = @"not called";
NSString *RNProbeDiagnosis(void) { return probeDiagnosis; }

NSString *RNProbeIdentifier(NSData *data, BOOL connectable) {
    // @objc name verified in the framework's class list (not module-qualified).
    Class cls = NSClassFromString(@"RNPeripheral");
    SEL initializer = @selector(initWithData:localDevices:isConnectable:error:);
    if (!cls) { probeDiagnosis = @"runtime class missing"; return nil; }
    if (![cls instancesRespondToSelector:initializer]) { probeDiagnosis = @"initializer missing"; return nil; }
    NSError *error = nil;
    id<RNPeripheralRuntime> parsed = [(id<RNPeripheralRuntime>)[cls alloc]
        // This dictionary is a MODEL NAME catalog, not paired credentials.
        // parseAdv explicitly throws for nil; empty is sufficient for the ID.
        initWithData:data localDevices:@{} isConnectable:connectable error:&error];
    if (!parsed || error) {
        probeDiagnosis = [NSString stringWithFormat:@"parser error domain=%@ code=%ld", error.domain, (long)error.code];
        return nil;
    }
    if (![parsed respondsToSelector:@selector(identifier)]) { probeDiagnosis = @"identifier selector missing"; return nil; }
    probeDiagnosis = @"success";
    return [[parsed identifier] copy];
}

NSObject *RNProbePeripheral(NSData *data, CBPeripheral *peripheral, NSDictionary *advertisement, NSDictionary *catalog) {
    Class cls = NSClassFromString(@"RNPeripheral");
    if (![cls instancesRespondToSelector:@selector(initWithData:localDevices:isConnectable:error:)]) return nil;
    NSError *error = nil;
    BOOL connectable = [advertisement[CBAdvertisementDataIsConnectable] boolValue];
    id<RNPeripheralRuntime> parsed = [(id<RNPeripheralRuntime>)[cls alloc]
        initWithData:data localDevices:catalog isConnectable:connectable error:&error];
    if (!parsed || error) return nil;
    for (NSString *selector in @[@"setPeripheral:", @"setUuid:", @"setDeviceName:", @"setAdvertisementData:"]) {
        if (![parsed respondsToSelector:NSSelectorFromString(selector)]) return nil;
    }
    [parsed setPeripheral:peripheral];
    [parsed setUuid:peripheral.identifier.UUIDString];
    [parsed setDeviceName:peripheral.name ?: @"RayNeo"];
    [parsed setAdvertisementData:advertisement];
    return (NSObject *)parsed;
}

static const uint8_t *RNProbeImageBase(void) {
    // Calls existing signed code inside THIS process, never patches memory.
    // Research-only offset for RNCompUtil.convertDevice(rnPer:), specialized
    // static-self argument removed. Fail closed for every other Mach-O UUID.
    void *export = dlsym(RTLD_DEFAULT, "$s9RayneoNet13RNCoreConnectC10SDKVersionSSSgvgZ");
    Dl_info info = {0};
    if (!export || !dladdr(export, &info) || !info.dli_fbase) return NULL;
    const struct mach_header_64 *header = info.dli_fbase;
    if (header->magic != MH_MAGIC_64) return NULL;
    const uint8_t expected[16] = {0xbf,0x1c,0xd6,0x61,0xbc,0x2c,0x38,0x92,0x92,0x92,0x45,0xb7,0xa9,0xf4,0x4a,0x36};
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (end - cursor < sizeof(struct load_command)) return NULL;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > end - cursor) return NULL;
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uuid = (const struct uuid_command *)command;
            if (memcmp(uuid->uuid, expected, sizeof(expected))) return NULL;
            return (const uint8_t *)header;
        }
        cursor += command->cmdsize;
    }
    return NULL;
}

const void *RNProbeConverterAddress(void) {
    const uint8_t *base = RNProbeImageBase();
    return base ? base + 0x457b0 : NULL;
}

BOOL RNProbeMessageImageMatches(void) {
    return RNProbeImageBase() != NULL;
}

BOOL RNProbeDispatchSyntheticReceive(const void *core, const void *message) {
    const uint8_t *base = RNProbeImageBase();
    if (!base || !core || !message || !NSThread.isMainThread) return NO;
    // Swift method self lives in x20; clang's swift_context parameter handles
    // this ABI without generated executable memory or an assembly trampoline.
    // 0x115b38 only dispatches to RNMessageDelegate; it is NOT the send entry.
    typedef void (*Receiver)(const void *, const void * __attribute__((swift_context)))
                         __attribute__((swiftcall));
    ((Receiver)(base + 0x115b38))(message, core);
    return YES;
}

const void *RNProbeCatalogAddress(void) {
    const uint8_t *base = RNProbeImageBase();
    return base ? base + 0x120168 : NULL;
}

CBPeripheral *RNProbeSDKPeripheral(NSUUID *identifier) {
    // Read this exact SDK's initialized singleton/field, then resolve with the
    // public CoreBluetooth API. A CBPeripheral belongs to its central manager;
    // never hand the SDK our separate scanner's object. No state is patched.
    const uint8_t *base = RNProbeImageBase();
    if (!base || !NSThread.isMainThread) return nil;
    const void *manager = *(const void * const *)(base + 0x1b9568);
    if (!manager) return nil;
    uintptr_t offset = *(const uintptr_t *)(base + 0x1aa648);
    if (offset < 16 || offset > 4096) return nil;
    const void *raw = *(const void * const *)((const uint8_t *)manager + offset);
    if (!raw) return nil;
    CBCentralManager *central = (__bridge CBCentralManager *)raw;
    if (![central isKindOfClass:CBCentralManager.class] || central.state != CBManagerStatePoweredOn) return nil;
    return [central retrievePeripheralsWithIdentifiers:@[identifier]].firstObject;
}
