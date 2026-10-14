/*
 * Halcyon - emulator surface view. See HCEmulatorView.h.
 * Licensed under the GNU General Public License v3 or later.
 */
#import "HCEmulatorView.h"
#import "HCEmulator.h"

/// Symbian standard scancode for a typed character, or -1.
/// Letters and digits use their upper-case ASCII value, as in e32keys.h.
static int HCScancodeForCharacter(unichar c) {
    if (c >= 'a' && c <= 'z') return c - 'a' + 'A';
    if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return c;
    switch (c) {
        case ' ': return 0x05;           // EStdKeySpace
        case '\r': case '\n': return 0x03; // EStdKeyEnter
        case '\t': return 0x02;          // EStdKeyTab
        case '*': return '*';
        case '#': return 0x7F;           // EStdKeyHash
        default: return -1;
    }
}

#if TARGET_OS_IOS
#import <QuartzCore/CAEAGLLayer.h>

@implementation HCEmulatorView {
    int _lastWidth;
    int _lastHeight;
    BOOL _announcedReady;
    NSMapTable<UITouch *, NSNumber *> *_touchSlots;
}

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        const CGFloat scale = UIScreen.mainScreen.scale;
        self.contentScaleFactor = scale;
        self.multipleTouchEnabled = YES;
        self.opaque = YES;
        self.backgroundColor = UIColor.blackColor;

        // Configure the layer on the main thread before the GL thread binds to it.
        CAEAGLLayer *layer = (CAEAGLLayer *)self.layer;
        layer.opaque = YES;
        layer.contentsScale = scale;
        layer.drawableProperties = @{
            kEAGLDrawablePropertyRetainedBacking : @NO,
            kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8
        };
        _touchSlots = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}

- (void *)renderSurface { return (__bridge void *)self.layer; }
- (int)drawableWidth { return (int)(self.bounds.size.width * self.contentScaleFactor); }
- (int)drawableHeight { return (int)(self.bounds.size.height * self.contentScaleFactor); }

- (BOOL)canBecomeFirstResponder { return YES; }

- (void)layoutSubviews {
    [super layoutSubviews];
    const int w = self.drawableWidth, h = self.drawableHeight;
    if (w <= 0 || h <= 0) {
        return;
    }
    if (!_announcedReady && self.window) {
        _announcedReady = YES;
        _lastWidth = w;
        _lastHeight = h;
        if (self.readyHandler) {
            self.readyHandler(self);
        }
        return;
    }
    if (w != _lastWidth || h != _lastHeight) {
        _lastWidth = w;
        _lastHeight = h;
        if (HCEmulator.shared.isRunning) {
            [HCEmulator.shared surfaceChanged:self.renderSurface width:w height:h];
        }
    }
}

// Guests reject pointer numbers above what a window enabled, so the first finger is
// always 0 and later fingers take the lowest free slot.
- (int)slotForTouch:(UITouch *)touch {
    NSNumber *existing = [_touchSlots objectForKey:touch];
    if (existing) return existing.intValue;
    NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
    for (UITouch *t in _touchSlots) {
        [used addIndex:[[_touchSlots objectForKey:t] unsignedIntegerValue]];
    }
    int slot = 0;
    while ([used containsIndex:(NSUInteger)slot]) slot++;
    [_touchSlots setObject:@(slot) forKey:touch];
    return slot;
}

- (void)send:(NSSet<UITouch *> *)touches action:(HCTouchAction)action {
    const CGFloat scale = self.contentScaleFactor;
    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        [HCEmulator.shared touchAtX:(int)(p.x * scale) y:(int)(p.y * scale) action:action pointer:[self slotForTouch:touch]];
        if (action == HCTouchActionUp) {
            [_touchSlots removeObjectForKey:touch];
        }
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self send:touches action:HCTouchActionDown]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self send:touches action:HCTouchActionMove]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self send:touches action:HCTouchActionUp]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self send:touches action:HCTouchActionUp]; }

// ---- Hardware keyboard (iPad Magic Keyboard, Bluetooth keyboards) ----------

