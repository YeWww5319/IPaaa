//
//  BAAntiDetect.mm
//

#import "BAAntiDetect.h"
#import "BAFishhook.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <stdio.h>
#import <stdlib.h>
#import <stdarg.h>
#import <string.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// 需要隐藏的痕迹（命中任一子串就当不存在）
static const char *kHiddenPaths[] = {
    "/var/jb",
    "/Applications/Cydia.app",
    "/Applications/Sileo.app",
    "/Applications/Zebra.app",
    "/Library/MobileSubstrate",
    "/Library/PreferenceBundles",
    "/usr/sbin/sshd",
    "/usr/bin/ssh",
    "/bin/bash",
    "/bin/sh",
    "/etc/apt",
    "/private/preboot",
    "/usr/lib/libhooker",
    "/usr/lib/libsubstrate",
    "/usr/lib/libellekit",
    "frida",
    "Frida",
    "cycript",
    "Substrate",
    "substrate",
    "BilliardsAim",          // 自己的 dylib
    "Cephei",
    "shepherd",
};

static bool ba_hidden(const char *path) {
    if (!path) return false;
    size_t n = sizeof(kHiddenPaths) / sizeof(kHiddenPaths[0]);
    for (size_t i = 0; i < n; i++) {
        if (strstr(path, kHiddenPaths[i]) != NULL) return true;
    }
    return false;
}

static bool ba_hidden_ns(NSString *path) {
    if (!path.length) return false;
    const char *p = path.UTF8String;
    return ba_hidden(p);
}

#pragma mark - C 层挂钩

static int (*orig_stat)(const char *, struct stat *);
static int (*orig_lstat)(const char *, struct stat *);
static int (*orig_access)(const char *, int);
static int (*orig_open)(const char *, int, ...);
static FILE *(*orig_fopen)(const char *, const char *);
static char *(*orig_getenv)(const char *);
static const char *(*orig_dyld_get_image_name)(uint32_t);

static int ba_stat(const char *path, struct stat *buf) {
    if (ba_hidden(path)) return -1;
    if (!orig_stat) return -1;
    return orig_stat(path, buf);
}

static int ba_lstat(const char *path, struct stat *buf) {
    if (ba_hidden(path)) return -1;
    if (!orig_lstat) return -1;
    return orig_lstat(path, buf);
}

static int ba_access(const char *path, int mode) {
    if (ba_hidden(path)) return -1;
    if (!orig_access) return -1;
    return orig_access(path, mode);
}

static int ba_open(const char *path, int oflag, ...) {
    if (ba_hidden(path)) return -1;
    if (!orig_open) return -1;
    if (oflag & O_CREAT) {
        va_list ap; va_start(ap, oflag);
        int mode = va_arg(ap, int);
        va_end(ap);
        return orig_open(path, oflag, mode);
    }
    return orig_open(path, oflag);
}

static FILE *ba_fopen(const char *path, const char *mode) {
    if (ba_hidden(path)) return NULL;
    if (!orig_fopen) return NULL;
    return orig_fopen(path, mode);
}

static char *ba_getenv(const char *name) {
    if (!name) return NULL;
    if (strcmp(name, "DYLD_INSERT_LIBRARIES") == 0) return NULL;
    if (strcmp(name, "_MSSafeMode") == 0) return NULL;
    if (strcmp(name, "_MSSuppressLogging") == 0) return NULL;
    if (strcmp(name, "DYLD_FRAMEWORK_PATH") == 0) return NULL;
    if (!orig_getenv) return NULL;
    return orig_getenv(name);
}

static const char *ba_image_name(uint32_t index) {
    if (!orig_dyld_get_image_name) return NULL;
    const char *p = orig_dyld_get_image_name(index);
    if (ba_hidden(p)) return "/usr/lib/libSystem.B.dylib";
    return p;
}

#pragma mark - ObjC 层挂钩

@implementation NSFileManager (BAAntiDetect)

- (BOOL)ba_fileExistsAtPath:(NSString *)path {
    if (ba_hidden_ns(path)) return NO;
    return [self ba_fileExistsAtPath:path];
}

