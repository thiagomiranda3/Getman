// Real bridge allocator contract: alignment, ownership, realloc and quota limits.
// Define GETMAN_TEST_MSVC_ALIGNMENT on a non-Windows host to compile the MSVC
// header layout without max_align_t; actual MSVC builds use their SDK constants.
#include "quickjs.h"
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stddef.h>
#include <time.h>

#if defined(GETMAN_TEST_MSVC_ALIGNMENT) && !defined(_MSC_VER)
#define _MSC_VER 1930
#define MEMORY_ALLOCATION_ALIGNMENT 16
#define max_align_t unavailable_in_msvc_c_mode
#endif

// Include the real allocator's static functions without adding a product API.
#include "bridge.c"

static void assert_aligned(void *pointer) {
    assert(pointer != NULL);
#ifdef _MSC_VER
    assert((uintptr_t)pointer % MEMORY_ALLOCATION_ALIGNMENT == 0);
#else
    assert((uintptr_t)pointer % _Alignof(max_align_t) == 0);
#endif
}

int main(void) {
    Control control = {0};
    control.limit = 4096;
    for (size_t size = 1; size <= 128; ++size) {
        unsigned char *pointer = quota_malloc(&control, size);
        assert_aligned(pointer);
        assert(quota_size(pointer) == size);
        memset(pointer, 0x5a, size);

        unsigned char *grown = quota_realloc(&control, pointer, size + 17);
        assert_aligned(grown);
        assert(quota_size(grown) == size + 17);
        for (size_t index = 0; index < size; ++index) {
            assert(grown[index] == 0x5a);
        }
        quota_free(&control, grown);
        assert(control.used == 0);
    }

    unsigned char *zeroed = quota_calloc(&control, 7, 9);
    assert_aligned(zeroed);
    for (size_t index = 0; index < 63; ++index) assert(zeroed[index] == 0);
    size_t charged = control.used;
    assert(charged > 63);  // The allocation header is part of the quota.
    control.limit = charged;
    assert(quota_malloc(&control, 1) == NULL);
    assert(control.memory_exceeded == 1);
    assert(control.used == charged);
    assert(quota_realloc(&control, zeroed, 64) == NULL);
    assert(quota_size(zeroed) == 63);  // Failed realloc retains the old buffer.
    quota_free(&control, zeroed);
    assert(control.used == 0);
    assert(quota_malloc(&control, SIZE_MAX) == NULL);
    assert(control.used == 0);
    quota_free(&control, NULL);
    return 0;
}
