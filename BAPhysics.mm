//
//  BAPhysics.mm
//

#import "BAPhysics.h"
#include <math.h>
#include <string.h>

static inline double baClamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

BATable baDefaultTable(void) {
    BATable t;
    t.length       = 2.54;
    t.width        = 1.27;
    t.ballRadius   = 0.028575;
    t.rollDecel    = 0.85;   // 台呢滚动减速度实测近似值（中力出球走 3~4m）
    t.cushionRest  = 0.62;
    t.maxSpeed     = 6.5;
    t.pocketRadius = 0.06;
    return t;
}

double baRollDistance(BATable t, double speed) {
    if (speed <= 0) return 0;
    // 无库边时的纯滚动距离
    double raw = (speed * speed) / (2.0 * t.rollDecel);
    // 库边损耗在 baTrace 里逐步按 energy 折算，这里只做保守修正
    return raw;
}

int baPockets(BATable t, BAVec2 *out, int maxCount) {
    BAVec2 p[6] = {
        BAV2(0,          0),
        BAV2(t.length/2, 0),
        BAV2(t.length,   0),
        BAV2(0,          t.width),
        BAV2(t.length/2, t.width),
        BAV2(t.length,   t.width),
    };
    int n = maxCount < 6 ? maxCount : 6;
    for (int i = 0; i < n; i++) out[i] = p[i];
    return n;
}

int baTrace(BATable t, BAVec2 start, BAVec2 dir, double distance, BAVec2 *out, int maxPts) {
    if (maxPts <= 0) return 0;
    int n = 0;
    out[n++] = start;
    double remain = distance;
    BAVec2 p = start;
    BAVec2 d = baUnit(dir);
    if (remain <= 1e-6 || (d.x == 0 && d.y == 0)) return n;

    const double r = t.ballRadius;
    for (int guard = 0; guard < 24 && remain > 1e-4; guard++) {
        double tXp = (d.x >  1e-9) ? ((t.length - r) - p.x) / d.x : INFINITY;
        double tXn = (d.x < -1e-9) ? ((r) - p.x) / d.x : INFINITY;
        double tYp = (d.y >  1e-9) ? ((t.width - r) - p.y) / d.y : INFINITY;
        double tYn = (d.y < -1e-9) ? ((r) - p.y) / d.y : INFINITY;

        double tBest = tXp; int axis = 0;   // 0 = 撞 x 向库壁
        if (tXn < tBest) { tBest = tXn; axis = 0; }
        if (tYp < tBest) { tBest = tYp; axis = 1; }
        if (tYn < tBest) { tBest = tYn; axis = 1; }

        if (!isfinite(tBest) || tBest > remain) {
            p = baAdd(p, baMul(d, remain));
            if (n < maxPts) out[n++] = p;
            return n;
        }
        p = baAdd(p, baMul(d, tBest));
        remain -= tBest;
        if (n < maxPts) out[n++] = p;
        if (axis == 0) d.x = -d.x; else d.y = -d.y;
        // 库边损耗：剩余可走距离按 e^2 折减（能量 ∝ 距离）
        remain *= t.cushionRest * t.cushionRest;
    }
    return n;
}

BAVec2 baStopPoint(BATable t, BAVec2 start, BAVec2 dir, double distance) {
    BAVec2 pts[24];
    int n = baTrace(t, start, dir, distance, pts, 24);
    return n > 0 ? pts[n - 1] : start;
}

