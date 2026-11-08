//
//  BAHomography.mm
//

#import "BAHomography.h"
#include <math.h>
#include <string.h>

// 高斯消元解 n 元一次方程组，A 为 n x (n+1) 增广矩阵
static bool baSolveLinear(double *A, int n, double *x) {
    for (int col = 0; col < n; col++) {
        int piv = col;
        double best = fabs(A[col * (n + 1) + col]);
        for (int r = col + 1; r < n; r++) {
            double v = fabs(A[r * (n + 1) + col]);
            if (v > best) { best = v; piv = r; }
        }
        if (best < 1e-12) return false;
        if (piv != col) {
            for (int c = 0; c <= n; c++) {
                double tmp = A[col * (n + 1) + c];
                A[col * (n + 1) + c] = A[piv * (n + 1) + c];
                A[piv * (n + 1) + c] = tmp;
            }
        }
        double d = A[col * (n + 1) + col];
        for (int c = col; c <= n; c++) A[col * (n + 1) + c] /= d;
        for (int r = 0; r < n; r++) {
            if (r == col) continue;
            double f = A[r * (n + 1) + col];
            if (f == 0) continue;
            for (int c = col; c <= n; c++) A[r * (n + 1) + c] -= f * A[col * (n + 1) + c];
        }
    }
    for (int i = 0; i < n; i++) x[i] = A[i * (n + 1) + n];
    return true;
}

BAHomography baHomographyFromCorners(CGPoint tl, CGPoint tr, CGPoint br, CGPoint bl,
                                     double tableLength, double tableWidth) {
    BAHomography h;
    memset(&h, 0, sizeof(h));

    double src[4][2] = { {0, 0}, {tableLength, 0}, {tableLength, tableWidth}, {0, tableWidth} };
    CGPoint dst[4]   = { tl, tr, br, bl };

    // 8 个未知量 h0..h7（h8 = 1）
    double A[8 * 9];
    memset(A, 0, sizeof(A));
    for (int i = 0; i < 4; i++) {
        double X = src[i][0], Y = src[i][1];
        double u = dst[i].x, v = dst[i].y;
        int r = i * 2;
        A[r * 9 + 0] = X; A[r * 9 + 1] = Y; A[r * 9 + 2] = 1;
        A[r * 9 + 6] = -u * X; A[r * 9 + 7] = -u * Y; A[r * 9 + 8] = u;

        A[(r + 1) * 9 + 3] = X; A[(r + 1) * 9 + 4] = Y; A[(r + 1) * 9 + 5] = 1;
        A[(r + 1) * 9 + 6] = -v * X; A[(r + 1) * 9 + 7] = -v * Y; A[(r + 1) * 9 + 8] = v;
    }

    double sol[8];
    if (!baSolveLinear(A, 8, sol)) return h;

    h.m[0] = sol[0]; h.m[1] = sol[1]; h.m[2] = sol[2];
    h.m[3] = sol[3]; h.m[4] = sol[4]; h.m[5] = sol[5];
    h.m[6] = sol[6]; h.m[7] = sol[7]; h.m[8] = 1.0;
    h.valid = true;
    return h;
}

CGPoint baTableToScreen(BAHomography h, BAVec2 p) {
    if (!h.valid) return CGPointZero;
    double X = p.x, Y = p.y;
    double w = h.m[6] * X + h.m[7] * Y + h.m[8];
    if (fabs(w) < 1e-12) w = 1e-12;
    double u = (h.m[0] * X + h.m[1] * Y + h.m[2]) / w;
    double v = (h.m[3] * X + h.m[4] * Y + h.m[5]) / w;
    return CGPointMake(u, v);
}

double baScreenBallRadius(BAHomography h, double tableLength, double ballRadius) {
    // 在桌面中心附近取两点，量 2R 对应的屏幕距离
    BAVec2 a = BAV2(tableLength * 0.5, 0.6);
    BAVec2 b = BAV2(tableLength * 0.5 + 2.0 * ballRadius, 0.6);
    CGPoint pa = baTableToScreen(h, a);
    CGPoint pb = baTableToScreen(h, b);
    double d = hypot(pb.x - pa.x, pb.y - pa.y);
    return d * 0.5 > 1.0 ? d * 0.5 : 1.0;
}
