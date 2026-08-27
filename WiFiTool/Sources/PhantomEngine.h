#import <Foundation/Foundation.h>

@interface PhantomEngine : NSObject
+ (void)silentTryConnectBSSID:(NSString *)bssid password:(NSString *)password completion:(void(^)(BOOL success))completion;
+ (NSInteger)getLastTriedIndexForBSSID:(NSString *)bssid;
+ (void)saveProgressIndex:(NSInteger)index forBSSID:(NSString *)bssid;
@end
