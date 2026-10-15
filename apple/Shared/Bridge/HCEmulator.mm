/*
 * SymbOS - Objective-C++ wrapper around the EKA2L1 core.
 * Licensed under the GNU General Public License v3 or later.
 */
#import "HCEmulator.h"

#if HALCYON_REAL_CORE
#include <ios/emu_bridge.h>
#include <halcyon_host.h>
namespace emu = eka2l1::ios::bridge;
#endif

#include <string>
#include <vector>

static std::string HCStd(NSString *s) {
    return s ? std::string(s.UTF8String) : std::string();
}

static NSString *HCNS(const std::string &s) {
    return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}

/// Returns a +1 image (the caller releases it, or hands it to Swift as a "copy" result).
static CGImageRef HCCreateImageRGBA(const uint8_t *rgba, int width, int height) {
    if (!rgba || width <= 0 || height <= 0) {
        return NULL;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CFDataRef data = CFDataCreate(NULL, rgba, (CFIndex)width * height * 4);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGImageRef image = CGImageCreate(width, height, 8, 32, (size_t)width * 4, space,
        kCGBitmapByteOrderDefault | kCGImageAlphaLast, provider, NULL, true, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CFRelease(data);
    CGColorSpaceRelease(space);
    return image;
}

#pragma mark - Value types

@implementation HCAppInfo
- (instancetype)initWithUID:(uint32_t)uid name:(NSString *)name {
    if ((self = [super init])) {
        _uid = uid;
        _name = [name copy];
    }
    return self;
}
@end

@implementation HCPackageInfo
- (instancetype)initWithUID:(uint32_t)uid index:(int32_t)index name:(NSString *)name {
    if ((self = [super init])) {
        _uid = uid;
        _index = index;
        _name = [name copy];
    }
    return self;
}
@end

@implementation HCDeviceInfo
- (instancetype)initWithName:(NSString *)name firmware:(NSString *)firmware {
    if ((self = [super init])) {
        _name = [name copy];
        _firmware = [firmware copy];
    }
    return self;
}
@end

#pragma mark - Emulator

@implementation HCEmulator {
#if !HALCYON_REAL_CORE
    NSMutableArray<HCAppInfo *> *_mockApps;
    BOOL _mockRunning;
    BOOL _mockJIT;
#endif
}

+ (HCEmulator *)shared {
    static HCEmulator *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[HCEmulator alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
#if HALCYON_REAL_CORE
        __weak HCEmulator *weakSelf = self;
        emu::set_app_exit_callback([weakSelf]() {
            dispatch_async(dispatch_get_main_queue(), ^{
                HCEmulator *strongSelf = weakSelf;
                if (strongSelf.appExitHandler) {
                    strongSelf.appExitHandler();
                }
            });
        });
        eka2l1::ios::host::on_text_input_request = [weakSelf](const std::string &initial, int maxLen) {
            NSString *text = HCNS(initial);
            dispatch_async(dispatch_get_main_queue(), ^{
                HCEmulator *strongSelf = weakSelf;
                if (strongSelf.textInputHandler) {
                    strongSelf.textInputHandler(text, maxLen);
                } else {
                    eka2l1::ios::host::finish_text_input(HCStd(text));
                }
            });
        };
        eka2l1::ios::host::on_question_request = [weakSelf](const std::string &message, const std::string &first,
                                                            const std::string &second) {
            NSString *m = HCNS(message), *a = HCNS(first), *b = HCNS(second);
            dispatch_async(dispatch_get_main_queue(), ^{
                HCEmulator *strongSelf = weakSelf;
                if (strongSelf.questionHandler) {
                    strongSelf.questionHandler(m, a, b);
                } else {
                    eka2l1::ios::host::finish_question(1);
                }
            });
        };
#else
        _mockApps = [NSMutableArray array];
        NSArray *names = @[ @"Sample Clock", @"Sample Notes", @"Sample Game", @"Sample Music" ];
        uint32_t uid = 0xE0000001;
        for (NSString *name in names) {
            [_mockApps addObject:[[HCAppInfo alloc] initWithUID:uid++ name:name]];
        }
#endif
    }
    return self;
}

#if HALCYON_REAL_CORE

- (BOOL)isMock { return NO; }
- (BOOL)isRunning { return emu::is_running(); }
- (BOOL)hasDevice { return emu::has_device(); }
- (BOOL)jitEnabled { return emu::get_jit_enabled(); }
- (void)setJitEnabled:(BOOL)enabled { emu::set_jit_enabled(enabled); }

- (void)prepareDataDirectory:(NSString *)dataDirectory bundleResources:(NSString *)bundleResources {
    emu::set_data_directory(HCStd(dataDirectory), HCStd(bundleResources));
}

- (BOOL)startWithSurface:(void *)surface width:(int)width height:(int)height {
    return emu::start(surface, width, height);
}

- (void)surfaceChanged:(void *)surface width:(int)width height:(int)height {
    emu::surface_changed(surface, width, height);
}

- (void)pause { emu::pause(); }
- (void)resume { emu::resume(); }
- (void)shutdown { emu::shutdown(); }

- (int)installDeviceROM:(NSString *)romPath rpkg:(NSString *)rpkgPath progress:(void (^)(int))progress {
    std::function<void(int)> cb = nullptr;
    if (progress) {
        void (^block)(int) = [progress copy];
        cb = [block](int percent) {
            dispatch_async(dispatch_get_main_queue(), ^{ block(percent); });
        };
    }
    // A dump with an RPKG installs as a device dump; a lone .vpl is VPL firmware.
    const bool isVPL = [romPath.pathExtension.lowercaseString isEqualToString:@"vpl"];
    return emu::install_device(HCStd(rpkgPath), HCStd(romPath), !isVPL, cb);
}

- (int)installPackageAtPath:(NSString *)path {
    return emu::install_app(HCStd(path));
}

- (NSArray<HCAppInfo *> *)apps {
    NSMutableArray *result = [NSMutableArray array];
    for (const auto &entry : emu::get_apps()) {
        [result addObject:[[HCAppInfo alloc] initWithUID:entry.uid name:HCNS(entry.name)]];
    }
    return result;
}

- (CGImageRef)copyIconForUID:(uint32_t)uid {
    emu::icon_image icon = emu::get_app_icon(uid);
    return HCCreateImageRGBA(icon.rgba.data(), icon.width, icon.height);
}

- (void)launchAppWithUID:(uint32_t)uid { emu::launch_app(uid); }
- (void)exitApp { emu::exit_game(); }

- (NSArray<HCPackageInfo *> *)packages {
    NSMutableArray *result = [NSMutableArray array];
    for (const auto &entry : emu::get_packages()) {
        [result addObject:[[HCPackageInfo alloc] initWithUID:entry.uid index:entry.index name:HCNS(entry.name)]];
    }
    return result;
}

- (void)uninstallPackageUID:(uint32_t)uid index:(int32_t)index {
    emu::uninstall_package(uid, index);
}

- (NSArray<HCDeviceInfo *> *)devices {
    NSMutableArray *result = [NSMutableArray array];
    for (const auto &entry : emu::get_devices()) {
        [result addObject:[[HCDeviceInfo alloc] initWithName:HCNS(entry.name) firmware:HCNS(entry.firmware)]];
    }
    return result;
}

- (NSInteger)currentDeviceIndex { return emu::get_current_device(); }
- (void)selectDeviceAtIndex:(NSInteger)index { emu::set_current_device((int)index); }

- (void)touchAtX:(int)x y:(int)y action:(HCTouchAction)action pointer:(int)pointer {
    emu::touch(x, y, static_cast<emu::touch_action>(action), pointer);
}

- (void)key:(HCKey)key down:(BOOL)down { emu::key((int)key, down); }

- (void)setGyroPassthrough:(BOOL)enabled { emu::set_gyro_passthrough(enabled); }
- (void)setHapticPassthrough:(BOOL)enabled { emu::set_haptic_passthrough(enabled); }

- (BOOL)sampleFPS:(float *)fps { return emu::get_status(fps); }

- (void)finishTextInput:(NSString *)text { eka2l1::ios::host::finish_text_input(HCStd(text)); }
- (void)finishQuestion:(BOOL)firstButton { eka2l1::ios::host::finish_question(firstButton ? 1 : 0); }

#else // ---- Mock core: sample data so the shell can be developed without the emulator.

- (BOOL)isMock { return YES; }
- (BOOL)isRunning { return _mockRunning; }
- (BOOL)hasDevice { return YES; }
- (BOOL)jitEnabled { return _mockJIT; }
- (void)setJitEnabled:(BOOL)enabled { _mockJIT = enabled; }
- (void)prepareDataDirectory:(NSString *)dataDirectory bundleResources:(NSString *)bundleResources {}
- (BOOL)startWithSurface:(void *)surface width:(int)width height:(int)height {
    _mockRunning = YES;
    return YES;
}
- (void)surfaceChanged:(void *)surface width:(int)width height:(int)height {}
- (void)pause {}
- (void)resume {}
- (void)shutdown { _mockRunning = NO; }

- (int)installDeviceROM:(NSString *)romPath rpkg:(NSString *)rpkgPath progress:(void (^)(int))progress {
    if (progress) {
        dispatch_async(dispatch_get_main_queue(), ^{ progress(100); });
    }
    return 0;
}

- (int)installPackageAtPath:(NSString *)path {
    NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
    uint32_t uid = 0xE0000100 + (uint32_t)_mockApps.count;
    [_mockApps addObject:[[HCAppInfo alloc] initWithUID:uid name:name.length ? name : @"Installed app"]];
    return 0;
}

- (NSArray<HCAppInfo *> *)apps { return [_mockApps copy]; }

- (CGImageRef)copyIconForUID:(uint32_t)uid {
    const int size = 88;
    std::vector<uint8_t> rgba((size_t)size * size * 4, 0);
    const uint8_t hue = (uint8_t)((uid * 47u) % 255u);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            const float dx = x - size / 2.0f, dy = y - size / 2.0f;
            if (dx * dx + dy * dy > (size / 2.2f) * (size / 2.2f)) {
                continue;
            }
            uint8_t *p = &rgba[((size_t)y * size + x) * 4];
            p[0] = hue;
            p[1] = (uint8_t)(120 + y);
            p[2] = (uint8_t)(255 - hue);
            p[3] = 255;
        }
    }
    return HCCreateImageRGBA(rgba.data(), size, size);
}

