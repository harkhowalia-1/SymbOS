/*
 * Halcyon - Objective-C face of the EKA2L1 core, used from Swift.
 *
 * Wraps eka2l1::ios::bridge (external/eka2l1/src/emu/ios/include/ios/emu_bridge.h).
 * When the app is built without the core (no core/out/<platform>), a mock
 * implementation with sample apps is compiled instead so the UI can be developed.
 *
 * Threading: methods marked "heavy" reboot or parse the guest and must be called
 * off the main thread. Everything else is safe on the main thread.
 *
 * Licensed under the GNU General Public License v3 or later.
 */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HCTouchAction) {
    HCTouchActionDown = 0,
    HCTouchActionMove = 1,
    HCTouchActionUp = 2
};

/// Symbian standard scancodes (e32keys.h) for the keys the shell exposes.
typedef NS_ENUM(NSInteger, HCKey) {
    HCKeyBackspace = 0x01,
    HCKeyLeft = 0x0E,
    HCKeyRight = 0x0F,
    HCKeyUp = 0x10,
    HCKeyDown = 0x11,
    HCKeyLeftSoftkey = 0xA4,   // "Options"
    HCKeyRightSoftkey = 0xA5,  // "Back" / "Exit"
    HCKeySelect = 0xA7,        // centre of the navigation key
    HCKeyMenu = 0xB4           // the N8's Menu key (EStdKeyApplication0)
};

@interface HCAppInfo : NSObject
@property (nonatomic, readonly) uint32_t uid;
@property (nonatomic, readonly, copy) NSString *name;
- (instancetype)initWithUID:(uint32_t)uid name:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface HCPackageInfo : NSObject
@property (nonatomic, readonly) uint32_t uid;
@property (nonatomic, readonly) int32_t index;
@property (nonatomic, readonly, copy) NSString *name;
- (instancetype)initWithUID:(uint32_t)uid index:(int32_t)index name:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface HCDeviceInfo : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *firmware;
- (instancetype)initWithName:(NSString *)name firmware:(NSString *)firmware NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface HCEmulator : NSObject

@property (class, nonatomic, readonly) HCEmulator *shared;

/// YES when built without the real core (sample data, nothing is emulated).
@property (nonatomic, readonly) BOOL isMock;
@property (nonatomic, readonly) BOOL isRunning;
/// YES when a firmware (device) is installed and the guest booted.
@property (nonatomic, readonly) BOOL hasDevice;

/// Persisted CPU backend preference. NO = dyncom interpreter, YES = Dynarmic JIT.
/// Setting it reboots the guest (heavy).
@property (nonatomic) BOOL jitEnabled;

/// Copy shaders, compat data and patch DLLs from `bundleResources`/assets into
/// `dataDirectory` (first launch only) and make it the emulator's storage root.
- (void)prepareDataDirectory:(NSString *)dataDirectory bundleResources:(NSString *)bundleResources;

/// Boot the guest into `surface` (CAEAGLLayer on iOS, NSView on macOS). Heavy.
/// Returns YES if a device is installed and booted.
- (BOOL)startWithSurface:(void *)surface width:(int)width height:(int)height;
- (void)surfaceChanged:(void *)surface width:(int)width height:(int)height;
- (void)pause;
- (void)resume;
- (void)shutdown;

/// Install a firmware dump (ROM + optional RPKG). Returns 0 on success. Heavy.
- (int)installDeviceROM:(NSString *)romPath
                   rpkg:(nullable NSString *)rpkgPath
               progress:(nullable void (^)(int percent))progress;
/// Install a .sis/.sisx package. 0 = success, 1 = aborted, 2 = invalid. Heavy.
- (int)installPackageAtPath:(NSString *)path;

- (NSArray<HCAppInfo *> *)apps;
/// The app's icon as decoded from the firmware / package (RGBA). May be NULL.
- (nullable CGImageRef)copyIconForUID:(uint32_t)uid CF_RETURNS_RETAINED;
- (void)launchAppWithUID:(uint32_t)uid;
/// Close the running app and return the guest to its booted state. Heavy.
- (void)exitApp;

- (NSArray<HCPackageInfo *> *)packages;
/// Remove a package and reboot the guest. Heavy.
- (void)uninstallPackageUID:(uint32_t)uid index:(int32_t)index;

- (NSArray<HCDeviceInfo *> *)devices;
- (NSInteger)currentDeviceIndex;
/// Switch firmware and reboot. Heavy.
- (void)selectDeviceAtIndex:(NSInteger)index;

/// Surface pixel coordinates.
- (void)touchAtX:(int)x y:(int)y action:(HCTouchAction)action pointer:(int)pointer;
- (void)key:(HCKey)key down:(BOOL)down;
- (void)tapKey:(HCKey)key;

- (void)setGyroPassthrough:(BOOL)enabled;
- (void)setHapticPassthrough:(BOOL)enabled;

/// Rolling frames per second. NO until two samples exist.
- (BOOL)sampleFPS:(float *)fps;

// ---- Callbacks (always delivered on the main queue) -------------------------
@property (nonatomic, copy, nullable) void (^appExitHandler)(void);
/// A Symbian app opened a text-entry dialog. Reply with -finishTextInput:.
@property (nonatomic, copy, nullable) void (^textInputHandler)(NSString *initialText, NSInteger maxLength);
/// A Symbian app asked a yes/no question. Reply with -finishQuestion:.
@property (nonatomic, copy, nullable) void (^questionHandler)(NSString *message, NSString *firstButton, NSString *secondButton);

- (void)finishTextInput:(NSString *)text;
/// YES = first button.
- (void)finishQuestion:(BOOL)firstButton;

@end

NS_ASSUME_NONNULL_END