BAResult baSolveShot(BATable t, BAVec2 cue, BAVec2 target, BAVec2 pocket, double power) {
    BAResult o;
    memset(&o, 0, sizeof(o));

    BAVec2 toPocket = baSub(pocket, target);
    double dTP = baLen(toPocket);
    if (dTP < 1e-6) return o;
    BAVec2 pocketDir = baMul(toPocket, 1.0 / dTP);

    // 假想球：目标球往后沿「球→袋」反方向退一个球径
    BAVec2 ghost = baSub(target, baMul(pocketDir, 2.0 * t.ballRadius));
    o.ghost = ghost;

    BAVec2 cueToGhost = baSub(ghost, cue);
    double d1 = baLen(cueToGhost);
    o.approachDist = d1;
    o.pocketDist = dTP;
    if (d1 < 1e-6) return o;

    BAVec2 aimDir = baMul(cueToGhost, 1.0 / d1);
    double cosT = baClamp(baDot(aimDir, pocketDir), -1.0, 1.0);
    double cut = acos(cosT);
    o.cutAngleDeg = cut * 180.0 / M_PI;

    // 切角 >= 85° 视为打不进（传递能量几乎为 0）
    if (cut >= 85.0 * M_PI / 180.0) return o;
    o.valid = true;

    power = baClamp(power, 0.0, 1.0);
    double v0 = power * t.maxSpeed;
    double v1sq = v0 * v0 - 2.0 * t.rollDecel * d1;
    if (v1sq <= 0.0) {
        o.cueReaches = false;
        o.contactSpeed = 0;
        o.cueStop = cue;
        return o;
    }
    o.cueReaches = true;
    double v1 = sqrt(v1sq);
    o.contactSpeed = v1;

    // 目标球：沿球心连线（= pocketDir）分速度
    double vObj = v1 * cosT;
    o.objectSpeed = vObj;
    o.objectTravel = (vObj * vObj) / (2.0 * t.rollDecel);
    // 目标球需要走的距离是「球心到袋口」减去半个袋口余量
    o.potOk = (o.objectTravel >= (dTP - t.pocketRadius * 0.55));

    // 母球：走切线方向，速度 v1*sin(cut)
    BAVec2 tangent = baPerp(pocketDir);
    if (baDot(tangent, aimDir) < 0) tangent = baMul(tangent, -1.0);
    double vCue = v1 * sin(cut);
    o.cueSpeedAfter = vCue;
    o.cueTravel = (vCue * vCue) / (2.0 * t.rollDecel);
    o.cueStop = baStopPoint(t, ghost, tangent, o.cueTravel);

    return o;
}

BAVec2 baBankPocketFromCushion(BATable t, BAVec2 target, BAVec2 pocket, int side) {
    // side: 0=上库(y=0) 1=下库(y=width) 2=左库(x=0) 3=右库(x=length)
    BAVec2 m = pocket;
    switch (side) {
        case 0: m.y = -pocket.y; break;
        case 1: m.y = 2.0 * t.width - pocket.y; break;
        case 2: m.x = -pocket.x; break;
        case 3: m.x = 2.0 * t.length - pocket.x; break;
        default: break;
    }
    (void)target;
    return m;
}

BABestShot baBestShot(BATable t, BAVec2 cue, const BAVec2 *balls, const bool *alive,
                      int count, double power) {
    BABestShot best;
    memset(&best, 0, sizeof(best));
    best.ballIndex = -1;
    best.pocketIndex = -1;

    BAVec2 pockets[6];
    int np = baPockets(t, pockets, 6);

    double bestScore = 1e9;
    for (int i = 0; i < count; i++) {
        if (alive && !alive[i]) continue;
        if (baLen(baSub(balls[i], cue)) < 1e-4) continue;   // 跳过母球自己
        for (int p = 0; p < np; p++) {
            BAResult r = baSolveShot(t, cue, balls[i], pockets[p], power);
            if (!r.valid || !r.cueReaches) continue;
            // 评分：切角越小越好 + 距离越短越好；进不了的球给惩罚而不是直接丢，
            // 这样力度不够时也能提示「这一杆需要更大力」
            double score = r.cutAngleDeg * 1.4 + r.approachDist * 12.0 + r.pocketDist * 6.0;
            if (!r.potOk) score += 260.0;
            if (score < bestScore) {
                bestScore = score;
                best.valid = true;
                best.ballIndex = i;
                best.pocketIndex = p;
                best.result = r;
            }
        }
    }
    return best;
}

int baPowerLadder(BATable t, BAVec2 cue, BAVec2 target, BAVec2 pocket, BAPowerRow *out, int maxRows) {
    double steps[BA_POWER_STEPS] = { 0.20, 0.40, 0.60, 0.80, 1.00 };
    int n = 0;
    for (int i = 0; i < BA_POWER_STEPS && n < maxRows; i++) {
        BAResult r = baSolveShot(t, cue, target, pocket, steps[i]);
        out[n].power       = steps[i];
        out[n].potOk       = r.potOk;
        out[n].cueReaches  = r.cueReaches;
        out[n].cueStop     = r.cueStop;
        out[n].cueTravel   = r.cueTravel;
        n++;
    }
    return n;
}
