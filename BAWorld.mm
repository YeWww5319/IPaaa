//
//  BAWorld.mm
//

#import "BAWorld.h"
#import "BAConfig.h"
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <string.h>
#include <math.h>

static BABallSet gLast;
static bool gHasLast = false;

@implementation BAWorld {
    unsigned long long _autoAddr;
    bool _scanned;
    bool _scanning;
}

+ (instancetype)shared {
    static BAWorld *w;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ w = [[BAWorld alloc] init]; });
    return w;
}

- (void)start {
    _autoAddr = 0;
    _scanned = NO;
}

- (void)setManualAddress:(unsigned long long)addr {
    _autoAddr = addr;
    _scanned = YES;
}

#pragma mark - 模块基址

- (unsigned long long)moduleBase {
    BAConfig *cfg = [BAConfig shared];
    uint32_t n = _dyld_image_count();
    unsigned long long fallback = 0;
    for (uint32_t i = 0; i < n; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *path = @(name);
        NSString *file = path.lastPathComponent;
        unsigned long long base = (unsigned long long)_dyld_get_image_header(i);
        if (cfg.moduleName.length && [file isEqualToString:cfg.moduleName]) return base;
        if (i == 0) fallback = base;
        if (!cfg.moduleName.length && path.length && ![path containsString:@"/usr/lib/"] &&
            ![path containsString:@"/System/"] && ![path containsString:@".dylib"]) {
            fallback = base;
        }
    }
    return fallback;
}

#pragma mark - 内存只读

static bool baReadMem(unsigned long long addr, void *buf, size_t len) {
    if (!addr) return false;
    vm_size_t out = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
                                              (mach_vm_address_t)addr,
                                              (mach_vm_size_t)len,
                                              (mach_vm_address_t)buf,
                                              &out);
    return kr == KERN_SUCCESS && out == len;
}

static double baReadValue(const unsigned char *p, int type) {
    if (type == 1) { double d; memcpy(&d, p, sizeof(double)); return d; }
    if (type == 2) { int32_t v; memcpy(&v, p, sizeof(int32_t)); return (double)v / 1000.0; }
    float f; memcpy(&f, p, sizeof(float)); return (double)f;
}

// 把游戏内部坐标统一换算到「米」
static double baNormalizeLength(double v, double tableLen) {
    double a = fabs(v);
    if (a < 1e-9) return v;
    if (a <= 1.5)          return v * tableLen;          // 归一化 0~1
    if (a <= 6.0)          return v * (tableLen / 2.54) * 1.0; // 近似「台长倍数」
    if (a <= 100.0)        return v / 100.0 * (tableLen / 2.54); // 可能 0~254 单位 = 厘米
    if (a <= 6000.0)       return v / 1000.0;            // 毫米
    return v;
}

#pragma mark - 自动扫描候选（粗略，用于 offset 没填时的兜底）

