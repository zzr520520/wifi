#import "WiFiAutoEngine.h"
#import <NetworkExtension/NetworkExtension.h>
#import <dlfcn.h>
#import <objc/message.h>

@implementation WiFiAutoEngine

// 检查当前设备实际连接的 SSID 是否为目标 SSID
+ (NSString *)currentAssociatedSSID {
    void *cwHandle = dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_NOW);
    if (!cwHandle) return nil;

    Class CWFInterfaceClass = NSClassFromString(@"CWFInterface");
    if (!CWFInterfaceClass) return nil;

    id interface = [[CWFInterfaceClass alloc] init];
    if ([interface respondsToSelector:@selector(activate)]) {
        ((void (*)(id, SEL))objc_msgSend)(interface, @selector(activate));
    }

    NSString *currentSSID = nil;
    if ([interface respondsToSelector:NSSelectorFromString(@"networkName")]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        currentSSID = [interface performSelector:NSSelectorFromString(@"networkName")];
        #pragma clang diagnostic pop
    }

    if ([interface respondsToSelector:@selector(invalidate)]) {
        ((void (*)(id, SEL))objc_msgSend)(interface, @selector(invalidate));
    }
    return currentSSID;
}

+ (NSString *)calculateDefaultKeyWithSSID:(NSString *)ssid bssid:(NSString *)bssid {
    if (!ssid || ssid.length == 0) return nil;
    NSString *cleanBSSID = [[bssid stringByReplacingOccurrencesOfString:@":" withString:@""] uppercaseString];

    // 移动特定光猫
    if ([ssid hasPrefix:@"CMCC-"] || [ssid hasPrefix:@"and-baby"]) {
        if (cleanBSSID.length >= 8) {
            return [cleanBSSID substringFromIndex:cleanBSSID.length - 8].lowercaseString;
        }
    }
    // 电信光猫
    if ([ssid hasPrefix:@"ChinaNet-"] || [ssid hasPrefix:@"Mifi-"]) {
        if (cleanBSSID.length >= 6) {
            return [NSString stringWithFormat:@"cn%@", [cleanBSSID substringFromIndex:cleanBSSID.length - 6].lowercaseString];
        }
    }
    return nil;
}

// 真实连接校验：下发配置后，轮询 6 秒确认是否真正连上
+ (void)tryConnectSSID:(NSString *)ssid password:(NSString *)password completion:(void(^)(BOOL success, NSError *error))completion {
    if (@available(iOS 11.0, *)) {
        NEHotspotConfiguration *config = [[NEHotspotConfiguration alloc] initWithSSID:ssid passphrase:password isWEP:NO];
        config.joinOnce = YES;

        [[NEHotspotConfigurationManager sharedManager] applyConfiguration:config completionHandler:^(NSError * _Nullable error) {
            if (error) {
                if (completion) completion(NO, error);
                return;
            }

            // 下发配置成功后，启动多轮检测，确认网卡是否真正连通
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                BOOL reallyConnected = NO;
                for (int i = 0; i < 6; i++) {
                    [NSThread sleepForTimeInterval:1.0];
                    NSString *connectedNow = [self currentAssociatedSSID];
                    if ([connectedNow isEqualToString:ssid]) {
                        reallyConnected = YES;
                        break;
                    }
                }

                // 清理临时测试配置，避免弹窗常驻
                [[NEHotspotConfigurationManager sharedManager] removeConfigurationForSSID:ssid];

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (reallyConnected) {
                        if (completion) completion(YES, nil);
                    } else {
                        NSError *failErr = [NSError errorWithDomain:@"WiFiTool" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"密码错误，握手失败"}];
                        if (completion) completion(NO, failErr);
                    }
                });
            });
        }];
    } else {
        if (completion) completion(NO, nil);
    }
}

@end