- (int)scancodeForPress:(UIPress *)press {
    UIKey *key = press.key;
    if (!key) return -1;
    switch (key.keyCode) {
        case UIKeyboardHIDUsageKeyboardUpArrow: return HCKeyUp;
        case UIKeyboardHIDUsageKeyboardDownArrow: return HCKeyDown;
        case UIKeyboardHIDUsageKeyboardLeftArrow: return HCKeyLeft;
        case UIKeyboardHIDUsageKeyboardRightArrow: return HCKeyRight;
        case UIKeyboardHIDUsageKeyboardDeleteOrBackspace: return HCKeyBackspace;
        case UIKeyboardHIDUsageKeyboardEscape: return HCKeyRightSoftkey;
        case UIKeyboardHIDUsageKeyboardF1: return HCKeyLeftSoftkey;
        case UIKeyboardHIDUsageKeyboardF2: return HCKeyRightSoftkey;
        case UIKeyboardHIDUsageKeyboardF3: return HCKeyMenu;
        default: break;
    }
    NSString *chars = key.charactersIgnoringModifiers;
    return chars.length == 1 ? HCScancodeForCharacter([chars characterAtIndex:0]) : -1;
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses) {
        int code = [self scancodeForPress:press];
        if (code >= 0) {
            [HCEmulator.shared key:(HCKey)code down:YES];
            handled = YES;
        }
    }
    if (!handled) [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    for (UIPress *press in presses) {
        int code = [self scancodeForPress:press];
        if (code >= 0) {
            [HCEmulator.shared key:(HCKey)code down:NO];
            handled = YES;
        }
    }
    if (!handled) [super pressesEnded:presses withEvent:event];
}

@end

#else // ---- macOS --------------------------------------------------------------

@implementation HCEmulatorView {
    int _lastWidth;
    int _lastHeight;
    BOOL _announcedReady;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsBestResolutionOpenGLSurface = YES;
    }
    return self;
}

- (void *)renderSurface { return (__bridge void *)self; }
- (CGFloat)backingScale { return self.window ? self.window.backingScaleFactor : 2.0; }
- (int)drawableWidth { return (int)(self.bounds.size.width * self.backingScale); }
- (int)drawableHeight { return (int)(self.bounds.size.height * self.backingScale); }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque { return YES; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self checkSize];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self checkSize];
}

- (void)checkSize {
    const int w = self.drawableWidth, h = self.drawableHeight;
    if (!self.window || w <= 0 || h <= 0) {
        return;
    }
    if (!_announcedReady) {
        _announcedReady = YES;
        _lastWidth = w;
        _lastHeight = h;
        // Let the window finish its first layout before the core attaches a GL context.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.readyHandler) self.readyHandler(self);
        });
        return;
    }
    if (w != _lastWidth || h != _lastHeight) {
        _lastWidth = w;
        _lastHeight = h;
        if (HCEmulator.shared.isRunning) {
            [HCEmulator.shared surfaceChanged:self.renderSurface width:w height:h];
        }
    }
}

- (void)sendMouse:(NSEvent *)event action:(HCTouchAction)action {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    const CGFloat scale = self.backingScale;
    // NSView's origin is bottom-left; the guest expects top-left.
    const int x = (int)(p.x * scale);
    const int y = (int)((self.bounds.size.height - p.y) * scale);
    [HCEmulator.shared touchAtX:x y:y action:action pointer:0];
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    [self sendMouse:event action:HCTouchActionDown];
}
- (void)mouseDragged:(NSEvent *)event { [self sendMouse:event action:HCTouchActionMove]; }
- (void)mouseUp:(NSEvent *)event { [self sendMouse:event action:HCTouchActionUp]; }
- (void)rightMouseDown:(NSEvent *)event { [HCEmulator.shared key:HCKeyLeftSoftkey down:YES]; }
- (void)rightMouseUp:(NSEvent *)event { [HCEmulator.shared key:HCKeyLeftSoftkey down:NO]; }

- (int)scancodeForEvent:(NSEvent *)event {
    switch (event.keyCode) {
        case 126: return HCKeyUp;
        case 125: return HCKeyDown;
        case 123: return HCKeyLeft;
        case 124: return HCKeyRight;
        case 51: return HCKeyBackspace;
        case 53: return HCKeyRightSoftkey; // Escape
        case 122: return HCKeyLeftSoftkey; // F1
        case 120: return HCKeyRightSoftkey; // F2
        case 99: return HCKeyMenu;         // F3
        default: break;
    }
    NSString *chars = event.charactersIgnoringModifiers;
    return chars.length == 1 ? HCScancodeForCharacter([chars characterAtIndex:0]) : -1;
}

- (void)keyDown:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        [super keyDown:event];
        return;
    }
    int code = [self scancodeForEvent:event];
    if (code >= 0) {
        if (!event.isARepeat) [HCEmulator.shared key:(HCKey)code down:YES];
    } else {
        [super keyDown:event];
    }
}

- (void)keyUp:(NSEvent *)event {
    int code = [self scancodeForEvent:event];
    if (code >= 0) {
        [HCEmulator.shared key:(HCKey)code down:NO];
    } else {
        [super keyUp:event];
    }
}

@end

#endif
