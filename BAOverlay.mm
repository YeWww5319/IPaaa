//
//  BAOverlay.mm
//

#import "BAOverlay.h"
#import "BAConfig.h"
#import "BAWorld.h"
#import "BAPhysics.h"
#import "BAHomography.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

#define BA_COLOR_GREEN  [UIColor colorWithRed:0.20 green:1.00 blue:0.55 alpha:0.95]
#define BA_COLOR_CYAN   [UIColor colorWithRed:0.20 green:0.85 blue:1.00 alpha:0.90]
#define BA_COLOR_RED    [UIColor colorWithRed:1.00 green:0.28 blue:0.32 alpha:0.90]
#define BA_COLOR_YELLOW [UIColor colorWithRed:1.00 green:0.82 blue:0.25 alpha:0.90]

#pragma mark - 标定视图（依次点四个桌面角）

@class BAOverlay;

@interface BACalibrationView : UIView
@property (nonatomic, strong) NSMutableArray<NSValue *> *points;
@property (nonatomic, copy) void (^onDone)(NSArray<NSValue *> *pts);
@property (nonatomic, strong) UILabel *hint;
@end

@implementation BACalibrationView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        self.points = [NSMutableArray array];
        _hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 120)];
        _hint.numberOfLines = 0;
        _hint.textAlignment = NSTextAlignmentCenter;
        _hint.textColor = [UIColor whiteColor];
        _hint.font = [UIFont boldSystemFontOfSize:16];
        _hint.center = CGPointMake(frame.size.width / 2, 90);
        _hint.text = @"标定：依次点击球桌四个角\n1/4  左上角（远离你的那一侧左边）";
        [self addSubview:_hint];
    }
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = touches.anyObject;
    CGPoint p = [t locationInView:self];
    [self.points addObject:[NSValue valueWithCGPoint:p]];

    NSArray *names = @[@"左上角（远端左）", @"右上角（远端右）", @"右下角（近端右）", @"左下角（近端左）"];
    NSUInteger n = self.points.count;
    if (n < 4) {
        self.hint.text = [NSString stringWithFormat:@"标定：依次点击球桌四个角\n%lu/4  %@", (unsigned long)(n + 1), names[n]];
        // 画个点做反馈
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 18, 18)];
        dot.center = p;
        dot.backgroundColor = BA_COLOR_GREEN;
        dot.layer.cornerRadius = 9;
        [self addSubview:dot];
    } else {
        if (self.onDone) self.onDone(self.points.copy);
    }
}

@end

#pragma mark - 悬浮按钮

@interface BABall : UIView
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, copy) void (^onLongPress)(void);
@end

@implementation BABall {
    CGPoint _startCenter;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.55];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
        l.text = @"◎";
        l.textAlignment = NSTextAlignmentCenter;
        l.textColor = [UIColor whiteColor];
        l.font = [UIFont systemFontOfSize:frame.size.width * 0.6];
        [self addSubview:l];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLong:)];
        lp.minimumPressDuration = 0.8;
        [self addGestureRecognizer:lp];
    }
    return self;
}

- (void)handleTap { if (self.onTap) self.onTap(); }

- (void)handleLong:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) { if (self.onLongPress) self.onLongPress(); }
    else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint p = [g locationInView:self.superview];
        self.center = p;
    }
}

@end

#pragma mark - 主 Overlay

@implementation BAOverlay {
    UIWindow *_aimWindow;
    UIWindow *_ballWindow;
    BABall *_ball;

    CAShapeLayer *_aimLayer;
    CAShapeLayer *_ghostLayer;
    CAShapeLayer *_objLayer;
    CAShapeLayer *_cueLayer;
    CAShapeLayer *_ladderLayer;
    CATextLayer *_panel;

    CADisplayLink *_link;
    BAHomography _H;
    double _screenBallRadius;
    BOOL _visible;
    BOOL _calibrating;
    BACalibrationView *_calView;
}

+ (instancetype)shared {
    static BAOverlay *o;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ o = [[BAOverlay alloc] init]; });
    return o;
}

- (void)attach {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self buildWindows];
        [self rebuildHomography];
        [self startLink];
    });
}

#pragma mark - 建窗口

