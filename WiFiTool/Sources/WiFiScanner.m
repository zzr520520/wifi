#import "WiFiScanner.h"
#import <CoreLocation/CoreLocation.h>
#import <dlfcn.h>

// ========================================================================
// WiFiScanner.m - RootHide/越狱环境兼容版
// 方案1: CoreWiFi.framework CWFInterface (iOS 15-17 最稳私有库)
// 方案2: MobileWiFi.framework 降级回退
// + CLLocationManager 请求定位授权 (iOS 17 硬性要求)
// ========================================================================

@interface WiFiScanner () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locManager;
@end

@implementation WiFiScanner

static WiFiScanner *sharedInstance = nil;

+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[WiFiScanner alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.locManager = [[CLLocationManager alloc] init];
            self.locManager.delegate = self;
            [self.locManager requestWhenInUseAuthorization];
        });
    }
    return self;
}

+ (void)scanAvailableNetworksWithCompletion:(void(^)(NSArray<NSDictionary *> *networks))completion {
    // 确保初始化并请求定位
    [WiFiScanner shared];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableArray *networks = [NSMutableArray array];

        // 方案 1: 优先尝试 CoreWiFi (iOS 15-17 最稳私有库)
        void *cwHandle = dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_LAZY);
        if (cwHandle) {
            Class CWFInterfaceClass = NSClassFromString(@"CWFInterface");
            if (CWFInterfaceClass) {
                id interface = [[CWFInterfaceClass alloc] init];
                if ([interface respondsToSelector:NSSelectorFromString(@"activate")]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [interface performSelector:NSSelectorFromString(@"activate")];

                    if ([interface respondsToSelector:NSSelectorFromString(@"performScanWithType:error:")]) {
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[CWFInterfaceClass instanceMethodSignatureForSelector:NSSelectorFromString(@"performScanWithType:error:")]];
                        [inv setTarget:interface];
                        [inv setSelector:NSSelectorFromString(@"performScanWithType:error:")];
                        NSInteger type = 0; // 全频段扫描
                        void *nilErr = nil;
                        [inv setArgument:&type atIndex:2];
                        [inv setArgument:&nilErr atIndex:3];
                        [inv invoke];

                        CFTypeRef scanResultsRaw = NULL;
                        [inv getReturnValue:&scanResultsRaw];
                        NSSet *scanResults = (__bridge_transfer NSSet *)scanResultsRaw;

                        for (id scanObj in scanResults) {
                            NSString *ssid = [scanObj valueForKey:@"networkName"] ?: @"(隐藏网络)";
                            NSString *bssid = [scanObj valueForKey:@"BSSID"] ?: @"";
                            NSNumber *rssi = [scanObj valueForKey:@"RSSI"] ?: @(0);

                            if (ssid.length > 0) {
                                [networks addObject:@{@"ssid": ssid, @"bssid": bssid, @"rssi": rssi}];
                            }
                        }
                    }
                    #pragma clang diagnostic pop
                }
            }
            dlclose(cwHandle);
        }

        // 方案 2: 若 CoreWiFi 未取到，回落到系统 wifid 接口
        if (networks.count == 0) {
            void *mwHandle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
            if (mwHandle) {
                typedef void* (*WiFiManagerClientCreateFunc)(CFAllocatorRef, int);
                typedef CFArrayRef (*WiFiManagerClientCopyDevicesFunc)(void*);
                typedef CFArrayRef (*WiFiDeviceClientCopyNetworksFunc)(void*);
                typedef CFTypeRef (*WiFiNetworkGetPropertyFunc)(void*, CFStringRef);

                WiFiManagerClientCreateFunc createClient = (WiFiManagerClientCreateFunc)dlsym(mwHandle, "WiFiManagerClientCreate");
                WiFiManagerClientCopyDevicesFunc copyDevs = (WiFiManagerClientCopyDevicesFunc)dlsym(mwHandle, "WiFiManagerClientCopyDevices");
                WiFiDeviceClientCopyNetworksFunc copyNets = (WiFiDeviceClientCopyNetworksFunc)dlsym(mwHandle, "WiFiDeviceClientCopyNetworks");
                WiFiNetworkGetPropertyFunc getProp = (WiFiNetworkGetPropertyFunc)dlsym(mwHandle, "WiFiNetworkGetProperty");

                if (createClient && copyDevs && copyNets && getProp) {
                    void *mgr = createClient(kCFAllocatorDefault, 0);
                    if (mgr) {
                        CFArrayRef devs = copyDevs(mgr);
                        if (devs && CFArrayGetCount(devs) > 0) {
                            void *dev = (void *)CFArrayGetValueAtIndex(devs, 0);
                            CFArrayRef list = copyNets(dev);
                            if (list) {
                                for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
                                    void *net = (void *)CFArrayGetValueAtIndex(list, i);
                                    NSString *ssid = (__bridge_transfer NSString *)getProp(net, CFSTR("SSID_STR"));
                                    NSString *bssid = (__bridge_transfer NSString *)getProp(net, CFSTR("BSSID"));
                                    NSNumber *rssi = (__bridge_transfer NSNumber *)getProp(net, CFSTR("RSSI"));
                                    if (ssid) {
                                        [networks addObject:@{@"ssid": ssid, @"bssid": bssid ?: @"", @"rssi": rssi ?: @0}];
                                    }
                                }
                                CFRelease(list);
                            }
                        }
                        if (devs) CFRelease(devs);
                        CFRelease(mgr);
                    }
                }
                dlclose(mwHandle);
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion([networks copy]);
        });
    });
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        [manager requestWhenInUseAuthorization];
    }
}

@end
