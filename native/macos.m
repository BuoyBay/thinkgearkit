/* Direct IOBluetooth RFCOMM transport. Own all calls on the main thread.
 * This is an opt-in Bluetooth connection to an already paired device; no pairing.
 * Based on the sibling mind-games driver, using the public macOS SDK ABI. */
#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
#define TG_API __attribute__((visibility("default")))

static char tgMacError[512];
static int64_t tgMacNext = 1;
static NSMutableDictionary<NSNumber *, id> *tgMacSessions;
static void tgMacSetError(NSString *message) {
    snprintf(tgMacError, sizeof(tgMacError), "%s", message.UTF8String ?: "Bluetooth transport failed");
}
static BOOL tgMacMain(void) {
    if ([NSThread isMainThread]) return YES;
    tgMacSetError(@"MindWave RFCOMM must be used on the macOS main thread");
    return NO;
}
static double tgMacTime(void) { return NSProcessInfo.processInfo.systemUptime; }
static BOOL tgMacMatches(NSString *wanted, NSString *name, NSString *address) {
    if (!wanted.length || [wanted caseInsensitiveCompare:@"auto"] == NSOrderedSame ||
        [wanted caseInsensitiveCompare:@"mindwave"] == NSOrderedSame) {
        return [name.lowercaseString hasPrefix:@"mindwave"];
    }
    return (address && [address caseInsensitiveCompare:wanted] == NSOrderedSame) ||
           (name && [name caseInsensitiveCompare:wanted] == NSOrderedSame);
}

@interface TGMacRFCOMM : NSObject <IOBluetoothRFCOMMChannelDelegate> {
@public
    IOBluetoothDevice *device;
    IOBluetoothRFCOMMChannel *channel;
    NSMutableData *bytes;
    NSUInteger readOffset;
    NSInteger phase; /* 1 SDP, 2 opening, 3 streaming, -1 failure */
    BOOL openDone, channelClosed;
    IOReturn openResult;
    double phaseStart, lastData;
    NSString *error;
}
- (void)tick;
- (void)stop;
- (void)fail:(NSString *)message;
@end
@implementation TGMacRFCOMM
- (instancetype)init {
    if ((self = [super init])) { bytes = [NSMutableData data]; phase = 1; phaseStart = tgMacTime(); }
    return self;
}
- (void)fail:(NSString *)message { @synchronized(self) { error = message; phase = -1; } }
- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel *)sender data:(void *)data length:(size_t)length {
    (void)sender;
    @synchronized(self) {
        if (phase < 0 || !data || length == 0) return;
        if (length > 1048576 || bytes.length - readOffset > 1048576 - length) {
            [self fail:@"Bluetooth input queue overflow; poll more frequently and reconnect"];
            return;
        }
        if (readOffset) {
            [bytes replaceBytesInRange:NSMakeRange(0, readOffset) withBytes:NULL length:0];
            readOffset = 0;
        }
        [bytes appendBytes:data length:length]; lastData = tgMacTime();
    }
}
- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel *)sender status:(IOReturn)status {
    (void)sender;
    @synchronized(self) { openDone = YES; openResult = status; lastData = tgMacTime(); }
}
- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel *)sender {
    (void)sender;
    @synchronized(self) { channelClosed = YES; }
}
- (void)tick {
    @synchronized(self) {
        double now = tgMacTime();
        if (phase == 1) {
            /* Query without a callback target so disconnect during SDP cannot leave
             * a callback referencing a released session. Poll the OS cache after 2s. */
            if (now - phaseStart < 2) return;
            IOBluetoothSDPServiceRecord *record = [device getServiceRecordForUUID:[IOBluetoothSDPUUID uuid16:0x1101]];
            if (!record) {
                if (now - phaseStart > 12) [self fail:@"Paired device has no MindWave SPP service (UUID 0x1101)"];
                return;
            }
            BluetoothRFCOMMChannelID channelID = 0;
            IOReturn result = [record getRFCOMMChannelID:&channelID];
            if (result != kIOReturnSuccess || !channelID) {
                [self fail:[NSString stringWithFormat:@"SPP channel lookup failed: 0x%x", result]]; return;
            }
            IOBluetoothRFCOMMChannel *opened = nil;
            phase = 2; phaseStart = now;
            result = [device openRFCOMMChannelAsync:&opened withChannelID:channelID delegate:self];
            channel = opened;
            if (result != kIOReturnSuccess || !channel) {
                [self fail:[NSString stringWithFormat:@"Bluetooth RFCOMM open failed: 0x%x", result]];
            }
        } else if (phase == 2) {
            if (openDone) {
                if (openResult == kIOReturnSuccess) phase = 3;
                else [self fail:[NSString stringWithFormat:@"Bluetooth RFCOMM connection failed: 0x%x", openResult]];
            } else if (now - phaseStart > 15) [self fail:@"Bluetooth RFCOMM open timed out"];
        } else if (phase == 3) {
            if (channelClosed) [self fail:@"Bluetooth RFCOMM channel closed"];
            else if (now - lastData > 8) [self fail:@"Bluetooth stream silent for eight seconds; reconnect"];
        }
    }
}
- (void)stop {
    /* The channel's delegate is not owned: detach before releasing either object. */
    IOBluetoothRFCOMMChannel *closing = channel;
    if (closing) { [closing setDelegate:nil]; [closing closeChannel]; }
    channel = nil; device = nil;
    @synchronized(self) { [bytes setLength:0]; readOffset = 0; phase = -1; }
}
@end

