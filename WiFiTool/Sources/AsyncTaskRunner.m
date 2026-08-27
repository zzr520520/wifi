#import "AsyncTaskRunner.h"
#include <spawn.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>

extern char **environ;

@interface AsyncTaskRunner ()
@property (nonatomic, assign) pid_t childPid;
@property (nonatomic, assign) int pipeFd[2];
@property (nonatomic, strong) NSThread *readThread;
@property (nonatomic, strong) NSThread *waitThread;
@property (nonatomic, assign) BOOL running;
@end

@implementation AsyncTaskRunner

- (instancetype)init {
    self = [super init];
    if (self) {
        _childPid = -1;
        _pipeFd[0] = -1;
        _pipeFd[1] = -1;
        _running = NO;
    }
    return self;
}

- (void)launchWithPath:(NSString *)execPath arguments:(NSArray<NSString *> *)arguments {
    if (self.running) return;

    if (pipe(self.pipeFd) != 0) {
        if (self.onOutput) self.onOutput(@"错误：无法创建管道\n");
        return;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, self.pipeFd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, self.pipeFd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, self.pipeFd[0]);
    posix_spawn_file_actions_addclose(&actions, self.pipeFd[1]);

    NSMutableArray *argv = [NSMutableArray arrayWithObject:execPath];
    [argv addObjectsFromArray:arguments];

    const char **cArgv = malloc(sizeof(char *) * (argv.count + 1));
    for (NSUInteger i = 0; i < argv.count; i++) {
        cArgv[i] = [argv[i] UTF8String];
    }
    cArgv[argv.count] = NULL;

    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, [execPath UTF8String], &actions, NULL, (char *const *)cArgv, environ);

    posix_spawn_file_actions_destroy(&actions);
    close(self.pipeFd[1]);
    self.pipeFd[1] = -1;
    free(cArgv);

    if (spawnResult != 0) {
        close(self.pipeFd[0]);
        self.pipeFd[0] = -1;
        if (self.onOutput) {
            self.onOutput([NSString stringWithFormat:@"posix_spawn 失败 (错误码: %d)\n", spawnResult]);
        }
        if (self.onCompletion) self.onCompletion(spawnResult);
        return;
    }

    self.childPid = pid;
    self.running = YES;

    // 读取线程
    self.readThread = [[NSThread alloc] initWithTarget:self selector:@selector(readPipe) object:nil];
    [self.readThread start];

    // 等待线程
    self.waitThread = [[NSThread alloc] initWithTarget:self selector:@selector(waitForExit) object:nil];
    [self.waitThread start];
}

- (void)readPipe {
    @autoreleasepool {
        char buffer[8192];
        ssize_t bytesRead;
        while (self.running && (bytesRead = read(self.pipeFd[0], buffer, sizeof(buffer))) > 0) {
            NSData *data = [NSData dataWithBytes:buffer length:bytesRead];
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (str && self.onOutput) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.onOutput(str);
                });
            }
        }
        if (self.pipeFd[0] >= 0) {
            close(self.pipeFd[0]);
            self.pipeFd[0] = -1;
        }
    }
}

- (void)waitForExit {
    @autoreleasepool {
        int status = 0;
        waitpid(self.childPid, &status, 0);
        self.running = NO;

        // 等待读线程完成
        [NSThread sleepForTimeInterval:0.1];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.onCompletion) {
                self.onCompletion(WIFEXITED(status) ? WEXITSTATUS(status) : -1);
            }
        });
    }
}

- (void)terminate {
    if (self.childPid > 0 && self.running) {
        kill(self.childPid, SIGTERM);
        self.running = NO;
    }
}

- (void)dealloc {
    [self terminate];
    if (self.pipeFd[0] >= 0) close(self.pipeFd[0]);
    if (self.pipeFd[1] >= 0) close(self.pipeFd[1]);
}

@end
