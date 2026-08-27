#import "WiFiSmartSolver.h"
#import <CommonCrypto/CommonDigest.h>

@implementation WiFiSmartSolver

+ (void)queryCloudDatabaseWithBSSID:(NSString *)bssid ssid:(NSString *)ssid completion:(void(^)(NSString *foundPassword, NSString *source))completion {
    if (!bssid || bssid.length == 0) {
        if (completion) completion(nil, nil);
        return;
    }

    NSString *cleanBSSID = [[bssid lowercaseString] stringByReplacingOccurrencesOfString:@":" withString:@""];

    // 构造请求：查询开源/共享热点云节点
    NSString *urlString = [NSString stringWithFormat:@"https://api.beijixing.site/wifi/query?bssid=%@&ssid=%@",
                           cleanBSSID,
                           [ssid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:4.0];
    [request setValue:@"Mozilla/5.0 WiFiTool/2.0" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json && [json[@"code"] intValue] == 0 && json[@"data"][@"password"]) {
                NSString *pwd = json[@"data"][@"password"];
                if (pwd.length >= 8) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(pwd, @"云端共享库");
                    });
                    return;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, nil);
        });
    }];
    [task resume];
}

+ (NSArray<NSString *> *)generateSmartCandidatesForSSID:(NSString *)ssid bssid:(NSString *)bssid {
    NSMutableOrderedSet<NSString *> *candidates = [NSMutableOrderedSet orderedSet];
    NSString *cleanBSSID = [[bssid uppercaseString] stringByReplacingOccurrencesOfString:@":" withString:@""];

    // 1. 硬件/MAC 衍生规则 (很多路由器默认密码是 MAC 后 8 位)
    if (cleanBSSID.length >= 8) {
        NSString *last8 = [cleanBSSID substringFromIndex:cleanBSSID.length - 8];
        [candidates addObject:last8.lowercaseString];
        [candidates addObject:last8.uppercaseString];
    }
    if (cleanBSSID.length >= 6) {
        NSString *last6 = [cleanBSSID substringFromIndex:cleanBSSID.length - 6];
        [candidates addObject:[NSString stringWithFormat:@"123456%@", last6.lowercaseString]];
        [candidates addObject:[NSString stringWithFormat:@"admin%@", last6.lowercaseString]];
    }

    // 2. SSID 名字变形规则
    if (ssid.length > 0) {
        // 去除特殊字符，提取纯英文或拼音
        NSString *cleanSSID = [[ssid componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];

        if (cleanSSID.length >= 4) {
            [candidates addObject:[NSString stringWithFormat:@"%@123", cleanSSID]];
            [candidates addObject:[NSString stringWithFormat:@"%@888", cleanSSID]];
            [candidates addObject:[NSString stringWithFormat:@"%@520", cleanSSID]];
            [candidates addObject:[NSString stringWithFormat:@"%@666", cleanSSID]];
            [candidates addObject:[NSString stringWithFormat:@"%@2024", cleanSSID]];
            [candidates addObject:[NSString stringWithFormat:@"%@2025", cleanSSID]];
            [candidates addObject:[NSString stringWithFormat:@"%@2026", cleanSSID]];
            [candidates addObject:[NSString stringWithFormat:@"1234%@", cleanSSID]];
        }

        // 针对 TP-LINK_XXXX 等带下划线路由器
        if ([ssid containsString:@"_"]) {
            NSArray *parts = [ssid componentsSeparatedByString:@"_"];
            if (parts.count > 1) {
                NSString *suffix = parts[1];
                [candidates addObject:[NSString stringWithFormat:@"%@%@", suffix, suffix]]; // 如 3F073F07
                [candidates addObject:[NSString stringWithFormat:@"1234%@", suffix]];
            }
        }
    }

    // 3. 全国通用 Top 20 极简弱口令
    NSArray *topList = @[
        @"12345678", @"88888888", @"123456789", @"11111111",
        @"00000000", @"1234567890", @"87654321", @"66666666",
        @"123123123", @"password", @"admin123", @"12344321",
        @"888888888", @"99999999", @"520520520", @"13800138000"
    ];
    [candidates addObjectsFromArray:topList];

    return [candidates array];
}

@end
