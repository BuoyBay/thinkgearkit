/* Read-only paired MindWave inventory. Never scans, pairs, or opens devices.
 * ABI JSON text is thread-local and valid until the next call on that thread. */
#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#include <string.h>
#define TG_DISCOVERY_API __attribute__((visibility("default")))
#define TG_DISCOVERY_LIMIT (256 * 1024)
static _Thread_local char tgMacDiscoveryJSON[TG_DISCOVERY_LIMIT + 1];

static BOOL tgDiscoveryString(id text) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    if ([text length] > 4096) return NO;
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    return utf8 && utf8.length <= 4096 && [text rangeOfString:@"\0"].location == NSNotFound;
}
/* Fixture boundary: snapshots of paired objects, not synthetic live devices. */
static const char *tgDiscoveryRender(NSArray *records, BOOL complete, NSString *error) {
    NSMutableArray *devices = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSUInteger inspected = 0;
    for (id record in records) {
        if (inspected++ >= 4096) { complete = NO; error = @"Paired-device inventory exceeded inspection limit"; break; }
        if (![record isKindOfClass:[NSDictionary class]]) { complete = NO; error = @"Invalid paired-device record"; continue; }
        id name = record[@"name"], address = record[@"id"];
        if (![name isKindOfClass:[NSString class]]) continue;
        if ([name length] > 4096) {
            complete = NO; error = @"Paired device name exceeds metadata inspection limit"; continue;
        }
        if ([[name lowercaseString] rangeOfString:@"mindwave"].location == NSNotFound) continue;
        if (!tgDiscoveryString(name) || !tgDiscoveryString(address) || ![address length]) {
            complete = NO; error = @"Paired MindWave has invalid or oversized name/address"; continue;
        }
        NSString *key = [address lowercaseString];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        NSString *endpoint = [@"bluetooth:" stringByAppendingString:address];
        [devices addObject:@{@"id": endpoint, @"name": name, @"endpoint": endpoint,
                             @"transport": @"rfcomm", @"pairing_known": @YES, @"paired": @YES}];
    }
    [devices sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"id"] compare:b[@"id"] options:NSCaseInsensitiveSearch];
        if (order == NSOrderedSame) order = [a[@"id"] compare:b[@"id"]];
        return order;
    }];
    if (devices.count > 64) {
        [devices removeObjectsInRange:NSMakeRange(64, devices.count - 64)];
        complete = NO; error = @"Paired MindWave inventory exceeded 64-device limit";
    }
    NSData *json = nil;
    for (;;) {
        NSDictionary *result = @{@"supported": @YES, @"complete": @(complete),
                                  @"devices": devices, @"error": error ?: @""};
        json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
        if (json && json.length <= TG_DISCOVERY_LIMIT) break;
        if (!devices.count) {
            const char *fallback = "{\"supported\":true,\"complete\":false,\"devices\":[],\"error\":\"Cannot encode paired-device inventory\"}";
            memcpy(tgMacDiscoveryJSON, fallback, strlen(fallback) + 1);
            return tgMacDiscoveryJSON;
        }
        [devices removeLastObject]; complete = NO;
        error = @"Paired MindWave inventory exceeded JSON byte limit";
    }
    memcpy(tgMacDiscoveryJSON, json.bytes, json.length);
    tgMacDiscoveryJSON[json.length] = 0;
    return tgMacDiscoveryJSON;
}
TG_DISCOVERY_API const char *tg_macos_discover_headsets(void) {
    @autoreleasepool {
        if (![NSThread isMainThread]) return tgDiscoveryRender(@[], NO, @"Paired MindWave discovery must run on the macOS main thread");
        @try {
            NSArray *paired = [IOBluetoothDevice pairedDevices];
            /* nil cannot distinguish denied/unavailable enumeration from no devices. */
            if (!paired) return tgDiscoveryRender(@[], NO, @"macOS paired-device inventory is unavailable");
            NSMutableArray *records = [NSMutableArray array];
            BOOL complete = YES;
            for (IOBluetoothDevice *device in paired) {
                if (records.count >= 4096) { complete = NO; break; }
                [records addObject:@{@"id": device.addressString ?: [NSNull null],
                                     @"name": device.name ?: [NSNull null]}];
            }
            return tgDiscoveryRender(records, complete, complete ? @"" : @"Paired-device inventory exceeded inspection limit");
        } @catch (NSException *exception) {
            (void)exception;
            return tgDiscoveryRender(@[], NO, @"macOS paired-device enumeration raised an exception");
        }
    }
}
