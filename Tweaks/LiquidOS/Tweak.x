// LiquidIsland.xm
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <stdlib.h>

// ─────────────────────────────────────────────────────────────
// MARK: - Spring solver
// ─────────────────────────────────────────────────────────────

typedef struct {
    double mass;
    double stiffness;
    double damping;
    double v0;
} SpringParams;

static double SolveSpring(double t, SpringParams p, BOOL *outSettled)
{
    double w0   = sqrt(p.stiffness / p.mass);
    double zeta = p.damping / (2.0 * sqrt(p.stiffness * p.mass));
    double result;

    if (zeta < 1.0) {
        double wd = w0 * sqrt(1.0 - zeta * zeta);
        double B  = (zeta * w0 + p.v0) / wd;
        result = 1.0 - exp(-zeta * w0 * t) * (cos(wd * t) + B * sin(wd * t));
    } else {
        double r = -w0;
        result = 1.0 - exp(r * t) * (1.0 + (p.v0 - r) * t);
    }

    if (outSettled)
        *outSettled = (fabs(result - 1.0) < 0.0005 && t > 0.15);

    return result;
}

// ─────────────────────────────────────────────────────────────
// MARK: - Animator
// ─────────────────────────────────────────────────────────────

@interface LiquidIslandAnimator : NSObject {
    CADisplayLink  *_link;
    CFTimeInterval  _startTime;
    double _fromScale, _toScale;
    double _fromTY,    _toTY;
    double _fromAlpha, _toAlpha;
    double _fromShadow,_toShadow;
    SpringParams    _params;
    void (^_completion)(void);
    __weak CALayer *_targetLayer;
}
+ (instancetype)shared;
- (void)animateLayer:(CALayer *)layer
           fromScale:(double)fs  toScale:(double)ts
               fromY:(double)fy      toY:(double)ty
          fromAlpha:(double)fa   toAlpha:(double)ta
         fromShadow:(double)fsh toShadow:(double)tsh
             spring:(SpringParams)params
         completion:(void(^)(void))completion;
- (void)cancel;
@end

@implementation LiquidIslandAnimator

+ (instancetype)shared {
    static LiquidIslandAnimator *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (void)cancel {
    [_link invalidate];
    _link = nil;
}

- (void)animateLayer:(CALayer *)layer
           fromScale:(double)fs  toScale:(double)ts
               fromY:(double)fy      toY:(double)ty
          fromAlpha:(double)fa   toAlpha:(double)ta
         fromShadow:(double)fsh toShadow:(double)tsh
             spring:(SpringParams)params
         completion:(void(^)(void))completion
{
    [self cancel];
    _targetLayer  = layer;
    _fromScale=fs; _toScale=ts;
    _fromTY=fy;    _toTY=ty;
    _fromAlpha=fa; _toAlpha=ta;
    _fromShadow=fsh; _toShadow=tsh;
    _params=params;
    _completion=completion;
    _startTime=0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.transform = CATransform3DMakeScale((CGFloat)fs, (CGFloat)fs, 1.0);
    layer.opacity   = (float)fa;
    [CATransaction commit];

    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(_tick:)];
    if (@available(iOS 15.0, *)) {
        _link.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    }
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)_tick:(CADisplayLink *)link
{
    CALayer *layer = _targetLayer;
    if (!layer) { [self cancel]; return; }

    if (_startTime == 0) _startTime = link.timestamp;
    double t = link.timestamp - _startTime;

    BOOL settled = NO;
    double p = SolveSpring(t, _params, &settled);
    if (p < 0.0) p = 0.0;
    if (p > 2.0) p = 2.0;

    double sc  = _fromScale  + (_toScale  - _fromScale)  * p;
    double ty  = _fromTY     + (_toTY     - _fromTY)     * p;
    double al  = _fromAlpha  + (_toAlpha  - _fromAlpha)  * p;
    double sh  = _fromShadow + (_toShadow - _fromShadow) * p;
    if (al < 0.0) al = 0.0; if (al > 1.0) al = 1.0;
    if (sh < 0.0) sh = 0.0; if (sh > 1.0) sh = 1.0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CATransform3D tr = CATransform3DIdentity;
    tr = CATransform3DScale(tr, (CGFloat)sc, (CGFloat)sc, 1.0);
    tr = CATransform3DTranslate(tr, 0, (CGFloat)(ty / sc), 0);
    layer.transform     = tr;
    layer.opacity       = (float)al;
    layer.shadowOpacity = (float)sh;
    [CATransaction commit];

    if (settled) {
        [self cancel];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CATransform3D fin = CATransform3DMakeScale((CGFloat)_toScale,
                                                   (CGFloat)_toScale, 1.0);
        fin = CATransform3DTranslate(fin, 0, (CGFloat)_toTY, 0);
        layer.transform     = fin;
        layer.opacity       = (float)_toAlpha;
        layer.shadowOpacity = (float)_toShadow;
        [CATransaction commit];
        if (_completion) _completion();
    }
}

