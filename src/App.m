#import "App.h"
#import "fishhook.h"

@implementation App

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    _screen = [UIScreen mainScreen];
    _win = [[UIWindow alloc] initWithFrame:_screen.bounds];
    _win.rootViewController = self;
    _win.backgroundColor = [UIColor blackColor];
    [_win makeKeyAndVisible];
    
    return YES;
}

- (void)loadView {
    
    WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc] init];
    
    _web = [[WKWebView alloc] initWithFrame:_screen.bounds configuration:config];
    _web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    //_web.navigationDelegate = self;
    //_web.UIDelegate = self;
    
    [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://google.com/"]]];

    self.view = _web;
}

@end
