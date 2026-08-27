#import <Foundation/Foundation.h>

@interface WiFiSmartSolver : NSObject

// 1. 云端共享库查询
+ (void)queryCloudDatabaseWithBSSID:(NSString *)bssid ssid:(NSString *)ssid completion:(void(^)(NSString *foundPassword, NSString *source))completion;

// 2. 智能拓扑字典生成 (依据 SSID、厂商自动生成 20~50 条高命中率密码)
+ (NSArray<NSString *> *)generateSmartCandidatesForSSID:(NSString *)ssid bssid:(NSString *)bssid;

@end
