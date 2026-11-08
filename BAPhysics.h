//
//  BAPhysics.h — 台球几何/物理求解核心
//  纯数学，不依赖游戏内部结构。所有输入输出都在「球桌平面坐标系」里：
//  原点 = 球桌左上角(短边靠左)，x 轴沿长边，y 轴沿短边，单位米。
//

#ifndef BAPHYSICS_H
#define BAPHYSICS_H

#include <stdbool.h>

typedef struct { double x, y; } BAVec2;

static inline BAVec2 BAV2(double x, double y) { BAVec2 v; v.x = x; v.y = y; return v; }
static inline BAVec2 baAdd(BAVec2 a, BAVec2 b) { return BAV2(a.x + b.x, a.y + b.y); }
static inline BAVec2 baSub(BAVec2 a, BAVec2 b) { return BAV2(a.x - b.x, a.y - b.y); }
static inline BAVec2 baMul(BAVec2 a, double s) { return BAV2(a.x * s, a.y * s); }
static inline double baDot(BAVec2 a, BAVec2 b) { return a.x * b.x + a.y * b.y; }
static inline double baLen(BAVec2 a) { return __builtin_sqrt(a.x * a.x + a.y * a.y); }
static inline BAVec2 baUnit(BAVec2 a) { double l = baLen(a); return l > 1e-9 ? baMul(a, 1.0 / l) : BAV2(0, 0); }
static inline BAVec2 baPerp(BAVec2 a) { return BAV2(-a.y, a.x); }

typedef struct {
    double length;        // 台面长边 (m)  默认 2.54 (9尺)
    double width;         // 台面短边 (m)  默认 1.27
    double ballRadius;    // 球半径 (m)    默认 0.028575 (57.15mm 标准美式)
    double rollDecel;     // 滚动减速度 (m/s^2)  默认 0.32 (台呢摩擦+滚动阻力实测近似)
    double cushionRest;   // 库边恢复系数 0.62
    double maxSpeed;      // 满力出杆初速 (m/s) 默认 7.2
    double pocketRadius;  // 袋口半径 (m) 默认 0.06
} BATable;

// 默认 9 尺美式台
BATable baDefaultTable(void);

// 6 个袋口坐标（4 角 + 2 中袋）
int baPockets(BATable t, BAVec2 *out, int maxCount);

// 一条完整解算结果
typedef struct {
    bool     valid;             // 几何上是否可解
    bool     cueReaches;        // 该力度下母球能否走到撞击点
    bool     potOk;             // 目标球是否有足够动能到袋
    BAVec2   ghost;             // 假想球球心（母球撞击时应在的位置）
    double   cutAngleDeg;       // 切角
    double   contactSpeed;      // 母球到达撞击点时的速度 m/s
    double   objectSpeed;       // 目标球出球速度 m/s
    double   objectTravel;      // 目标球按动能可走距离 m
    double   cueSpeedAfter;     // 母球撞击后速度 (沿切线)
    double   cueTravel;         // 母球撞击后滚动距离 m
    BAVec2   cueStop;           // 母球最终停点
    double   approachDist;      // 母球到假想球的距离
    double   pocketDist;        // 目标球到袋距离
} BAResult;

// 单杆解算：母球 / 目标球 / 袋口 / 力度(0~1)
BAResult baSolveShot(BATable t, BAVec2 cue, BAVec2 target, BAVec2 pocket, double power);

// 母球从 start 出发、方向 dir、可滚动 distance 距离，追踪库边反弹后的折线路径
// 返回写入 out 的点数（含起点与终点）
int baTrace(BATable t, BAVec2 start, BAVec2 dir, double distance, BAVec2 *out, int maxPts);

// 同上，只取终点
BAVec2 baStopPoint(BATable t, BAVec2 start, BAVec2 dir, double distance);

// 库边反弹（翻袋）瞄准点：母球打目标球，先用一面库把目标球送进袋
// 返回需要瞄准的「镜像袋口」在真实桌面上的坐标
BAVec2 baBankPocketFromCushion(BATable t, BAVec2 target, BAVec2 pocket, int cushionSide);

// 全桌最优解：在给定力度下，为母球从所有目标球 × 所有袋口中挑出最优的一杆
typedef struct {
    bool     valid;
    int      ballIndex;         // 命中哪颗球
    int      pocketIndex;       // 进哪个袋
    BAResult result;
} BABestShot;

BABestShot baBestShot(BATable t, BAVec2 cue, const BAVec2 *balls, const bool *alive,
                      int count, double power);

// 母球撞击后速度 -> 滚动距离（含多次库边损耗近似）
double baRollDistance(BATable t, double speed);

// 力度档位落点分析（不同力度的母球停点 + 是否进球）
#define BA_POWER_STEPS 5
typedef struct {
    double   power;
    bool     potOk;
    bool     cueReaches;
    BAVec2   cueStop;
    double   cueTravel;
} BAPowerRow;

int baPowerLadder(BATable t, BAVec2 cue, BAVec2 target, BAVec2 pocket, BAPowerRow *out, int maxRows);

#endif