@end

// ─────────────────────────────────────────────────────────────
// MARK: - Forward declarations (C functions dùng bởi GR)
// ─────────────────────────────────────────────────────────────

static void PressDown(void);
static void PressUp(void);

// ─────────────────────────────────────────────────────────────
// MARK: - Gesture handler
// ─────────────────────────────────────────────────────────────

@interface LiquidIslandGR : NSObject
+ (instancetype)shared;
- (void)handle:(UILongPressGestureRecognizer *)gr;
@end

@implementation LiquidIslandGR
+ (instancetype)shared {
    static LiquidIslandGR *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}
- (void)handle:(UILongPressGestureRecognizer *)gr {
    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
            PressDown(); break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            PressUp(); break;
        default: break;
    }
}
@end

// ─────────────────────────────────────────────────────────────
// MARK: - State + Spring presets
// ─────────────────────────────────────────────────────────────

static UIView  *gIsland  = nil;
static UILabel *gLabel   = nil;
static BOOL     gVisible = NO;
static BOOL     gPressed = NO;

static const SpringParams kSpringShow    = {1.0, 220.0, 20.0, 0.4};
static const SpringParams kSpringHide    = {1.0, 300.0, 32.0, 0.0};
static const SpringParams kSpringPress   = {1.2, 400.0, 30.0, 0.0};
static const SpringParams kSpringRelease = {1.0, 240.0, 17.0, 1.6};

// ─────────────────────────────────────────────────────────────
// MARK: - Window helper
// ─────────────────────────────────────────────────────────────

static UIWindow *GetWindow(void)
{
    if (@available(iOS 13.0, *))
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes)
            if ([sc isKindOfClass:[UIWindowScene class]])
                for (UIWindow *w in ((UIWindowScene *)sc).windows)
                    if (w.isKeyWindow) return w;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
}

// ─────────────────────────────────────────────────────────────
// MARK: - Layer setup
// ─────────────────────────────────────────────────────────────

static void SetupLayerForGPU(UIView *v, CGFloat height)
{
    CALayer *l = v.layer;
    l.shouldRasterize    = YES;
    l.rasterizationScale = UIScreen.mainScreen.scale;
    l.drawsAsynchronously = NO;
    l.shadowColor   = UIColor.blackColor.CGColor;
    l.shadowOpacity = 0.35f;
    l.shadowRadius  = 16.0f;
    l.shadowOffset  = CGSizeMake(0, 5);
    l.shadowPath    = [UIBezierPath bezierPathWithRoundedRect:v.bounds
                                                 cornerRadius:height / 2.0f].CGPath;
    l.borderWidth   = 0.5f;
    l.borderColor   = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    l.cornerRadius  = height / 2.0f;
    l.masksToBounds = NO;
}

// ─────────────────────────────────────────────────────────────
// MARK: - CreateIsland
// ─────────────────────────────────────────────────────────────