- (unsigned long long)scanCandidate {
    BAConfig *cfg = [BAConfig shared];
    unsigned long long base = [self moduleBase];
    if (!base) return 0;

    const struct mach_header_64 *hdr = (const struct mach_header_64 *)base;
    if (hdr->magic != MH_MAGIC_64) return 0;

    const uint8_t *p = (const uint8_t *)(hdr + 1);
    unsigned long long dataStart = base, dataEnd = 0;
    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            NSString *sn = @(seg->segname);
            if ([sn isEqualToString:@"__DATA"] || [sn containsString:@"__DATA"]) {
                unsigned long long s = base + (seg->vmaddr - 0x100000000ULL);
                if (!dataEnd || s < dataStart) dataStart = s;
                unsigned long long e = s + seg->vmsize;
                if (e > dataEnd) dataEnd = e;
            }
        }
        p += lc->cmdsize;
    }
    if (!dataEnd || dataEnd <= dataStart) return 0;

    // 限制扫描窗口，避免卡顿
    unsigned long long window = 8ULL * 1024 * 1024;
    unsigned long long end = dataStart + window < dataEnd ? dataStart + window : dataEnd;
    int stride = cfg.ballStride > 0 ? cfg.ballStride : 24;
    if (stride < 8 || stride > 128) stride = 24;
    int need = cfg.ballCount > 2 ? cfg.ballCount : 16;

    const size_t chunk = 256 * 1024;
    unsigned char buf[chunk];
    for (unsigned long long a = dataStart; a + chunk < end; a += chunk) {
        if (!baReadMem(a, buf, chunk)) continue;
        for (size_t off = 0; off + (size_t)stride * need + 16 < chunk; off += 4) {
            int good = 0;
            BAVec2 pts[32];
            for (int i = 0; i < need; i++) {
                const unsigned char *bp = buf + off + (size_t)i * stride;
                double x = baReadValue(bp + cfg.ballXOffset, cfg.ballValueType);
                double y = baReadValue(bp + cfg.ballYOffset, cfg.ballValueType);
                if (!isfinite(x) || !isfinite(y)) break;
                if (fabs(x) > 3000 || fabs(y) > 3000) break;
                pts[i] = BAV2(x, y);
                good++;
            }
            if (good < need) continue;
            // 合法性：所有点分布在一个矩形内，且互不重合太多
            double minx = 1e9, maxx = -1e9, miny = 1e9, maxy = -1e9;
            for (int i = 0; i < need; i++) {
                if (pts[i].x < minx) minx = pts[i].x;
                if (pts[i].x > maxx) maxx = pts[i].x;
                if (pts[i].y < miny) miny = pts[i].y;
                if (pts[i].y > maxy) maxy = pts[i].y;
            }
            double w = maxx - minx, h = maxy - miny;
            if (w < 1e-6 || h < 1e-6) continue;
            double ratio = w / h;
            if (ratio < 1.2 || ratio > 3.2) continue;   // 球桌长宽比 2:1 附近
            return a + off;
        }
    }
    return 0;
}

#pragma mark - 取一帧

- (BABallSet)snapshot {
    BAConfig *cfg = [BAConfig shared];
    BATable t = baDefaultTable();
    t.length      = cfg.tableLength;
    t.width       = cfg.tableWidth;
    t.ballRadius  = cfg.ballRadius;
    t.rollDecel   = cfg.rollDecel;
    t.cushionRest = cfg.cushionRest;
    t.maxSpeed    = cfg.maxSpeed;
    t.pocketRadius= cfg.pocketRadius;

    BABallSet set;
    memset(&set, 0, sizeof(set));
    set.cueIndex = -1;

    unsigned long long addr = 0;
    if (_autoAddr) {
        addr = _autoAddr;
    } else if (cfg.ballArrayOffset) {
        addr = [self moduleBase] + cfg.ballArrayOffset;
    } else {
        // 没配 offset：后台扫一次，扫到之前先不画，避免卡主线程
        if (!_scanned && !_scanning) {
            _scanning = YES;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                unsigned long long found = [self scanCandidate];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->_scanning = NO;
                    self->_scanned = YES;
                    if (found) {
                        self->_autoAddr = found;
                        NSLog(@"[BilliardsAim] 自动定位到球数组 addr=0x%llx", found);
                    }
                });
            });
        }
        return set;
    }
    if (!addr) return set;

    int n = cfg.ballCount > 0 ? cfg.ballCount : 16;
    if (n > 32) n = 32;
    int stride = cfg.ballStride > 0 ? cfg.ballStride : 24;

    unsigned char buf[32 * 128];
    size_t need = (size_t)stride * n;
    if (need > sizeof(buf)) return set;

    if (!baReadMem(addr, buf, need)) return set;

    for (int i = 0; i < n; i++) {
        const unsigned char *bp = buf + (size_t)i * stride;
        double x = baReadValue(bp + cfg.ballXOffset, cfg.ballValueType);
        double y = baReadValue(bp + cfg.ballYOffset, cfg.ballValueType);
        if (!isfinite(x) || !isfinite(y)) return set;
        set.pts[i] = BAV2(baNormalizeLength(x, t.length), baNormalizeLength(y, t.width));
    }
    set.count = n;
    set.ok = true;

    // 母球：通常是数组第 0 颗；如果不像就按「离中心最近的孤立球」兜底
    set.cueIndex = 0;

    // 静止判定
    set.stable = true;
    if (gHasLast && gLast.count == set.count) {
        for (int i = 0; i < n; i++) {
            double d = baLen(baSub(set.pts[i], gLast.pts[i]));
            if (d > 0.002) { set.stable = false; break; }
        }
    } else {
        set.stable = false;
    }

    gLast = set;
    gHasLast = true;
    return set;
}

@end
