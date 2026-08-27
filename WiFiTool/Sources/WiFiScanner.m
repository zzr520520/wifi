#import <Foundation/Foundation.h>
#import <dlfcn.h>

// ========================================================================
// WiFiScanner.m - 方案A：MobileWiFi 私有 API 扫描桥接
// 在 TrollStore 赋予 Root/私有权限后，调用 MobileWiFi.framework
// 读取周边 AP 的 SSID、BSSID、RSSI，并在本地/云端规则库匹配弱口令
// ========================================================================

typedef struct __WiFiManagerClient* WiFiManagerClientRef;
typedef struct __WiFiDeviceClient* WiFiDeviceClientRef;
typedef struct __WiFiNetwork* WiFiNetworkRef;

WiFiManagerClientRef (*WiFiManagerClientCreate)(CFAllocatorRef, int);
CFArrayRef (*WiFiManagerClientCopyDevices)(WiFiManagerClientRef);
CFArrayRef (*WiFiDeviceClientCopyNetworks)(WiFiDeviceClientRef);
CFStringRef (*WiFiNetworkGetProperty)(WiFiNetworkRef, CFStringRef);

@interface WiFiScanner : NSObject
+ (NSArray<NSDictionary *> *)scanAvailableNetworks;
@end

@implementation WiFiScanner

+ (NSArray<NSDictionary *> *)scanAvailableNetworks {
    NSMutableArray *networks = [NSMutableArray array];
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
    if (!handle) return networks;

    WiFiManagerClientCreate = dlsym(handle, "WiFiManagerClientCreate");
    WiFiManagerClientCopyDevices = dlsym(handle, "WiFiManagerClientCopyDevices");
    WiFiDeviceClientCopyNetworks = dlsym(handle, "WiFiDeviceClientCopyNetworks");
    WiFiNetworkGetProperty = dlsym(handle, "WiFiNetworkGetProperty");

    WiFiManagerClientRef manager = WiFiManagerClientCreate(kCFAllocatorDefault, 0);
    CFArrayRef devices = WiFiManagerClientCopyDevices(manager);
    if (devices && CFArrayGetCount(devices) > 0) {
        WiFiDeviceClientRef client = (WiFiDeviceClientRef)CFArrayGetValueAtIndex(devices, 0);
        CFArrayRef scanResults = WiFiDeviceClientCopyNetworks(client);
        
        if (scanResults) {
            CFIndex count = CFArrayGetCount(scanResults);
            for (CFIndex i = 0; i < count; i++) {
                WiFiNetworkRef net = (WiFiNetworkRef)CFArrayGetValueAtIndex(scanResults, i);
                NSString *ssid = (__bridge_transfer NSString *)WiFiNetworkGetProperty(net, CFSTR("SSID_STR"));
                NSString *bssid = (__bridge_transfer NSString *)WiFiNetworkGetProperty(net, CFSTR("BSSID"));
                NSNumber *rssi = (__bridge_transfer NSNumber *)WiFiNetworkGetProperty(net, CFSTR("RSSI"));
                
                if (ssid) {
                    [networks addObject:@{
                        @"ssid": ssid,
                        @"bssid": bssid ?: @"",
                        @"rssi": rssi ?: @(0)
                    }];
                }
            }
            CFRelease(scanResults);
        }
        CFRelease(devices);
    }
    dlclose(handle);
    return networks;
}

@end
