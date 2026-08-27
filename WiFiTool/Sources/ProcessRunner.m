#import "ProcessRunner.h"
#include <spawn.h>
#include <unistd.h>
#include <sys/wait.h>

extern char **environ;

@implementation ProcessRunner

+ (NSString *)runCommand:(NSString *)executablePath arguments:(NSArray<NSString *> *)arguments {
    int pipefd[2];
    if (pipe(pipefd) != 0) return @"错误：无法创建管道";

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    NSMutableArray *argv = [NSMutableArray array];
    [argv addObject:executablePath];
    for (NSString *arg in arguments) {
        [argv addObject:arg];
    }

    const char **cArgv = malloc(sizeof(char *) * (argv.count + 1));
    for (NSUInteger i = 0; i < argv.count; i++) {
        cArgv[i] = [argv[i] UTF8String];
    }
    cArgv[argv.count] = NULL;

    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, [executablePath UTF8String], &actions, NULL, (char *const *)cArgv, environ);

    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);
    free(cArgv);

    if (spawnResult != 0) {
        close(pipefd[0]);
        return [NSString stringWithFormat:@"posix_spawn 失败 (错误码: %d)", spawnResult];
    }

    NSMutableData *outputData = [NSMutableData data];
    char buffer[4096];
    ssize_t bytesRead;

    while ((bytesRead = read(pipefd[0], buffer, sizeof(buffer))) > 0) {
        [outputData appendBytes:buffer length:bytesRead];
    }
    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    return output ?: @"";
}

@end
