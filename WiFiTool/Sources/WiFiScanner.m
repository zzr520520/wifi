#import "WiFiScanner.h"
#import <dlfcn.h>
#import <objc/message.h>

@implementation WiFiScanner

+ (void)scanAvailableNetworksWithCompletion:(void(^)(NSArray<NSDictionary<NSString *, id> *> *networks, NSString *debugLog))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableArray<NSDictionary<NSString *, id> *> *resultList = [NSMutableArray array];
        NSMutableString *debug = [NSMutableString string];

        void *cwHandle = dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_NOW);
        if (!cwHandle) {
            [debug appendString:@"[Error] 无法加载 CoreWiFi.framework\n"];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], debug); });
            return;
        }

        Class CWFInterfaceClass = NSClassFromString(@"CWFInterface");
        Class CWFScanParamsClass = NSClassFromString(@"CWFScanParameters");

        if (!CWFInterfaceClass) {
            [debug appendString:@"[Error] 未找到 CWFInterface\n"];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(@[], debug); });
            return;
        }

        @try {
            id interface = [[CWFInterfaceClass alloc] init];

            // 激活接口
            if ([interface respondsToSelector:@selector(activate)]) {
                ((void (*)(id, SEL))objc_msgSend)(interface, @selector(activate));
                [debug appendString:@"[CoreWiFi] 接口已激活\n"];
            }

            NSSet *rawNetworks = nil;
            NSError *error = nil;

            // 1. 优先调用 iOS 17 标准方法 performScanWithParameters:error:
            SEL scanWithParamsSel = NSSelectorFromString(@"performScanWithParameters:error:");
            if ([interface respondsToSelector:scanWithParamsSel]) {
                id params = nil;
                if (CWFScanParamsClass) {
                    params = [[CWFScanParamsClass alloc] init];
                    // scanType: 0 (全部信道全扫描)
                    [params setValue:@(0) forKey:@"scanType"];
                }

                typedef NSSet* (*ScanWithParamsFunc)(id, SEL, id, NSError**);
                ScanWithParamsFunc scanMethod = (ScanWithParamsFunc)[interface methodForSelector:scanWithParamsSel];
                rawNetworks = scanMethod(interface, scanWithParamsSel, params, &error);
            }
            // 2. 兼容旧接口
            else if ([interface respondsToSelector:NSSelectorFromString(@"performScanWithType:error:")]) {
                SEL scanWithTypeSel = NSSelectorFromString(@"performScanWithType:error:");
                typedef NSSet* (*ScanWithTypeFunc)(id, SEL, NSInteger, NSError**);
                ScanWithTypeFunc scanMethod = (ScanWithTypeFunc)[interface methodForSelector:scanWithTypeSel];
                rawNetworks = scanMethod(interface, scanWithTypeSel, 0, &error);
            }

            // 处理扫描结果
            if (error) {
                [debug appendFormat:@"[CoreWiFi] 扫描返回错误: %@\n", error.localizedDescription];
            } else if (rawNetworks && rawNetworks.count > 0) {
                for (id netObj in rawNetworks) {
                    // 读取 SSID、BSSID、RSSI
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
                [debug appendFormat:@"扫描成功，共发现 %lu 个周边 WiFi！\n", (unsigned long)resultList.count];
            } else {
                [debug appendString:@"[CoreWiFi] 扫描成功，但未返回热点数据（请确认系统 Wi-Fi 已开启）\n"];
            }

            // 关闭接口
            if ([interface respondsToSelector:@selector(invalidate)]) {
                ((void (*)(id, SEL))objc_msgSend)(interface, @selector(invalidate));
            }
        } @catch (NSException *e) {
            [debug appendFormat:@"[Exception] 执行异常: %@\n", e.reason];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion([resultList copy], [debug copy]);
        });
    });
}

@end
