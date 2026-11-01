/* Direct Mobile 2 CoreBluetooth transport. Main-thread lifecycle, manual retain/release.
 * The byte ABI returns normalized JSON, never fabricated serial frames.
 * Profile facts: sibling mind-games/src/ble_protocol.rs, see BLE-README.md.
 */
#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <mach/mach_time.h>
#define API __attribute__((visibility("default")))
static NSString *const TGService = @"039afff0-2c94-11e3-9e06-0002a5d5c51b";
static NSString *const TGSense = @"039afff8-2c94-11e3-9e06-0002a5d5c51b";
static NSString *const TGRaw = @"039afff4-2c94-11e3-9e06-0002a5d5c51b";
static NSString *const TGCommand = @"039affa0-2c94-11e3-9e06-0002a5d5c51b";
static BOOL tg_ble_target_matches(NSString *selected, NSString *name, NSString *identifier) {
    if([selected length]==0 || [selected caseInsensitiveCompare:@"auto"]==NSOrderedSame)return YES;
    if([selected caseInsensitiveCompare:@"MindWave"]==NSOrderedSame)return [name rangeOfString:@"mindwave" options:NSCaseInsensitiveSearch|NSAnchoredSearch].location==0;
    return [selected caseInsensitiveCompare:identifier]==NSOrderedSame || [selected caseInsensitiveCompare:name]==NSOrderedSame;
}
API double tg_ble_monotonic_seconds(void) {
    mach_timebase_info_data_t info;mach_timebase_info(&info);
    return (double)mach_continuous_time()*(double)info.numer/(double)info.denom/1e9;
}
static NSString *tg_ble_bounded_text(NSString *text, NSUInteger limit) {
    text=text?:@"";
    NSUInteger count=MIN(text.length,limit);
    if(count<text.length && count && CFStringIsSurrogateHighCharacter([text characterAtIndex:count-1]) && CFStringIsSurrogateLowCharacter([text characterAtIndex:count]))count--;
    NSMutableString *result=[NSMutableString stringWithCapacity:count];
    for(NSUInteger i=0;i<count;i++) {
        unichar c=[text characterAtIndex:i];
        if(CFStringIsSurrogateHighCharacter(c)) {
            if(i+1<count && CFStringIsSurrogateLowCharacter([text characterAtIndex:i+1])) {
                unichar pair[2]={c,[text characterAtIndex:++i]};[result appendString:[NSString stringWithCharacters:pair length:2]];continue;
            }
            c=0xfffd;
        } else if(CFStringIsSurrogateLowCharacter(c))c=0xfffd;
        [result appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return result;
}
static char ble_error[512];
static void ble_set_error(NSString *text) { snprintf(ble_error,sizeof(ble_error),"%s",[text UTF8String]?:"CoreBluetooth failure"); }

@interface TGMobileBle : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate> {
@public
    CBCentralManager *manager;
    CBPeripheral *peripheral;
    CBCharacteristic *command, *sense, *raw;
    NSString *target;
    NSMutableData *bytes;
    NSUInteger cursor;
    NSInteger phase;
    BOOL senseNotify, rawNotify;
    CFAbsoluteTime deadline, lastData;
    NSString *failure;
    NSMutableArray *events;
    NSData *borrowedEvent;
    NSUInteger eventBytes;
    uint64_t sequence, droppedEvents, droppedBytes, reportedDrops;
    double firstDroppedAt, lastDroppedAt;
    BOOL eventsOverflowed;
}
- (void)fail:(NSString *)message;
- (void)emit:(NSString *)line;
- (void)sendStart:(uint8_t)operation;
- (BOOL)capture:(CBCharacteristic *)ch error:(NSError *)error;
- (const char *)drainEvent;
- (void)close;
@end
@implementation TGMobileBle
- (instancetype)init {
    self=[super init];
    if(self) { bytes=[[NSMutableData alloc] init];events=[[NSMutableArray alloc] init]; phase=1; deadline=tg_ble_monotonic_seconds()+15; }
    return self;
}
- (void)fail:(NSString *)message {
    if(phase==0)return;
    phase=0; [failure release]; failure=[tg_ble_bounded_text(message,4096) copy]; ble_set_error(failure);
    [manager stopScan];
    if(peripheral) { peripheral.delegate=nil; [manager cancelPeripheralConnection:peripheral]; }
    // Keep previously accepted normalized records readable after failure.
    // Gameplay observes failed status immediately; recording can finish draining.
}
- (void)emit:(NSString *)line {
    if(phase==0)return;
    NSData *encoded=[line dataUsingEncoding:NSUTF8StringEncoding];
    if(!encoded)return;
    if(cursor) { [bytes replaceBytesInRange:NSMakeRange(0,cursor) withBytes:NULL length:0];cursor=0; }
    if([bytes length]+[encoded length]>262144) { [self fail:@"BLE receive buffer overflow; poll more frequently"];return; }
    [bytes appendData:encoded];lastData=tg_ble_monotonic_seconds();
}
- (BOOL)capture:(CBCharacteristic *)ch error:(NSError *)error {
    double at=tg_ble_monotonic_seconds();
    sequence++;
    NSData *value=ch.value;
    NSUInteger n=value.length;
    if(eventsOverflowed) {
        if(droppedEvents<UINT64_MAX)droppedEvents++;
        droppedBytes=UINT64_MAX-droppedBytes<n?UINT64_MAX:droppedBytes+n;
        lastDroppedAt=at;return NO;
    }
    BOOL accepted=NO;
    NSString *reason=@"unknown_characteristic";
    const uint8_t *b=value.bytes;
    if(phase==0)reason=@"stream_failed";
    else if(error)reason=@"notification_error";
    else if(ch==raw) { accepted=n==20;reason=accepted?@"accepted":@"invalid_raw_length"; }
    else if(ch==sense) {
        if(n<3)reason=@"invalid_esense_length";
        else if(b[2]==0xea) { accepted=n>=11 && b[8]<=100 && b[10]<=100;reason=accepted?@"accepted":@"invalid_esense_scores_or_length"; }
        else if(b[2]==0xeb || b[2]==0xec) { accepted=n==20;reason=accepted?@"accepted":@"invalid_band_length"; }
        else reason=@"unknown_esense_tag";
    }
    NSString *originalUUID=ch.UUID.UUIDString?:@"";
    NSString *uuid=tg_ble_bounded_text(originalUUID,128);
    // A single event beyond the total byte budget cannot be retained. Count it
    // explicitly and preserve all earlier events; never silently truncate bytes.
    if(n>2097152)goto overflow;
    NSMutableString *hex=[NSMutableString stringWithCapacity:n*2];
    for(NSUInteger i=0;i<n;i++)[hex appendFormat:@"%02x",b[i]];
    NSString *domain=error.domain?:@"", *message=error.localizedDescription?:@"";
    BOOL truncated=domain.length>4096 || message.length>4096 || originalUUID.length>128;
    NSString *safeDomain=tg_ble_bounded_text(domain,4096), *safeMessage=tg_ble_bounded_text(message,4096);
    BOOL sanitized=![safeDomain isEqualToString:[domain substringToIndex:safeDomain.length]] || ![safeMessage isEqualToString:[message substringToIndex:safeMessage.length]] || ![uuid isEqualToString:[originalUUID substringToIndex:uuid.length]];
    id errorInfo=error?@{@"domain":safeDomain,@"code":@(error.code),@"message":safeMessage,@"domain_original_length":@(domain.length),@"message_original_length":@(message.length)}:[NSNull null];
    NSDictionary *event=@{@"seq":@(sequence),@"monotonic_seconds":@(at),@"protocol":@"mindwave-ble",@"uuid":uuid,@"bytes_hex":hex,@"length":@(n),@"had_value":(value!=nil?@YES:@NO),@"value_may_be_cached":(error!=nil?@YES:@NO),@"metadata_truncated":@(truncated),@"metadata_sanitized":@(sanitized),@"uuid_original_length":@(originalUUID.length),@"accepted":@(accepted),@"reason":reason,@"integrity":@"bluetooth_stack_no_payload_checksum",@"error":errorInfo};
    NSData *encoded=[NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
    if(!encoded || events.count>=4096 || encoded.length>4194304-eventBytes)goto overflow;
    [events addObject:encoded];eventBytes+=encoded.length;
    return accepted;
overflow:
    eventsOverflowed=YES;droppedEvents=1;droppedBytes=n;firstDroppedAt=lastDroppedAt=at;
    [self fail:@"BLE original-notification queue overflow; recording incomplete; drain events before close"];
    return NO;
}
- (const char *)drainEvent {
    [borrowedEvent release];borrowedEvent=nil;
    NSData *next=nil;
    if(events.count) {
        next=[[events objectAtIndex:0] retain];eventBytes-=next.length;[events removeObjectAtIndex:0];
    } else if(droppedEvents>reportedDrops) {
        NSDictionary *loss=@{@"protocol":@"mindwave-ble",@"event_type":@"overflow",@"seq":@(sequence),@"monotonic_seconds":@(lastDroppedAt),@"first_dropped_monotonic_seconds":@(firstDroppedAt),@"uuid":@"",@"bytes_hex":@"",@"length":@0,@"accepted":@NO,@"reason":@"recording_queue_overflow",@"integrity":@"recording_incomplete",@"error":[NSNull null],@"dropped_count":@(droppedEvents),@"dropped_bytes":@(droppedBytes)};
        next=[[NSJSONSerialization dataWithJSONObject:loss options:0 error:NULL] retain];reportedDrops=droppedEvents;
    }
    if(!next)return NULL;
    NSMutableData *terminated=[NSMutableData dataWithData:next];[next release];uint8_t zero=0;[terminated appendBytes:&zero length:1];borrowedEvent=[terminated copy];return borrowedEvent.bytes;
}
- (void)sendStart:(uint8_t)operation {
    uint8_t envelope[20]={0};envelope[0]=0x77;envelope[1]=1;envelope[2]=operation;
    envelope[19]=(uint8_t)~(uint8_t)(1+operation);
    [peripheral writeValue:[NSData dataWithBytes:envelope length:20] forCharacteristic:command type:CBCharacteristicWriteWithResponse];
}
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if(phase==0)return;
    if(central.state==CBManagerStatePoweredOn) {
        phase=2;deadline=tg_ble_monotonic_seconds()+15;
        [central scanForPeripheralsWithServices:nil options:nil];
    } else if(central.state==CBManagerStateUnauthorized) [self fail:@"Bluetooth permission is not authorized"];
    else if(central.state==CBManagerStateUnsupported) [self fail:@"CoreBluetooth is unsupported"];
    else if(central.state==CBManagerStatePoweredOff) [self fail:@"Bluetooth is powered off"];
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)found advertisementData:(NSDictionary<NSString *, id> *)advertisement RSSI:(NSNumber *)RSSI {
    (void)RSSI;
    if(phase!=2)return;
    NSString *name=advertisement[CBAdvertisementDataLocalNameKey]?:found.name?:@"";
    if([name rangeOfString:@"mindwave" options:NSCaseInsensitiveSearch].location==NSNotFound)return;
    if(!tg_ble_target_matches(target,name,found.identifier.UUIDString))return;
    peripheral=[found retain]; [central stopScan];phase=3;deadline=tg_ble_monotonic_seconds()+10;
    [central connectPeripheral:found options:nil];
}
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)connected {
    (void)central;
    if(phase!=3 || connected!=peripheral)return;
    phase=4;deadline=tg_ble_monotonic_seconds()+10;peripheral.delegate=self;
    [peripheral discoverServices:@[[CBUUID UUIDWithString:TGService]]];
}
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)device error:(NSError *)error {
    (void)central;(void)device;[self fail:error.localizedDescription?:@"BLE connection failed"];
}
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)device error:(NSError *)error {
    (void)central;(void)device;[self fail:error.localizedDescription?:@"BLE disconnected"];
}
- (void)peripheral:(CBPeripheral *)device didDiscoverServices:(NSError *)error {
    if(phase!=4)return;
    if(error) { [self fail:error.localizedDescription];return; }
    for(CBService *service in device.services)if([service.UUID isEqual:[CBUUID UUIDWithString:TGService]]) {
        [device discoverCharacteristics:@[[CBUUID UUIDWithString:TGSense],[CBUUID UUIDWithString:TGRaw],[CBUUID UUIDWithString:TGCommand]] forService:service];return;
    }
    [self fail:@"MindWave BLE service is missing"];
}
- (void)peripheral:(CBPeripheral *)device didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if(phase!=4)return;
    if(error) { [self fail:error.localizedDescription];return; }
    for(CBCharacteristic *ch in service.characteristics) {
        if([ch.UUID isEqual:[CBUUID UUIDWithString:TGCommand]])command=[ch retain];
        if([ch.UUID isEqual:[CBUUID UUIDWithString:TGSense]])sense=[ch retain];
        if([ch.UUID isEqual:[CBUUID UUIDWithString:TGRaw]])raw=[ch retain];
    }
    if(!command || !sense || !raw) { [self fail:@"Required BLE command/raw/eSense characteristic is missing"];return; }
    if(!(command.properties&CBCharacteristicPropertyWrite) || !(sense.properties&CBCharacteristicPropertyNotify) || !(raw.properties&CBCharacteristicPropertyNotify)) {
        [self fail:@"MindWave BLE characteristic properties do not support required writes/notifications"];return;
    }
    phase=5;deadline=tg_ble_monotonic_seconds()+10;
    [device setNotifyValue:YES forCharacteristic:sense];[device setNotifyValue:YES forCharacteristic:raw];
}
- (void)peripheral:(CBPeripheral *)device didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)ch error:(NSError *)error {
    (void)device;
    if(phase!=5)return;
    if(error || !ch.isNotifying) { [self fail:error.localizedDescription?:@"BLE notification subscription failed"];return; }
    if(ch==sense)senseNotify=YES;if(ch==raw)rawNotify=YES;
    if(senseNotify && rawNotify) { phase=6;[self sendStart:0x17]; }
}
- (void)peripheral:(CBPeripheral *)device didWriteValueForCharacteristic:(CBCharacteristic *)ch error:(NSError *)error {
    (void)device;
    if(ch!=command || (phase!=6 && phase!=7))return;
    if(error) { [self fail:error.localizedDescription];return; }
    if(phase==6) { phase=7;[self sendStart:0x15]; }
    else { phase=8;lastData=tg_ble_monotonic_seconds(); }
}
- (void)peripheral:(CBPeripheral *)device didUpdateValueForCharacteristic:(CBCharacteristic *)ch error:(NSError *)error {
    (void)device;
    BOOL accepted=[self capture:ch error:error];
    if(error) { [self fail:error.localizedDescription];return; }
    if(!accepted)return;
    const uint8_t *b=ch.value.bytes;NSUInteger n=ch.value.length;if(!b)return;
    if(ch==raw) {
        if(n!=20)return;
        for(NSUInteger i=0;i<20;i+=2) {
            int value=((int)b[i]<<8)|b[i+1];if(value>=32768)value-=65536;
            [self emit:[NSString stringWithFormat:@"{\"rawEeg\":%d}\n",value]];
        }
    } else if(ch==sense && n>=3) {
        if(b[2]==0xea && n>=11 && b[8]<=100 && b[10]<=100) {
            [self emit:[NSString stringWithFormat:@"{\"poorSignalLevel\":%u,\"eSense\":{\"attention\":%u,\"meditation\":%u}}\n",b[6],b[8],b[10]]];
        } else if((b[2]==0xeb || b[2]==0xec) && n==20) {
            const char *names[8]={"delta","theta","lowAlpha","highAlpha","lowBeta","highBeta","lowGamma","highGamma"};
            NSMutableString *line=[NSMutableString stringWithString:@"{\"eegPower\":{"];
            int start=b[2]==0xeb?0:4;
            for(int i=0;i<4;i++) {
                int offset=5+i*4;uint32_t value=((uint32_t)b[offset]<<16)|((uint32_t)b[offset+1]<<8)|b[offset+2];
                [line appendFormat:@"%s\"%s\":%u",i?",":"",names[start+i],value];
            }
            [line appendString:@"}}\n"];[self emit:line];
        }
    }
}
- (void)close {
    phase=0;[manager stopScan];manager.delegate=nil;
    if(peripheral) { peripheral.delegate=nil;[manager cancelPeripheralConnection:peripheral]; }
}
- (void)dealloc {
    [self close];[manager release];[peripheral release];[command release];[sense release];[raw release];[target release];[bytes release];[failure release];[events release];[borrowedEvent release];[super dealloc];
}
@end
static TGMobileBle *sessions[16];
static int64_t tokens[16], nextToken=1;
static TGMobileBle *lookup(int64_t token) {
    if(![NSThread isMainThread]) { ble_set_error(@"BLE lifecycle must run on the main thread");return nil; }
    for(int i=0;i<16;i++)if(sessions[i] && tokens[i]==token)return sessions[i];
    ble_set_error(@"Invalid or closed BLE handle");return nil;
}
API const char *tg_ble_error(void) { return ble_error; }
API int64_t tg_ble_open(const char *name) {
    @autoreleasepool {
        if(![NSThread isMainThread]) { ble_set_error(@"BLE lifecycle must run on the main thread");return 0; }
        NSString *selected=name?[NSString stringWithUTF8String:name]:@"auto";
        if(!selected || [selected length]>256) { ble_set_error(@"Invalid BLE target name/UUID");return 0; }
        for(int i=0;i<16;i++)if(!sessions[i]) {
            TGMobileBle *session=[[TGMobileBle alloc] init];session->target=[selected copy];
            sessions[i]=session;tokens[i]=nextToken;nextToken=nextToken==INT64_MAX?1:nextToken+1;
            session->manager=[[CBCentralManager alloc] initWithDelegate:session queue:nil options:nil];
            if(!session->manager) { [session release];sessions[i]=nil;ble_set_error(@"Could not initialize CoreBluetooth");return 0; }
            return tokens[i];
        }
        ble_set_error(@"BLE transport capacity (16) reached");return 0;
    }
}
API int64_t tg_ble_status(int64_t token) {
    @autoreleasepool {
        TGMobileBle *s=lookup(token);if(!s)return 0;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,0,true);
        CFAbsoluteTime now=tg_ble_monotonic_seconds();
        if(s->phase>0 && s->phase<8 && now>s->deadline)[s fail:@"BLE discovery/connection/configuration timed out"];
        if(s->phase==8 && now-s->lastData>5)[s fail:@"No decoded BLE measurements for five seconds"];
        if(s->phase==0) { ble_set_error(s->failure?:@"BLE disconnected");return 0; }
        return s->phase==8?2:1;
    }
}
API int64_t tg_ble_read_byte(int64_t token) {
    @autoreleasepool {
        TGMobileBle *s=lookup(token);if(!s)return -2;
        int64_t status=tg_ble_status(token);
        if(s->cursor<[s->bytes length])return ((const uint8_t *)[s->bytes bytes])[s->cursor++];
        [s->bytes setLength:0];s->cursor=0;
        return status==0?-2:-1;
    }
}
API void tg_ble_close(int64_t token) {
    @autoreleasepool {
        if(!lookup(token))return;
        for(int i=0;i<16;i++)if(tokens[i]==token && sessions[i]) { [sessions[i] close];[sessions[i] release];sessions[i]=nil;tokens[i]=0;return; }
    }
}

API const char *tg_ble_drain_event(int64_t token) {
    @autoreleasepool { TGMobileBle *s=lookup(token);return s?[s drainEvent]:NULL; }
}
API int64_t tg_ble_internal_events_dropped(int64_t token) {
    @autoreleasepool { TGMobileBle *s=lookup(token);return s?(int64_t)MIN(s->droppedEvents,(uint64_t)INT64_MAX):0; }
}
