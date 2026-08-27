#import <Foundation/Foundation.h>

@interface WiFiScanner : NSObject
+ (void)scanAvailableNetworksWithCompletion:(void(^)(NSArray<NSDictionary *> *networks, NSString *debugLog))completion;
@end
