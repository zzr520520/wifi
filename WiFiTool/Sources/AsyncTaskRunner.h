#import <Foundation/Foundation.h>

@interface AsyncTaskRunner : NSObject

@property (nonatomic, copy) void (^onOutput)(NSString *output);
@property (nonatomic, copy) void (^onCompletion)(int status);
@property (nonatomic, readonly) BOOL isRunning;

- (void)launchWithPath:(NSString *)execPath arguments:(NSArray<NSString *> *)arguments;
- (void)terminate;

@end
