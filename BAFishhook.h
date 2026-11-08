//
//  BAFishhook.h — 极简符号重绑定（给 C 函数挂钩子用）
//

#ifndef BAFISHHOOK_H
#define BAFISHHOOK_H

#include <stddef.h>

typedef struct {
    const char *name;      // 符号名，如 "stat"
    void       *replacement;
    void      **replaced;  // 原函数指针回填
} ba_rebinding;

int ba_rebind_symbols(ba_rebinding rebindings[], size_t count);

#endif
