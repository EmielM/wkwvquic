#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface App : UIViewController <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow* win;
@property (strong, nonatomic) UIScreen* screen;
@property (readonly) WKWebView* web;

@end


