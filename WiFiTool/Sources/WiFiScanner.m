#import "WiFiScanner.h"
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>

// ========================================================================
// WiFiScanner.m - 纯 C 风格静态符号安全封装
// 移除 NSInvocation/ARC桥接强转，杜绝 objc_release 野指针崩溃
// ========================================================================

@implementation WiFiScanner

+ (void)scanAvailableNetworksWithCompletion:(void(^)(NSArray<NSDictionary<NSString *, id> *> *networks, NSString *debugLog))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSMutableArray<NSDictionary<NSString *, id> *> *networks = [NSMutableArray array];
            NSMutableString *debug = [NSMutableString string];

            void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_NOW);
            if (!handle) {
                [debug appendString:@"[Error] 无法加载 MobileWiFi\n"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(@[], [debug copy]);
                });
                return;
            }

            typedef void* (*WiFiManagerClientCreateFunc)(CFAllocatorRef, int);
            typedef CFArrayRef (*WiFiManagerClientCopyDevicesFunc)(void*);
            typedef CFArrayRef (*WiFiDeviceClientCopyNetworksFunc)(void*);
            typedef CFTypeRef (*WiFiNetworkGetPropertyFunc)(void*, CFStringRef);

            WiFiManagerClientCreateFunc clientCreate = (WiFiManagerClientCreateFunc)dlsym(handle, "WiFiManagerClientCreate");
            WiFiManagerClientCopyDevicesFunc copyDevices = (WiFiManagerClientCopyDevicesFunc)dlsym(handle, "WiFiManagerClientCopyDevices");
            WiFiDeviceClientCopyNetworksFunc copyNetworks = (WiFiDeviceClientCopyNetworksFunc)dlsym(handle, "WiFiDeviceClientCopyNetworks");
            WiFiNetworkGetPropertyFunc getProperty = (WiFiNetworkGetPropertyFunc)dlsym(handle, "WiFiNetworkGetProperty");

            if (!clientCreate || !copyDevices || !copyNetworks || !getProperty) {
                [debug appendString:@"[Error] dlsym 解析私有符号失败\n"];
                dlclose(handle);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(@[], [debug copy]);
                });
                return;
            }

            void *manager = clientCreate(kCFAllocatorDefault, 0);
            if (!manager) {
                [debug appendString:@"[Error] WiFiManagerClientCreate 失败，缺少 entitlements\n"];
                dlclose(handle);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(@[], [debug copy]);
                });
                return;
            }

            CFArrayRef devices = copyDevices(manager);
            if (devices) {
                CFIndex devCount = CFArrayGetCount(devices);
                for (CFIndex d = 0; d < devCount; d++) {
                    void *device = (void *)CFArrayGetValueAtIndex(devices, d);
                    if (!device) continue;

                    CFArrayRef rawNetworks = copyNetworks(device);
                    if (rawNetworks) {
                        CFIndex netCount = CFArrayGetCount(rawNetworks);
                        for (CFIndex i = 0; i < netCount; i++) {
                            void *net = (void *)CFArrayGetValueAtIndex(rawNetworks, i);
                            if (!net) continue;

                            CFTypeRef cfSSID = getProperty(net, CFSTR("SSID_STR"));
                            CFTypeRef cfBSSID = getProperty(net, CFSTR("BSSID"));
                            CFTypeRef cfRSSI = getProperty(net, CFSTR("RSSI"));

                            NSString *ssid = cfSSID ? [NSString stringWithString:(__bridge NSString *)cfSSID] : @"(隐藏网络)";
                            NSString *bssid = cfBSSID ? [NSString stringWithString:(__bridge NSString *)cfBSSID] : @"";
                            NSNumber *rssi = cfRSSI ? [NSNumber numberWithInt:[(__bridge NSNumber *)cfRSSI intValue]] : @(0);

                            if (bssid.length > 0 || ssid.length > 0) {
                                [networks addObject:@{
                                    @"ssid": ssid,
                                    @"bssid": bssid,
                                    @"rssi": rssi
                                }];
                            }
                        }
                        CFRelease(rawNetworks);
                    }
                }
                CFRelease(devices);
            } else {
                [debug appendString:@"[Warning] 无法获取网络设备列表 (Devices is NULL)\n"];
            }

            CFRelease(manager);
            dlclose(handle);

            [debug appendFormat:@"扫描完成，共找到 %lu 个网络\n", (unsigned long)networks.count];

            NSArray *finalList = [networks copy];
            NSString *finalDebug = [debug copy];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(finalList, finalDebug);
                }
            });
        }
    });
}

@end
