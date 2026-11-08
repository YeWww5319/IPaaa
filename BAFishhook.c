//
//  BAFishhook.c — 精简版 fishhook（Mach-O 间接符号表重绑定）
//  arm64 / arm64e 通用，不依赖 Substrate / ElleKit。
//

#include "BAFishhook.h"
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>

#define BA_MAX_REBIND 64

static ba_rebinding g_rebs[BA_MAX_REBIND];
static size_t g_reb_count = 0;

static void ba_scan_image(const struct mach_header *header, intptr_t slide) {
    const struct mach_header_64 *mh = (const struct mach_header_64 *)header;
    if (!mh || mh->magic != MH_MAGIC_64) return;

    const uint8_t *base = (const uint8_t *)header;
    const struct segment_command_64 *linkedit = NULL;
    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;

    const struct load_command *lc = (const struct load_command *)(base + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strcmp(seg->segname, SEG_LINKEDIT) == 0) linkedit = seg;
        } else if (lc->cmd == LC_SYMTAB) {
            symtab = (const struct symtab_command *)lc;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysymtab = (const struct dysymtab_command *)lc;
        }
        lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
    }
    if (!linkedit || !symtab || !dysymtab) return;

    intptr_t linkedit_base = (intptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
    const struct nlist_64 *syments  = (const struct nlist_64 *)(linkedit_base + symtab->symoff);
    const char *strtab              = (const char *)(linkedit_base + symtab->stroff);
    const uint32_t *indirect        = (const uint32_t *)(linkedit_base + dysymtab->indirectsymoff);

    lc = (const struct load_command *)(base + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd != LC_SEGMENT_64) {
            lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
            continue;
        }
        const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
        const struct section_64 *sects = (const struct section_64 *)(seg + 1);

        for (uint32_t s = 0; s < seg->nsects; s++) {
            uint32_t type = sects[s].flags & SECTION_TYPE;
            if (type != S_LAZY_SYMBOL_POINTERS && type != S_NON_LAZY_SYMBOL_POINTERS) continue;

            void **slots = (void **)((intptr_t)slide + (intptr_t)sects[s].addr);
            uint32_t count = (uint32_t)(sects[s].size / sizeof(void *));
            uint32_t first = sects[s].reserved1;

            for (uint32_t j = 0; j < count; j++) {
                uint32_t idx = indirect[first + j];
                if (idx == INDIRECT_SYMBOL_LOCAL || idx == INDIRECT_SYMBOL_ABS) continue;
                const char *name = strtab + syments[idx].n_un.n_strx;
                if (name && name[0] == '_') name++;

                for (size_t r = 0; r < g_reb_count; r++) {
                    if (!g_rebs[r].name || !name) continue;
                    if (strcmp(name, g_rebs[r].name) != 0) continue;
                    if (slots[j] == g_rebs[r].replacement) continue;
                    if (g_rebs[r].replaced && *g_rebs[r].replaced == NULL) {
                        *g_rebs[r].replaced = slots[j];
                    }
                    slots[j] = g_rebs[r].replacement;
                }
            }
        }
        lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize);
    }
}

int ba_rebind_symbols(ba_rebinding rebindings[], size_t count) {
    if (!rebindings || count == 0) return 0;
    g_reb_count = 0;
    for (size_t i = 0; i < count && g_reb_count < BA_MAX_REBIND; i++) {
        g_rebs[g_reb_count++] = rebindings[i];
    }
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        ba_scan_image((const struct mach_header *)_dyld_get_image_header(i),
                      _dyld_get_image_vmaddr_slide(i));
    }
    return 0;
}