- (void)launchAppWithUID:(uint32_t)uid {}
- (void)exitApp {}
- (NSArray<HCPackageInfo *> *)packages { return @[]; }
- (void)uninstallPackageUID:(uint32_t)uid index:(int32_t)index {
    [_mockApps filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id app, NSDictionary *bindings) {
        return ((HCAppInfo *)app).uid != uid;
    }]];
}
- (NSArray<HCDeviceInfo *> *)devices {
    return @[ [[HCDeviceInfo alloc] initWithName:@"Demo device" firmware:@"DEMO"] ];
}
- (NSInteger)currentDeviceIndex { return 0; }
- (void)selectDeviceAtIndex:(NSInteger)index {}
- (void)touchAtX:(int)x y:(int)y action:(HCTouchAction)action pointer:(int)pointer {}
- (void)key:(HCKey)key down:(BOOL)down {}
- (void)setGyroPassthrough:(BOOL)enabled {}
- (void)setHapticPassthrough:(BOOL)enabled {}
- (BOOL)sampleFPS:(float *)fps { return NO; }
- (void)finishTextInput:(NSString *)text {}
- (void)finishQuestion:(BOOL)firstButton {}

#endif

- (void)tapKey:(HCKey)key {
    [self key:key down:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(80 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self key:key down:NO];
    });
}

@end
