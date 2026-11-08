//
//  BAWorld.h — 从游戏内存里取球的位置（只读，不写任何游戏数据）
//

#ifndef BAWORLD_H
#define BAWORLD_H

#import <Foundation/Foundation.h>
#include "BAPhysics.h"

typedef struct {
    int    count;        // 有效球数
    int    cueIndex;     // 母球下标（找不到 = -1）
    bool   stable;       // 与上一帧相比是否静止（判断能不能出瞄准线）
    bool   ok;           // 本帧读取是否成功
    BAVec2 pts[32];      // 桌面坐标（米）
} BABallSet;

@interface BAWorld : NSObject

+ (instancetype)shared;
- (void)start;
- (BABallSet)snapshot;

// 手动指定球数组绝对地址（调试用，算一次就不用再扫）
- (void)setManualAddress:(unsigned long long)addr;

@end

#endif
