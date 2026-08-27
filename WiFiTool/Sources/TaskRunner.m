#import "TaskRunner.h"

@implementation TaskRunner

- (void)launchWithPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    self.task = [[NSTask alloc] init];
    self.task.launchPath = path;
    self.task.arguments = arguments;

    NSPipe *pipe = [NSPipe pipe];
    self.task.standardOutput = pipe;
    self.task.standardError = pipe;

    NSMutableData *buffer = [NSMutableData data];

    __weak typeof(self) weakSelf = self;
    [pipe.fileHandleForReading readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = [handle availableData];
        if (data.length > 0) {
            [buffer appendData:data];
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (str && weakSelf.onOutput) {
                weakSelf.onOutput(str);
            }
        }
    }];

    self.task.terminationHandler = ^(NSTask *task) {
        if (weakSelf.onCompletion) {
            weakSelf.onCompletion(task.terminationStatus);
        }
    };

    [self.task launch];
}

- (void)terminate {
    if (self.task && self.task.isRunning) {
        [self.task terminate];
    }
}

@end
