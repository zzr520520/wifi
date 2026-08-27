#import <Foundation/Foundation.h>

@interface TaskRunner : NSObject
@property (nonatomic, copy) void (^onOutput)(NSString *line);
@property (nonatomic, copy) void (^onCompletion)(int terminationStatus);
@property (nonatomic, strong) NSTask *task;

- (void)launchWithPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments;
- (void)terminate;
@end
