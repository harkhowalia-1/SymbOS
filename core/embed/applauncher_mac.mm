/*
 * Halcyon - macOS replacement for the iOS port's UIKit browser launcher.
 * Licensed under the GNU General Public License v3 or later.
 */
#import <AppKit/AppKit.h>

#include <common/applauncher.h>

namespace eka2l1::common {
    // Called when a Symbian app asks the OS to open a web page.
    bool launch_browser(const std::string &url) {
        @autoreleasepool {
            NSString *str = [NSString stringWithUTF8String:url.c_str()];
            NSURL *nsurl = [NSURL URLWithString:str];
            if (!nsurl) {
                return false;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSWorkspace sharedWorkspace] openURL:nsurl];
            });
            return true;
        }
    }
}
