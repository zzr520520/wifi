#import <Foundation/Foundation.h>

@interface WiFiAutoEngine : NSObject
+ (NSString *)calculateDefaultKeyWithSSID:(NSString *)ssid bssid:(NSString *)bssid;
+ (void)tryConnectSSID:(NSString *)ssid password:(NSString *)password completion:(void(^)(BOOL success, NSError *error))completion;
@end
