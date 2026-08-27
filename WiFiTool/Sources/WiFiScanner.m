#import "WiFiScanner.h"
#import <CoreLocation/CoreLocation.h>
#import <dlfcn.h>

// ========================================================================
// WiFiScanner.m - iOS 17 XPC + 网卡绑定 + debugLog 版本
// 修复：wifid XPC 静默拒绝 + CWFInterface 需显式扫描参数
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

+ (void)scanAvailableNetworksWithCompletion:(void(^)(NSArray<NSDictionary *> *networks, NSString *debugLog))completion {
    [WiFiScanner shared];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableArray *networks = [NSMutableArray array];
        NSMutableString *debug = [NSMutableString string];

        // 方案 1: CoreWiFi.framework CWFInterface (iOS 17 带扫描参数)
        void *handle = dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_LAZY);
        if (!handle) {
            [debug appendString:@"[CoreWiFi] 无法加载动态库\n"];
        } else {
            Class CWFInterfaceClass = NSClassFromString(@"CWFInterface");
            if (!CWFInterfaceClass) {
                [debug appendString:@"[CoreWiFi] CWFInterface 类未找到\n"];
            } else {
                id interface = [[CWFInterfaceClass alloc] init];
                if (![interface respondsToSelector:NSSelectorFromString(@"activate")]) {
                    [debug appendString:@"[CoreWiFi] activate 方法不可用\n"];
                } else {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [interface performSelector:NSSelectorFromString(@"activate")];
                    [debug appendString:@"[CoreWiFi] 接口已激活\n"];

                    // 构建 iOS 17 标准扫描参数
                    Class CWFScanParamsClass = NSClassFromString(@"CWFScanParameters");
                    id params = nil;
                    if (CWFScanParamsClass) {
                        params = [[CWFScanParamsClass alloc] init];
                        [params setValue:@(0) forKey:@"scanType"];
                        [debug appendString:@"[CoreWiFi] 扫描参数已构建 (scanType=0)\n"];
                    } else {
                        [debug appendString:@"[CoreWiFi] CWFScanParameters 类未找到\n"];
                    }

                    NSSet *scanResults = nil;

                    // 优先尝试 performScanWithParameters:error:
                    SEL scanWithParams = NSSelectorFromString(@"performScanWithParameters:error:");
                    if ([interface respondsToSelector:scanWithParams]) {
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[CWFInterfaceClass instanceMethodSignatureForSelector:scanWithParams]];
                        [inv setTarget:interface];
                        [inv setSelector:scanWithParams];
                        [inv setArgument:&params atIndex:2];
                        NSError *scanError = nil;
                        [inv setArgument:&scanError atIndex:3];
                        [inv invoke];

                        CFTypeRef retVal = NULL;
                        [inv getReturnValue:&retVal];
                        scanResults = (__bridge_transfer NSSet *)retVal;

                        if (scanError) {
                            [debug appendFormat:@"[CoreWiFi] 扫描失败: %@\n", scanError.localizedDescription];
                        }
                        [debug appendString:@"[CoreWiFi] 已调用 performScanWithParameters:error:\n"];
                    } else {
                        // 降级: performScanWithType:error:
                        SEL scanWithType = NSSelectorFromString(@"performScanWithType:error:");
                        if ([interface respondsToSelector:scanWithType]) {
                            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[CWFInterfaceClass instanceMethodSignatureForSelector:scanWithType]];
                            [inv setTarget:interface];
                            [inv setSelector:scanWithType];
                            NSInteger type = 0;
                            [inv setArgument:&type atIndex:2];
                            NSError *scanError = nil;
                            [inv setArgument:&scanError atIndex:3];
                            [inv invoke];

                            CFTypeRef retVal = NULL;
                            [inv getReturnValue:&retVal];
                            scanResults = (__bridge_transfer NSSet *)retVal;

                            if (scanError) {
                                [debug appendFormat:@"[CoreWiFi] 扫描失败: %@\n", scanError.localizedDescription];
                            }
                            [debug appendString:@"[CoreWiFi] 已调用 performScanWithType:error:\n"];
                        } else {
                            [debug appendString:@"[CoreWiFi] 扫描方法均不可用\n"];
                        }
                    }

                    if (scanResults && scanResults.count > 0) {
                        for (id network in scanResults) {
                            NSString *ssid = [network valueForKey:@"networkName"] ?: @"(隐藏网络)";
                            NSString *bssid = [network valueForKey:@"BSSID"] ?: @"";
                            NSNumber *rssi = [network valueForKey:@"RSSI"] ?: @(0);

                            if (bssid.length > 0) {
                                [networks addObject:@{@"ssid": ssid, @"bssid": bssid, @"rssi": rssi}];
                            }
                        }
                        [debug appendFormat:@"[CoreWiFi] 扫描成功，捕获到 %lu 个网络\n", (unsigned long)networks.count];
                    } else {
                        [debug appendString:@"[CoreWiFi] 扫描返回结果为空 (0 APs)\n"];
                    }
                    #pragma clang diagnostic pop
                }
            }
            dlclose(handle);
        }

        // 方案 2: MobileWiFi 降级
        if (networks.count == 0) {
            [debug appendString:@"[MobileWiFi] 尝试降级方案...\n"];
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
                                [debug appendFormat:@"[MobileWiFi] 降级方案捕获 %lu 个网络\n", (unsigned long)networks.count];
                            } else {
                                [debug appendString:@"[MobileWiFi] copyNetworks 返回空\n"];
                            }
                        } else {
                            [debug appendString:@"[MobileWiFi] 未找到 WiFi 设备\n"];
                        }
                        if (devs) CFRelease(devs);
                        CFRelease(mgr);
                    } else {
                        [debug appendString:@"[MobileWiFi] WiFiManagerClientCreate 失败\n"];
                    }
                } else {
                    [debug appendString:@"[MobileWiFi] 符号解析失败\n"];
                }
                dlclose(mwHandle);
            } else {
                [debug appendString:@"[MobileWiFi] 无法加载动态库\n"];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion([networks copy], [debug copy]);
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
