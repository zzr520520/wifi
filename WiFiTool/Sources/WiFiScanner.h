#import <Foundation/Foundation.h>

@interface WiFiScanner : NSObject
+ (NSArray<NSDictionary *> *)scanAvailableNetworks;
@end
