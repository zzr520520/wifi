#import <Foundation/Foundation.h>

@interface ProcessRunner : NSObject
+ (NSString *)runCommand:(NSString *)executablePath arguments:(NSArray<NSString *> *)arguments;
@end
