#import <UIKit/UIKit.h>
#import "App.h"
#import "wkwvquic.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        wkwvquic_init();
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([App class]));
    }
}
