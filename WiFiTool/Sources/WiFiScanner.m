#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>

// ========================================================================
// WiFiScanner.m - iOS 17+ 空指针安全版本
// 修复 iOS 17.2.1 MobileWiFi.framework 私有 API 返回 NULL 导致的 EXC_BAD_ACCESS
// ========================================================================

typedef struct __WiFiManagerClient* WiFiManagerClientRef;
typedef struct __WiFiDeviceClient* WiFiDeviceClientRef;
typedef struct __WiFiNetwork* WiFiNetworkRef;

// 动态函数声明
typedef WiFiManagerClientRef (*WiFiManagerClientCreateFunc)(CFAllocatorRef, int);
typedef CFArrayRef (*WiFiManagerClientCopyDevicesFunc)(WiFiManagerClientRef);
typedef WiFiDeviceClientRef (*WiFiManagerClientGetDeviceFunc)(WiFiManagerClientRef);
typedef CFArrayRef (*WiFiDeviceClientCopyNetworksFunc)(WiFiDeviceClientRef);
typedef CFTypeRef (*WiFiNetworkGetPropertyFunc)(WiFiNetworkRef, CFStringRef);

@interface WiFiScanner : NSObject
+ (NSArray<NSDictionary *> *)scanAvailableNetworks;
@end

@implementation WiFiScanner

+ (NSArray<NSDictionary *> *)scanAvailableNetworks {
    NSMutableArray *networks = [NSMutableArray array];

    // 打开私有库
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
    if (!handle) {
        NSLog(@"[WiFiTool] 无法加载 MobileWiFi 动态库");
        return networks;
    }

    WiFiManagerClientCreateFunc clientCreate = (WiFiManagerClientCreateFunc)dlsym(handle, "WiFiManagerClientCreate");
    WiFiManagerClientCopyDevicesFunc copyDevices = (WiFiManagerClientCopyDevicesFunc)dlsym(handle, "WiFiManagerClientCopyDevices");
    WiFiManagerClientGetDeviceFunc getDevice = (WiFiManagerClientGetDeviceFunc)dlsym(handle, "WiFiManagerClientGetDevice");
    WiFiDeviceClientCopyNetworksFunc copyNetworks = (WiFiDeviceClientCopyNetworksFunc)dlsym(handle, "WiFiDeviceClientCopyNetworks");
    WiFiNetworkGetPropertyFunc getProperty = (WiFiNetworkGetPropertyFunc)dlsym(handle, "WiFiNetworkGetProperty");

    if (!clientCreate || !copyNetworks || !getProperty) {
        NSLog(@"[WiFiTool] 关键符号 dlsym 获取失败");
        dlclose(handle);
        return networks;
    }

    WiFiManagerClientRef manager = clientCreate(kCFAllocatorDefault, 0);
    if (!manager) {
        NSLog(@"[WiFiTool] WiFiManagerClientCreate 失败，可能缺少 entitlements");
        dlclose(handle);
        return networks;
    }

    WiFiDeviceClientRef device = NULL;

    // 优先尝试从设备数组取
    if (copyDevices) {
        CFArrayRef devices = copyDevices(manager);
        if (devices) {
            if (CFArrayGetCount(devices) > 0) {
                device = (WiFiDeviceClientRef)CFArrayGetValueAtIndex(devices, 0);
            }
            CFRelease(devices);
        }
    }

    // iOS 16/17 降级兼容方案
    if (!device && getDevice) {
        device = getDevice(manager);
    }

    if (!device) {
        NSLog(@"[WiFiTool] 未找到可用的 WiFiDeviceClient 实例");
        CFRelease(manager);
        dlclose(handle);
        return networks;
    }

    CFArrayRef scanResults = copyNetworks(device);
    if (scanResults) {
        CFIndex count = CFArrayGetCount(scanResults);
        for (CFIndex i = 0; i < count; i++) {
            WiFiNetworkRef net = (WiFiNetworkRef)CFArrayGetValueAtIndex(scanResults, i);
            if (!net) continue;

            CFStringRef cfSSID = (CFStringRef)getProperty(net, CFSTR("SSID_STR"));
            CFStringRef cfBSSID = (CFStringRef)getProperty(net, CFSTR("BSSID"));
            CFNumberRef cfRSSI = (CFNumberRef)getProperty(net, CFSTR("RSSI"));

            NSString *ssid = cfSSID ? (__bridge NSString *)cfSSID : @"(隐藏网络)";
            NSString *bssid = cfBSSID ? (__bridge NSString *)cfBSSID : @"00:00:00:00:00:00";
            NSNumber *rssi = cfRSSI ? (__bridge NSNumber *)cfRSSI : @(0);

            [networks addObject:@{
                @"ssid": ssid,
                @"bssid": bssid,
                @"rssi": rssi
            }];
        }
        CFRelease(scanResults);
    }

    CFRelease(manager);
    dlclose(handle);
    return [networks copy];
}

@end
