//
//  BAConfig.mm
//

#import "BAConfig.h"
#import <UIKit/UIKit.h>

static BAConfig *gConfig = nil;

@implementation BAConfig

+ (instancetype)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gConfig = [[BAConfig alloc] init];
        [gConfig load];
    });
    return gConfig;
}

- (instancetype)init {
    if ((self = [super init])) {
        // 默认 9 尺美式台
        _tableLength   = 2.54;
        _tableWidth    = 1.27;
        _ballRadius    = 0.028575;
        _rollDecel     = 0.85;
        _cushionRest   = 0.62;
        _maxSpeed      = 6.5;
        _pocketRadius  = 0.06;

        _moduleName    = @"";
        _ballArrayOffset = 0;
        _ballCount     = 16;
        _ballStride    = 24;
        _ballXOffset   = 0;
        _ballYOffset   = 4;
        _ballValueType = 0;

        _calibrated = NO;
        _screenSize = CGSizeZero;

        _showAimLine     = YES;
        _showGhostBall   = YES;
        _showObjectPath  = YES;
        _showCuePath     = YES;
        _showPowerLadder = YES;
        _antiDetection   = YES;
        _refreshHz       = 30.0;
    }
    return self;
}

- (NSString *)configPath {
    // 优先用 App 自己的 Documents（注入进包里的场景），
    // 没有就落到越狱的 Preferences 目录
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length) {
        NSString *p = [docs stringByAppendingPathComponent:@"BilliardsAim.plist"];
        BOOL writable = [[NSFileManager defaultManager] isWritableFileAtPath:docs];
        if (writable) return p;
    }
    return @"/var/mobile/Library/Preferences/com.zaka.billiardsaim.plist";
}

- (void)load {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self configPath]];
    if (!d) return;

    #define RD(_k, _f, _v) if (d[_k]) self._f = [d[_k] _v];
    RD(@"tableLength",   tableLength,   doubleValue);
    RD(@"tableWidth",    tableWidth,    doubleValue);
    RD(@"ballRadius",    ballRadius,    doubleValue);
    RD(@"rollDecel",     rollDecel,     doubleValue);
    RD(@"cushionRest",   cushionRest,   doubleValue);
    RD(@"maxSpeed",      maxSpeed,      doubleValue);
    RD(@"pocketRadius",  pocketRadius,  doubleValue);

    if (d[@"moduleName"]) self.moduleName = d[@"moduleName"];
    RD(@"ballArrayOffset", ballArrayOffset, unsignedLongLongValue);
    RD(@"ballCount",     ballCount,     intValue);
    RD(@"ballStride",    ballStride,    intValue);
    RD(@"ballXOffset",   ballXOffset,   intValue);
    RD(@"ballYOffset",   ballYOffset,   intValue);
    RD(@"ballValueType", ballValueType, intValue);

    RD(@"calibrated",    calibrated,    boolValue);
    if (d[@"cornerTL"]) self.cornerTL = CGPointFromString(d[@"cornerTL"]);
    if (d[@"cornerTR"]) self.cornerTR = CGPointFromString(d[@"cornerTR"]);
    if (d[@"cornerBR"]) self.cornerBR = CGPointFromString(d[@"cornerBR"]);
    if (d[@"cornerBL"]) self.cornerBL = CGPointFromString(d[@"cornerBL"]);
    if (d[@"screenSize"]) self.screenSize = CGSizeFromString(d[@"screenSize"]);

    RD(@"showAimLine",     showAimLine,     boolValue);
    RD(@"showGhostBall",   showGhostBall,   boolValue);
    RD(@"showObjectPath",  showObjectPath,  boolValue);
    RD(@"showCuePath",     showCuePath,     boolValue);
    RD(@"showPowerLadder", showPowerLadder, boolValue);
    RD(@"antiDetection",   antiDetection,   boolValue);
    RD(@"refreshHz",       refreshHz,       doubleValue);
    #undef RD
}

- (void)save {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"tableLength"]   = @(self.tableLength);
    d[@"tableWidth"]    = @(self.tableWidth);
    d[@"ballRadius"]    = @(self.ballRadius);
    d[@"rollDecel"]     = @(self.rollDecel);
    d[@"cushionRest"]   = @(self.cushionRest);
    d[@"maxSpeed"]      = @(self.maxSpeed);
    d[@"pocketRadius"]  = @(self.pocketRadius);

    d[@"moduleName"]        = self.moduleName ?: @"";
    d[@"ballArrayOffset"]   = @(self.ballArrayOffset);
    d[@"ballCount"]         = @(self.ballCount);
    d[@"ballStride"]        = @(self.ballStride);
    d[@"ballXOffset"]       = @(self.ballXOffset);
    d[@"ballYOffset"]       = @(self.ballYOffset);
    d[@"ballValueType"]     = @(self.ballValueType);

    d[@"calibrated"] = @(self.calibrated);
    d[@"cornerTL"]   = NSStringFromCGPoint(self.cornerTL);
    d[@"cornerTR"]   = NSStringFromCGPoint(self.cornerTR);
    d[@"cornerBR"]   = NSStringFromCGPoint(self.cornerBR);
    d[@"cornerBL"]   = NSStringFromCGPoint(self.cornerBL);
    d[@"screenSize"] = NSStringFromCGSize(self.screenSize);

    d[@"showAimLine"]     = @(self.showAimLine);
    d[@"showGhostBall"]   = @(self.showGhostBall);
    d[@"showObjectPath"]  = @(self.showObjectPath);
    d[@"showCuePath"]     = @(self.showCuePath);
    d[@"showPowerLadder"] = @(self.showPowerLadder);
    d[@"antiDetection"]   = @(self.antiDetection);
    d[@"refreshHz"]       = @(self.refreshHz);

    [d writeToFile:[self configPath] atomically:YES];
}

@end
