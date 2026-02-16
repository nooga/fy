#include <stddef.h>
#include <stdint.h>

#if defined(__APPLE__)
#define EXPORT __attribute__((visibility("default")))
#else
#define EXPORT
#endif

EXPORT size_t my_strlen(const char *s) {
    if (!s) return 0;
    size_t n = 0;
    while (s[n] != '\0') n++;
    return n;
}

EXPORT int my_abs(int x) {
    return x < 0 ? -x : x;
}

EXPORT int64_t my_inc64(int64_t x) {
    return x + 1;
}

