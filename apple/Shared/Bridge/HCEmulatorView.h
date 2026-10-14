/*
 * Halcyon - the view the emulator renders into.
 *
 * iOS: a UIView backed by a CAEAGLLayer (OpenGL ES 3).
 * macOS: an NSView the core attaches an NSOpenGLContext to.
 *
 * Touches (or mouse clicks) become Symbian pointer events and hardware keys
 * become Symbian scancodes. There is one surface per process; the shell moves it
 * between screens rather than creating new ones.
 *
 * Licensed under the GNU General Public License v3 or later.
 * Touch-slot logic adapted from the EKA2L1 iOS port's EmulatorView.
 */
#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#define HCPlatformView UIView
#else
#import <AppKit/AppKit.h>
#define HCPlatformView NSView
#endif

NS_ASSUME_NONNULL_BEGIN

@interface HCEmulatorView : HCPlatformView

/// The pointer handed to the core: the CAEAGLLayer on iOS, the view itself on macOS.
@property (nonatomic, readonly) void *renderSurface;
@property (nonatomic, readonly) int drawableWidth;
@property (nonatomic, readonly) int drawableHeight;

/// Called once the view has a window and a non-zero size, i.e. when the core can boot.
@property (nonatomic, copy, nullable) void (^readyHandler)(HCEmulatorView *view);

@end

NS_ASSUME_NONNULL_END
