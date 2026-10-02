/* SPDX-License-Identifier: Apache-2.0 */
/* This header declares only the function used by variadic logging glue. */
#ifndef QNX_COMPILER_MINIMAL_STDIO_H
#define QNX_COMPILER_MINIMAL_STDIO_H
#include <stddef.h>
#include <stdarg.h>
#ifdef __cplusplus
extern "C" {
#endif
int vsnprintf(char *buffer, size_t size, const char *format, va_list args);
#ifdef __cplusplus
}
#endif
#endif