static void CreateIsland(void)
{
    if (gIsland) return;
    UIWindow *w = GetWindow();
    if (!w) return;

    CGFloat sw     = UIScreen.mainScreen.bounds.size.width;
    CGFloat width  = 160.0f;
    CGFloat height = 38.0f;
    CGFloat x      = (sw - width) / 2.0f;

    gIsland = [[UIView alloc] initWithFrame:CGRectMake(x, 8.0f, width, height)];
    gIsland.backgroundColor = UIColor.blackColor;
    SetupLayerForGPU(gIsland, height);

    CAGradientLayer *hl = [CAGradientLayer layer];
    hl.frame = CGRectMake(0, 0, width, height / 2.0f);
    hl.colors = @[
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.11].CGColor,
        (__bridge id)[UIColor clearColor].CGColor
    ];
    hl.startPoint   = CGPointMake(0.5, 0.0);
    hl.endPoint     = CGPointMake(0.5, 1.0);
    hl.cornerRadius = height / 2.0f;
    [gIsland.layer addSublayer:hl];

    gLabel = [[UILabel alloc] initWithFrame:gIsland.bounds];
    gLabel.text          = @"LiquidOS";
    gLabel.textAlignment = NSTextAlignmentCenter;
    gLabel.textColor     = UIColor.whiteColor;
    gLabel.font          = [UIFont systemFontOfSize:15.0
                                             weight:UIFontWeightSemibold];
    gLabel.layer.shouldRasterize    = YES;
    gLabel.layer.rasterizationScale = UIScreen.mainScreen.scale;
    [gIsland addSubview:gLabel];

    gIsland.layer.opacity   = 0.0f;
    gIsland.layer.transform = CATransform3DMakeScale(0.82f, 0.82f, 1.0f);

    UILongPressGestureRecognizer *gr =
        [[UILongPressGestureRecognizer alloc]
         initWithTarget:[LiquidIslandGR shared]
                 action:@selector(handle:)];
    gr.minimumPressDuration = 0;
    [gIsland addGestureRecognizer:gr];
    gIsland.userInteractionEnabled = YES;

    [w addSubview:gIsland];
}

// ─────────────────────────────────────────────────────────────
// MARK: - Animation API
// ─────────────────────────────────────────────────────────────

static void ShowIsland(void)
{
    if (!gIsland || gVisible) return;
    gVisible = YES;
    [[LiquidIslandAnimator shared]
     animateLayer:gIsland.layer
        fromScale:0.82 toScale:1.0
            fromY:-4.0     toY:0.0
       fromAlpha:0.0   toAlpha:1.0
      fromShadow:0.0  toShadow:0.35
           spring:kSpringShow
       completion:nil];
}

static void HideIsland(void)
{
    if (!gIsland || !gVisible) return;
    gVisible = NO;
    [[LiquidIslandAnimator shared]
     animateLayer:gIsland.layer
        fromScale:1.0  toScale:0.92
            fromY:0.0      toY:-5.0
       fromAlpha:1.0   toAlpha:0.0
      fromShadow:0.35 toShadow:0.0
           spring:kSpringHide
       completion:nil];
}

static void PressDown(void)
{
    if (!gIsland || gPressed) return;
    gPressed = YES;
    [[LiquidIslandAnimator shared]
     animateLayer:gIsland.layer
        fromScale:1.0  toScale:0.84
            fromY:0.0      toY:-6.0
       fromAlpha:1.0   toAlpha:1.0
      fromShadow:0.35 toShadow:0.10
           spring:kSpringPress
       completion:nil];
}

static void PressUp(void)
{
    if (!gIsland || !gPressed) return;
    gPressed = NO;
    [[LiquidIslandAnimator shared]
     animateLayer:gIsland.layer
        fromScale:0.84 toScale:1.0
            fromY:-6.0     toY:0.0
       fromAlpha:1.0   toAlpha:1.0
      fromShadow:0.10 toShadow:0.35
           spring:kSpringRelease
       completion:nil];
}

// ─────────────────────────────────────────────────────────────
// MARK: - Hook
// ─────────────────────────────────────────────────────────────

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        CreateIsland();
        gLabel.text = @"LiquidOS";
        ShowIsland();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            HideIsland();
        });
    });
}
%end