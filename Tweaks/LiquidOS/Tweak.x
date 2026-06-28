#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Variables

static UIView *liquidIsland = nil;
static UILabel *titleLabel = nil;

#pragma mark - Helper

static UIWindow *GetMainWindow(void) {

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        if (windowScene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }

        for (UIWindow *window in windowScene.windows) {

            if (window.isKeyWindow) {
                return window;
            }

        }

    }

    return nil;
}

#pragma mark - Island

static void CreateIsland(void) {

    if (liquidIsland)
        return;

    UIWindow *window = GetMainWindow();

    if (!window)
        return;

    CGFloat width = 165.0;
    CGFloat height = 38.0;

    CGFloat x = (UIScreen.mainScreen.bounds.size.width - width) / 2.0;
    CGFloat y = window.safeAreaInsets.top + 6.0;

    liquidIsland = [[UIView alloc] initWithFrame:CGRectMake(x, y, width, height)];

    liquidIsland.backgroundColor = UIColor.blackColor;

    liquidIsland.layer.cornerRadius = height / 2.0;

    liquidIsland.layer.masksToBounds = NO;

    liquidIsland.layer.shadowColor = UIColor.blackColor.CGColor;
    liquidIsland.layer.shadowOpacity = 0.35;
    liquidIsland.layer.shadowRadius = 10;
    liquidIsland.layer.shadowOffset = CGSizeMake(0, 4);

    liquidIsland.alpha = 0.0;
    liquidIsland.transform = CGAffineTransformMakeScale(0.8, 0.8);

    titleLabel = [[UILabel alloc] initWithFrame:liquidIsland.bounds];

    titleLabel.text = @"LiquidOS";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];

    [liquidIsland addSubview:titleLabel];
    [window addSubview:liquidIsland];
}

#pragma mark - Animation

static void ShowIsland(void) {

    if (!liquidIsland)
        return;

    [UIView animateWithDuration:0.45
                          delay:0.0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{

        liquidIsland.alpha = 1.0;
        liquidIsland.transform = CGAffineTransformIdentity;

    } completion:nil];
}

#pragma mark - Hook

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {

    %orig;

    NSLog(@"[LiquidOS] Loaded");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{

        CreateIsland();
        ShowIsland();

    });
}

%end