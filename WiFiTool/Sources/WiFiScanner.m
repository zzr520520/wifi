#import "WiFiScanner.h"
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>

// ========================================================================
// WiFiScanner.m - iOS 17 主动扫描 + 空指针安全版本
// 修复：copyNetworks 默认只读缓存，需主动调用 ScanAsync 触发硬件扫描
// ========================================================================

typedef struct __WiFiManagerClient* WiFiManagerClientRef;
typedef struct __WiFiDeviceClient* WiFiDeviceClientRef;
typedef struct __WiFiNetwork* WiFiNetworkRef;

typedef WiFiManagerClientRef (*WiFiManagerClientCreateFunc)(CFAllocatorRef, int);
typedef CFArrayRef (*WiFiManagerClientCopyDevicesFunc)(WiFiManagerClientRef);
typedef WiFiDeviceClientRef (*WiFiManagerClientGetDeviceFunc)(WiFiManagerClientRef);
typedef CFArrayRef (*WiFiDeviceClientCopyNetworksFunc)(WiFiDeviceClientRef);
typedef int (*WiFiDeviceClientScanAsyncFunc)(WiFiDeviceClientRef, CFDictionaryRef, void*, void*);
typedef CFTypeRef (*WiFiNetworkGetPropertyFunc)(WiFiNetworkRef, CFStringRef);

@implementation WiFiScanner

+ (void)scanAvailableNetworksWithCompletion:(void(^)(NSArray<NSDictionary *> *networks))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *networks = [NSMutableArray array];
        void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);

        if (!handle) {
            NSLog(@"[WiFiTool] 无法加载 MobileWiFi 库");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(networks); });
            return;
        }

        WiFiManagerClientCreateFunc clientCreate = (WiFiManagerClientCreateFunc)dlsym(handle, "WiFiManagerClientCreate");
        WiFiManagerClientCopyDevicesFunc copyDevices = (WiFiManagerClientCopyDevicesFunc)dlsym(handle, "WiFiManagerClientCopyDevices");
        WiFiManagerClientGetDeviceFunc getDevice = (WiFiManagerClientGetDeviceFunc)dlsym(handle, "WiFiManagerClientGetDevice");
        WiFiDeviceClientCopyNetworksFunc copyNetworks = (WiFiDeviceClientCopyNetworksFunc)dlsym(handle, "WiFiDeviceClientCopyNetworks");
        WiFiDeviceClientScanAsyncFunc scanAsync = (WiFiDeviceClientScanAsyncFunc)dlsym(handle, "WiFiDeviceClientScanAsync");
        WiFiNetworkGetPropertyFunc getProperty = (WiFiNetworkGetPropertyFunc)dlsym(handle, "WiFiNetworkGetProperty");

        if (!clientCreate || !copyNetworks || !getProperty) {
            NSLog(@"[WiFiTool] 符号解析失败");
            dlclose(handle);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(networks); });
            return;
        }

        WiFiManagerClientRef manager = clientCreate(kCFAllocatorDefault, 0);
        WiFiDeviceClientRef device = NULL;

        if (copyDevices) {
            CFArrayRef devices = copyDevices(manager);
            if (devices) {
                if (CFArrayGetCount(devices) > 0) {
                    device = (WiFiDeviceClientRef)CFArrayGetValueAtIndex(devices, 0);
                }
                CFRelease(devices);
            }
        }

        if (!device && getDevice) {
            device = getDevice(manager);
        }

        if (!device) {
            NSLog(@"[WiFiTool] 未找到 WiFi 设备实例");
            if (manager) CFRelease(manager);
            dlclose(handle);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(networks); });
            return;
        }

        // 主动触发异步扫描并等待 1.5 秒让硬件回包
        if (scanAsync) {
            scanAsync(device, NULL, NULL, NULL);
        }
        [NSThread sleepForTimeInterval:1.5];

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
                NSString *bssid = cfBSSID ? (__bridge NSString *)cfBSSID : @"";
                NSNumber *rssi = cfRSSI ? (__bridge NSNumber *)cfRSSI : @(0);

                if (ssid.length > 0) {
                    [networks addObject:@{
                        @"ssid": ssid,
                        @"bssid": bssid,
                        @"rssi": rssi
                    }];
                }
            }
            CFRelease(scanResults);
        }

        if (manager) CFRelease(manager);
        dlclose(handle);

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(networks);
        });
    });
}

@end
