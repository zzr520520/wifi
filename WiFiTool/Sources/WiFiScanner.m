#import "WiFiScanner.h"
#import <dlfcn.h>
#import <objc/message.h>

// ========================================================================
// WiFiScanner.m - iOS 17 CWFInterface + objc_msgSend 版本
// 彻底摒弃 dlsym 旧符号 (iOS17 已移除 MobileWiFi C 函数)
// ========================================================================

@implementation WiFiScanner

+ (void)scanAvailableNetworksWithCompletion:(void(^)(NSArray<NSDictionary<NSString *, id> *> *networks, NSString *debugLog))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableArray<NSDictionary<NSString *, id> *> *resultList = [NSMutableArray array];
        NSMutableString *debug = [NSMutableString string];

        // 1. 加载 iOS 17 的 CoreWiFi 私有框架
        void *cwHandle = dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_NOW);
        if (!cwHandle) {
            [debug appendString:@"[Error] 无法加载 CoreWiFi.framework\n"];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(@[], [debug copy]);
            });
            return;
        }

        // 2. 获取 CWFInterface 核心通信类
        Class CWFInterfaceClass = NSClassFromString(@"CWFInterface");
        if (!CWFInterfaceClass) {
            [debug appendString:@"[Error] 未找到 CWFInterface 类定义\n"];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(@[], [debug copy]);
            });
            return;
        }

        @try {
            // 3. 实例化并激活接口
            id interface = [[CWFInterfaceClass alloc] init];
            if ([interface respondsToSelector:@selector(activate)]) {
                ((void (*)(id, SEL))objc_msgSend)(interface, @selector(activate));
                [debug appendString:@"[CoreWiFi] 接口已激活\n"];
            }

            // 4. 发起主动扫描 (performScanWithType:error:)
            // ScanType 0: 主动全频段扫描 (Active Scan)
            SEL scanSel = NSSelectorFromString(@"performScanWithType:error:");
            if ([interface respondsToSelector:scanSel]) {
                NSError *error = nil;
                typedef NSSet* (*ScanFunc)(id, SEL, NSInteger, NSError**);
                ScanFunc scanMethod = (ScanFunc)[interface methodForSelector:scanSel];

                NSSet *rawNetworks = scanMethod(interface, scanSel, 0, &error);

                if (error) {
                    [debug appendFormat:@"[CoreWiFi] 扫描报错: %@\n", error.localizedDescription];
                } else if (rawNetworks && rawNetworks.count > 0) {
                    for (id netObj in rawNetworks) {
                        NSString *ssid = [netObj valueForKey:@"networkName"] ?: @"(隐藏网络)";
                        NSString *bssid = [netObj valueForKey:@"BSSID"] ?: @"";
                        NSNumber *rssi = [netObj valueForKey:@"RSSI"] ?: @(0);

                        if (bssid.length > 0 || ssid.length > 0) {
                            [resultList addObject:@{
                                @"ssid": ssid,
                                @"bssid": bssid,
                                @"rssi": rssi
                            }];
                        }
                    }
                    [debug appendFormat:@"扫描成功，共获取到 %lu 个热点\n", (unsigned long)resultList.count];
                } else {
                    [debug appendString:@"[CoreWiFi] 扫描完成，但未发现周边热点（0 结果）\n"];
                }
            } else {
                [debug appendString:@"[Error] 当前系统接口不支持 performScanWithType\n"];
            }

            // 关闭接口连接
            if ([interface respondsToSelector:@selector(invalidate)]) {
                ((void (*)(id, SEL))objc_msgSend)(interface, @selector(invalidate));
            }
        } @catch (NSException *e) {
            [debug appendFormat:@"[Crash Prevent] 执行异常: %@\n", e.reason];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion([resultList copy], [debug copy]);
            }
        });
    });
}

@end
