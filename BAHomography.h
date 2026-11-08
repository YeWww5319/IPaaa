//
//  BAHomography.h — 球桌平面 -> 屏幕像素 的透视变换（四点标定）
//  桌面上任意一点在屏幕上都是过单应矩阵映射，3D 视角下也成立（只对球桌平面精确）。
//

#ifndef BAHOMOGRAPHY_H
#define BAHOMOGRAPHY_H

#include <CoreGraphics/CoreGraphics.h>
#include "BAPhysics.h"

typedef struct {
    double m[9];   // 行主序 3x3，m[8] 归一化为 1
    bool   valid;
} BAHomography;

// 用屏幕上四个桌面角点求解（顺序：左上 / 右上 / 右下 / 左下，对应桌面坐标 (0,0)(L,0)(L,W)(0,W)）
BAHomography baHomographyFromCorners(CGPoint tl, CGPoint tr, CGPoint br, CGPoint bl,
                                     double tableLength, double tableWidth);

// 桌面坐标 -> 屏幕坐标
CGPoint baTableToScreen(BAHomography h, BAVec2 tablePt);

// 求解单应后，用两点距离估算屏幕上的球半径像素值（便于画圆）
double baScreenBallRadius(BAHomography h, double tableLength, double ballRadius);

#endif