TG_API int64_t tg_macos_open_rfcomm(const char *selector) {
    if (!tgMacMain()) return 0;
    @autoreleasepool {
        tgMacError[0] = 0;
        if (!selector || strlen(selector) > 1024) { tgMacSetError(@"Invalid MindWave device name/address"); return 0; }
        NSString *wanted = [NSString stringWithUTF8String:selector];
        if (!wanted) { tgMacSetError(@"Device name/address must be UTF-8"); return 0; }
        if (tgMacSessions.count >= 32 || tgMacNext == INT64_MAX) { tgMacSetError(@"Too many Bluetooth sessions"); return 0; }
        IOBluetoothDevice *selected = nil;
        NSArray *paired = [[IOBluetoothDevice pairedDevices] sortedArrayUsingComparator:^NSComparisonResult(IOBluetoothDevice *a, IOBluetoothDevice *b) {
            return [(a.addressString ?: @"") compare:(b.addressString ?: @"")];
        }];
        for (IOBluetoothDevice *candidate in paired) {
            BOOL match = tgMacMatches(wanted, candidate.name, candidate.addressString);
            if (match) { selected = candidate; break; }
        }
        if (!selected) { tgMacSetError(@"No matching paired MindWave; pair the headset in macOS Bluetooth settings"); return 0; }
        for (TGMacRFCOMM *existing in tgMacSessions.allValues) {
            if ([existing->device.addressString isEqualToString:selected.addressString]) {
                tgMacSetError(@"This headset already has an open RFCOMM session"); return 0;
            }
        }
        TGMacRFCOMM *session = [TGMacRFCOMM new]; session->device = selected;
        IOReturn result = [selected performSDPQuery:nil];
        if (result != kIOReturnSuccess) { tgMacSetError([NSString stringWithFormat:@"Bluetooth SDP request failed: 0x%x", result]); return 0; }
        if (!tgMacSessions) tgMacSessions = [NSMutableDictionary dictionary];
        int64_t handle = tgMacNext++; tgMacSessions[@(handle)] = session;
        return handle;
    }
}
static TGMacRFCOMM *tgMacGet(int64_t handle) {
    TGMacRFCOMM *session = tgMacSessions[@(handle)];
    if (!session) tgMacSetError(@"Invalid or closed RFCOMM handle");
    return session;
}
TG_API int64_t tg_macos_status(int64_t handle) {
    if (!tgMacMain()) return 0;
    @autoreleasepool {
        TGMacRFCOMM *session = tgMacGet(handle); if (!session) return 0;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
        [session tick];
        @synchronized(session) {
            if (session->phase < 0) { tgMacSetError(session->error ?: @"Bluetooth session closed"); return 0; }
            return session->phase == 3 ? 2 : 1;
        }
    }
}
TG_API int64_t tg_macos_read_byte(int64_t handle) {
    if (!tgMacMain()) return -2;
    @autoreleasepool {
        TGMacRFCOMM *session = tgMacGet(handle); if (!session) return -2;
        /* Run the framework and connection state machine once per empty queue. */
        @synchronized(session) {
            if (session->readOffset < session->bytes.length) return ((const uint8_t *)session->bytes.bytes)[session->readOffset++];
        }
        if (tg_macos_status(handle) == 0) return -2;
        @synchronized(session) {
            if (session->readOffset < session->bytes.length) return ((const uint8_t *)session->bytes.bytes)[session->readOffset++];
            [session->bytes setLength:0]; session->readOffset = 0;
        }
        return -1;
    }
}
TG_API void tg_macos_close(int64_t handle) {
    if (!tgMacMain()) return;
    @autoreleasepool {
        TGMacRFCOMM *session = tgMacGet(handle); if (!session) return;
        [session stop]; [tgMacSessions removeObjectForKey:@(handle)];
    }
}
TG_API const char *tg_macos_error(void) { return tgMacError; }