- (void)buildWindows {
    if (_aimWindow) return;
    CGRect bounds = [UIScreen mainScreen].bounds;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    vc.view.userInteractionEnabled = NO;

    _aimWindow = [[UIWindow alloc] initWithFrame:bounds];
    _aimWindow.rootViewController = vc;
    _aimWindow.windowLevel = UIWindowLevelAlert + 20;
    _aimWindow.backgroundColor = [UIColor clearColor];
    _aimWindow.userInteractionEnabled = NO;
    _aimWindow.hidden = NO;

    [self buildLayers];
    _visible = YES;

    // 悬浮按钮（唯一吃触摸的东西，用来开关 / 长按标定）
    _ballWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    _ballWindow.windowLevel = UIWindowLevelAlert + 21;
    _ballWindow.backgroundColor = [UIColor clearColor];
    _ballWindow.rootViewController = [[UIViewController alloc] init];
    _ballWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
    _ballWindow.hidden = NO;

    _ball = [[BABall alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    __weak typeof(self) ws = self;
    _ball.onTap = ^{ [ws toggleVisible]; };
    _ball.onLongPress = ^{
        __strong typeof(ws) ss = ws;
        [ss beginCalibration];
    };
    [_ballWindow addSubview:_ball];
    CGPoint c = CGPointMake(bounds.size.width - 46, bounds.size.height * 0.5);
    _ball.center = CGPointMake(c.x - bounds.origin.x, c.y - bounds.origin.y);
    _ballWindow.center = c;
}

- (void)buildLayers {
    UIView *host = _aimWindow.rootViewController.view;

    _aimLayer = [self newLayer:host color:BA_COLOR_GREEN width:2.0 dashed:NO];
    _ghostLayer = [self newLayer:host color:BA_COLOR_GREEN width:2.0 dashed:YES];
    _objLayer = [self newLayer:host color:BA_COLOR_CYAN width:2.0 dashed:YES];
    _cueLayer = [self newLayer:host color:BA_COLOR_YELLOW width:2.0 dashed:NO];
    _ladderLayer = [self newLayer:host color:BA_COLOR_YELLOW width:1.5 dashed:NO];

    _panel = [CATextLayer layer];
    _panel.frame = CGRectMake(12, 90, 250, 118);
    _panel.contentsScale = [UIScreen mainScreen].scale;
    _panel.fontSize = 10.5;
    _panel.font = (__bridge CFTypeRef)[UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium];
    _panel.foregroundColor = [UIColor whiteColor].CGColor;
    _panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45].CGColor;
    _panel.cornerRadius = 6;
    _panel.alignmentMode = kCAAlignmentLeft;
    _panel.wrapped = YES;
    [host.layer addSublayer:_panel];
}

- (CAShapeLayer *)newLayer:(UIView *)host color:(UIColor *)color width:(CGFloat)w dashed:(BOOL)dashed {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.frame = host.bounds;
    l.strokeColor = color.CGColor;
    l.fillColor = [UIColor clearColor].CGColor;
    l.lineWidth = w;
    l.lineCap = kCALineCapRound;
    l.lineJoin = kCALineJoinRound;
    if (dashed) {
        l.lineDashPattern = @[@6, @5];
    }
    [host.layer addSublayer:l];
    return l;
}

- (void)toggleVisible {
    _visible = !_visible;
    _aimWindow.hidden = !_visible;
    [_aimWindow.rootViewController.view setNeedsLayout];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
}

#pragma mark - 标定

- (void)startCalibration { [self beginCalibration]; }

- (void)beginCalibration {
    if (_calibrating) return;
    _calibrating = YES;
    _aimWindow.userInteractionEnabled = YES;

    UIView *host = _aimWindow.rootViewController.view;
    host.userInteractionEnabled = YES;
    _calView = [[BACalibrationView alloc] initWithFrame:host.bounds];
    __weak typeof(self) ws = self;
    _calView.onDone = ^(NSArray<NSValue *> *pts) {
        __strong typeof(ws) ss = ws;
        [ss finishCalibrationWithPoints:pts];
    };
    [host addSubview:_calView];
}

- (void)finishCalibrationWithPoints:(NSArray<NSValue *> *)pts {
    BAConfig *cfg = [BAConfig shared];
    cfg.cornerTL = [pts[0] CGPointValue];
    cfg.cornerTR = [pts[1] CGPointValue];
    cfg.cornerBR = [pts[2] CGPointValue];
    cfg.cornerBL = [pts[3] CGPointValue];
    cfg.screenSize = [UIScreen mainScreen].bounds.size;
    cfg.calibrated = YES;
    [cfg save];

    [_calView removeFromSuperview];
    _calView = nil;
    _calibrating = NO;
    _aimWindow.rootViewController.view.userInteractionEnabled = NO;
    _aimWindow.userInteractionEnabled = NO;

    [self rebuildHomography];
    UINotificationFeedbackGenerator *fb = [[UINotificationFeedbackGenerator alloc] init];
    [fb notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)rebuildHomography {
    BAConfig *cfg = [BAConfig shared];
    CGSize cur = [UIScreen mainScreen].bounds.size;
    if (cfg.calibrated && !CGSizeEqualToSize(cfg.screenSize, cur) && !CGSizeEqualToSize(cfg.screenSize, CGSizeZero)) {
        // 分辨率变了，按比例缩放标定点
        CGFloat sx = cur.width / cfg.screenSize.width;
        CGFloat sy = cur.height / cfg.screenSize.height;
        _H = baHomographyFromCorners(CGPointMake(cfg.cornerTL.x * sx, cfg.cornerTL.y * sy),
                                     CGPointMake(cfg.cornerTR.x * sx, cfg.cornerTR.y * sy),
                                     CGPointMake(cfg.cornerBR.x * sx, cfg.cornerBR.y * sy),
                                     CGPointMake(cfg.cornerBL.x * sx, cfg.cornerBL.y * sy),
                                     cfg.tableLength, cfg.tableWidth);
    } else if (cfg.calibrated) {
        _H = baHomographyFromCorners(cfg.cornerTL, cfg.cornerTR, cfg.cornerBR, cfg.cornerBL,
                                     cfg.tableLength, cfg.tableWidth);
    } else {
        // 未标定：用屏幕内缩一个安全区当默认值，能画但位置不会准
        CGRect b = [UIScreen mainScreen].bounds;
        CGFloat inset = 24;
        _H = baHomographyFromCorners(CGPointMake(inset, b.size.height * 0.22),
                                     CGPointMake(b.size.width - inset, b.size.height * 0.22),
                                     CGPointMake(b.size.width - inset, b.size.height * 0.78),
                                     CGPointMake(inset, b.size.height * 0.78),
                                     cfg.tableLength, cfg.tableWidth);
    }
    _screenBallRadius = baScreenBallRadius(_H, cfg.tableLength, cfg.ballRadius);
}

#pragma mark - 刷新

- (void)startLink {
    if (_link) return;
    BAConfig *cfg = [BAConfig shared];
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _link.preferredFramesPerSecond = (NSInteger)(cfg.refreshHz > 5 ? cfg.refreshHz : 30);
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tick {
    if (!_visible || _calibrating) return;

    BAConfig *cfg = [BAConfig shared];
    BABallSet set = [[BAWorld shared] snapshot];

    if (!set.ok || !set.stable || set.cueIndex < 0) {
        [self clearAll];
        _panel.string = @"读取中…\n（未取到球位置，检查 offset）";
        return;
    }

    BATable t = baDefaultTable();
    t.length = cfg.tableLength; t.width = cfg.tableWidth; t.ballRadius = cfg.ballRadius;
    t.rollDecel = cfg.rollDecel; t.cushionRest = cfg.cushionRest; t.maxSpeed = cfg.maxSpeed;
    t.pocketRadius = cfg.pocketRadius;

    BAVec2 cue = set.pts[set.cueIndex];
    bool alive[32];
    for (int i = 0; i < 32; i++) alive[i] = (i < set.count);
    alive[set.cueIndex] = false;

    BABestShot best = baBestShot(t, cue, set.pts, alive, set.count, 0.6);
    if (!best.valid) { [self clearAll]; _panel.string = @"没有可打的球"; return; }

    BAVec2 target = set.pts[best.ballIndex];
    BAVec2 pockets[6];
    baPockets(t, pockets, 6);
    BAVec2 pocket = pockets[best.pocketIndex];
    BAResult r = best.result;

    [self drawAim:best cue:cue target:target pocket:pocket t:t cfg:cfg];

    // 力度档位分析
    NSMutableString *txt = [NSMutableString string];
    if (cfg.showPowerLadder) {
        BAPowerRow rows[BA_POWER_STEPS];
        int n = baPowerLadder(t, cue, target, pocket, rows, BA_POWER_STEPS);
        [txt appendString:@"力度  母球走位      进袋\n"];
        for (int i = 0; i < n; i++) {
            NSString *pot = rows[i].potOk ? @"✓" : (rows[i].cueReaches ? @"✗力小" : @"✗不到");
            [txt appendFormat:@"%3.0f%%  %5.2fm         %@\n", rows[i].power * 100, rows[i].cueTravel, pot];
        }
        [txt appendFormat:@"切角 %.1f°  接触速 %.2f m/s", r.cutAngleDeg, r.contactSpeed];
    } else {
        [txt appendFormat:@"切角 %.1f°  母球走位 %.2fm", r.cutAngleDeg, r.cueTravel];
    }
    _panel.string = txt;
}

- (void)clearAll {
    for (CAShapeLayer *l in @[_aimLayer, _ghostLayer, _objLayer, _cueLayer, _ladderLayer]) {
        l.path = nil;
    }
}

- (void)drawAim:(BABestShot)best cue:(BAVec2)cue target:(BAVec2)target pocket:(BAVec2)pocket t:(BATable)t cfg:(BAConfig *)cfg {
    BAResult r = best.result;
    BAVec2 pockets[6];
    baPockets(t, pockets, 6);

    UIBezierPath *aim = [UIBezierPath bezierPath];
    UIBezierPath *ghost = [UIBezierPath bezierPath];
    UIBezierPath *obj = [UIBezierPath bezierPath];
    UIBezierPath *cuePath = [UIBezierPath bezierPath];
    UIBezierPath *ladder = [UIBezierPath bezierPath];

    CGPoint pCue = baTableToScreen(_H, cue);
    CGPoint pGhost = baTableToScreen(_H, r.ghost);
    CGPoint pTarget = baTableToScreen(_H, target);
    CGPoint pPocket = baTableToScreen(_H, pocket);

    // 1) 瞄准线：母球球心 -> 假想球球心，并延长到库边
    if (cfg.showAimLine) {
        BAVec2 dir = baUnit(baSub(r.ghost, cue));
        BAVec2 extend[24];
        double dist = 4.0;   // 足够扫到库边
        int n = baTrace(t, cue, dir, dist, extend, 24);
        [aim moveToPoint:pCue];
        for (int i = 1; i < n; i++) {
            CGPoint p = baTableToScreen(_H, extend[i]);
            [aim addLineToPoint:p];
        }
    }

    // 2) 假想球
    if (cfg.showGhostBall) {
        [ghost addArcWithCenter:pGhost radius:_screenBallRadius startAngle:0 endAngle:M_PI * 2 clockwise:YES];
    }

    // 3) 目标球 -> 袋口
    if (cfg.showObjectPath) {
        [obj moveToPoint:pTarget];
        [obj addLineToPoint:pPocket];
    }

    // 4) 母球撞击后路径（含库边折线）
    if (cfg.showCuePath) {
        BAVec2 aimDir = baUnit(baSub(r.ghost, cue));
        BAVec2 tangent = baPerp(baUnit(baSub(pocket, target)));
        if (baDot(tangent, aimDir) < 0) tangent = baMul(tangent, -1.0);
        BAVec2 pts[24];
        int n = baTrace(t, r.ghost, tangent, r.cueTravel, pts, 24);
        if (n > 0) {
            [cuePath moveToPoint:pGhost];
            for (int i = 1; i < n; i++) [cuePath addLineToPoint:baTableToScreen(_H, pts[i])];
        }
    }

    // 5) 力度档位停点
    if (cfg.showPowerLadder) {
        BAPowerRow rows[BA_POWER_STEPS];
        int n = baPowerLadder(t, cue, target, pocket, rows, BA_POWER_STEPS);
        for (int i = 0; i < n; i++) {
            CGPoint p = baTableToScreen(_H, rows[i].cueStop);
            [ladder addArcWithCenter:p radius:4.0 + i * 1.2 startAngle:0 endAngle:M_PI * 2 clockwise:YES];
        }
        ladder.lineWidth = 1.2;
    }

    _aimLayer.path = aim.CGPath;
    _ghostLayer.path = ghost.CGPath;
    _objLayer.path = obj.CGPath;
    _cueLayer.path = cuePath.CGPath;
    _ladderLayer.path = ladder.CGPath;
    _ladderLayer.strokeColor = BA_COLOR_YELLOW.CGColor;
}

@end
