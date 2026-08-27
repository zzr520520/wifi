#import <Foundation/Foundation.h>

@interface WiFiScanner : NSObject
+ (void)scanAvailableNetworksWithCompletion:(void(^)(NSArray<NSDictionary<NSString *, id> *> *networks, NSString *debugLog))completion;
@end