- (BOOL)ba_isReadableFileAtPath:(NSString *)path {
    if (ba_hidden_ns(path)) return NO;
    return [self ba_isReadableFileAtPath:path];
}

- (NSDictionary *)ba_attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    if (ba_hidden_ns(path)) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:nil];
        return nil;
    }
    return [self ba_attributesOfItemAtPath:path error:error];
}

- (NSArray *)ba_contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSArray *arr = [self ba_contentsOfDirectoryAtPath:path error:error];
    if (!arr) return arr;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *item in arr) {
        NSString *full = [path stringByAppendingPathComponent:item];
        if (!ba_hidden_ns(full)) [out addObject:item];
    }
    return out;
}

@end

@implementation UIApplication (BAAntiDetect)

- (BOOL)ba_canOpenURL:(NSURL *)url {
    NSString *s = url.absoluteString;
    if ([s containsString:@"cydia"] || [s containsString:@"sileo"] ||
        [s containsString:@"zbra"] || [s containsString:@"filza"] ||
        [s containsString:@"undecimus"]) {
        return NO;
    }
    return [self ba_canOpenURL:url];
}

@end

#pragma mark -

@implementation BAAntiDetect

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 1) C 层符号
        ba_rebinding rebs[] = {
            { "stat",            (void *)ba_stat,            (void **)&orig_stat },
            { "stat$INODE64",    (void *)ba_stat,            (void **)&orig_stat },
            { "lstat",           (void *)ba_lstat,           (void **)&orig_lstat },
            { "lstat$INODE64",   (void *)ba_lstat,           (void **)&orig_lstat },
            { "access",          (void *)ba_access,          (void **)&orig_access },
            { "open",            (void *)ba_open,            (void **)&orig_open },
            { "fopen",           (void *)ba_fopen,           (void **)&orig_fopen },
            { "getenv",          (void *)ba_getenv,          (void **)&orig_getenv },
            { "_dyld_get_image_name", (void *)ba_image_name, (void **)&orig_dyld_get_image_name },
        };
        ba_rebind_symbols(rebs, sizeof(rebs) / sizeof(rebs[0]));

        // 2) ObjC 层（NSFileManager 可能返回内部子类，两个类都挂，但只挂「自己实现了该 selector」的类，避免重复交换回去）
        void (^swapIfOwn)(Class, SEL, SEL) = ^(Class cls, SEL a, SEL b) {
            unsigned int n = 0;
            Method *ms = class_copyMethodList(cls, &n);
            bool hasA = false, hasB = false;
            for (unsigned int i = 0; i < n; i++) {
                SEL s = method_getName(ms[i]);
                if (s == a) hasA = true;
                if (s == b) hasB = true;
            }
            free(ms);
            if (!(hasA && hasB)) return;
            method_exchangeImplementations(class_getInstanceMethod(cls, a),
                                           class_getInstanceMethod(cls, b));
        };

        void (^hookFM)(Class) = ^(Class fm) {
            if (!fm) return;
            swapIfOwn(fm, @selector(fileExistsAtPath:), @selector(ba_fileExistsAtPath:));
            swapIfOwn(fm, @selector(isReadableFileAtPath:), @selector(ba_isReadableFileAtPath:));
            swapIfOwn(fm, @selector(attributesOfItemAtPath:error:), @selector(ba_attributesOfItemAtPath:error:));
            swapIfOwn(fm, @selector(contentsOfDirectoryAtPath:error:), @selector(ba_contentsOfDirectoryAtPath:error:));
        };

        Class fmClass = objc_getClass("NSFileManager");
        hookFM(fmClass);
        Class fmReal = object_getClass([NSFileManager defaultManager]);
        if (fmReal && fmReal != fmClass) {
            // 只有「这个子类自己实现了这些方法」时才挂，否则会跟父类交换两次又换回去
            hookFM(fmReal);
        }

        Class app = objc_getClass("UIApplication");
        if (app) {
            Method m1 = class_getInstanceMethod(app, @selector(canOpenURL:));
            Method m2 = class_getInstanceMethod(app, @selector(ba_canOpenURL:));
            if (m1 && m2) method_exchangeImplementations(m1, m2);
        }
    });
}

@end
