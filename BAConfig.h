//
//  BAConfig.h — 配置读写
//

#ifndef BACONFIG_H
#define BACONFIG_H

#import <Foundation/Foundation.h>

@interface BAConfig : NSObject

@property (nonatomic, assign) double tableLength;      // 台面长边 m
@property (nonatomic, assign) double tableWidth;       // 台面短边 m
@property (nonatomic, assign) double ballRadius;       // 球半径 m
@property (nonatomic, assign) double rollDecel;        // 滚动减速度
@property (nonatomic, assign) double cushionRest;      // 库边恢复系数
@property (nonatomic, assign) double maxSpeed;         // 满力初速
@property (nonatomic, assign) double pocketRadius;

// 内存读取参数（用户用 IDA / Frida 找到后填这里）
@property (nonatomic, copy)   NSString *moduleName;    // 主可执行文件名，留空=自动取主程序
@property (nonatomic, assign) unsigned long long ballArrayOffset; // 球数组相对模块基址偏移
@property (nonatomic, assign) int    ballCount;        // 球数，8球=16，9球=10
@property (nonatomic, assign) int    ballStride;       // 每颗球结构体步长（字节）
@property (nonatomic, assign) int    ballXOffset;      // 结构体内 x 偏移
@property (nonatomic, assign) int    ballYOffset;      // 结构体内 y 偏移
@property (nonatomic, assign) int    ballValueType;    // 0=float 1=double 2=int32(毫米)

// 结束球 2D 屏幕坐标（四点标定，右上/右下等）
@property (nonatomic, assign) BOOL   calibrated;
@property (nonatomic, assign) CGPoint cornerTL;   // 桌面 (0,0)
@property (nonatomic, assign) CGPoint cornerTR;   // 桌面 (length,0)
@property (nonatomic, assign) CGPoint cornerBR;   // 桌面 (length,width)
@property (nonatomic, assign) CGPoint cornerBL;   // 桌面 (0,width)
@property (nonatomic, assign) CGSize screenSize;  // 标定时的屏幕尺寸，变了要重标

// 显示开关
@property (nonatomic, assign) BOOL showAimLine;
@property (nonatomic, assign) BOOL showGhostBall;
@property (nonatomic, assign) BOOL showObjectPath;
@property (nonatomic, assign) BOOL showCuePath;
@property (nonatomic, assign) BOOL showPowerLadder;
@property (nonatomic, assign) BOOL antiDetection;
@property (nonatomic, assign) double refreshHz;

+ (instancetype)shared;
- (void)load;
- (void)save;

- (NSString *)configPath;

@end

#endif
