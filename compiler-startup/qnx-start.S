/* SPDX-License-Identifier: Apache-2.0
 *
 * Process entry for QNX Neutrino 6.5 on ARM (EABI). An original startup
 * object, written from the entry contract of the platform:
 *
 *   The program loader enters _start with a loader value in r0, argc at
 *   [sp], argv at sp+4, envp after the NULL that ends argv, and the
 *   auxiliary vector after the NULL that ends envp.
 *
 *   _start calls, in this order:
 *     _init_libc(argc, argv, envp, auxv, loader_value)
 *     _preinit_array(__preinit_array_start, __preinit_array_end)
 *     atexit(_fini)
 *     _fini_array(__fini_array_start, __fini_array_end)
 *     _init()
 *     _init_array(__init_array_start, __init_array_end)
 *     errno = 0
 *     exit(main(argc, argv, envp))
 *
 * Every callee except _init, _fini and main is an export of libc.so.3.
 * The array bounds are provided by the linker script. This object also
 * defines _init and _fini (empty: the image links no .init/.fini
 * fragments) and __dso_handle for __cxa_atexit users.
 */
    .syntax unified
    .arch armv7-a
    .eabi_attribute 25, 1   /* Tag_ABI_align_preserved: 8-byte stack */

    .text
    .align 2
    .globl _start
    .type _start, %function
_start:
    mov     r4, r0                  /* the loader value */
    ldr     r0, [sp]                /* argc */
    add     r1, sp, #4              /* argv */
    add     r2, r1, r0, lsl #2
    add     r2, r2, #4              /* envp: after argv's NULL */
    mov     r3, r2
1:  ldr     ip, [r3], #4            /* find envp's NULL */
    teq     ip, #0
    bne     1b                      /* r3: auxv */
    push    {r4}                    /* fifth argument on the stack */
    mov     r4, r0
    mov     r5, r1
    mov     r6, r2
    bl      _init_libc
    add     sp, sp, #4
    ldr     r0, =__preinit_array_start
    ldr     r1, =__preinit_array_end
    bl      _preinit_array
    ldr     r0, =_fini
    bl      atexit
    ldr     r0, =__fini_array_start
    ldr     r1, =__fini_array_end
    bl      _fini_array
    bl      _init
    ldr     r0, =__init_array_start
    ldr     r1, =__init_array_end
    bl      _init_array
    ldr     r0, =errno
    mov     r1, #0
    str     r1, [r0]
    mov     r0, r4
    mov     r1, r5
    mov     r2, r6
    bl      main
    bl      exit
2:  b       2b
    .pool
    .size _start, .-_start

    .globl _init
    .type _init, %function
_init:
    bx      lr
    .size _init, .-_init

    .globl _fini
    .type _fini, %function
_fini:
    bx      lr
    .size _fini, .-_fini

    .data
    .align 2
    .hidden __dso_handle
    .globl __dso_handle
    .type __dso_handle, %object
__dso_handle:
    .word 0
    .size __dso_handle, 4

    .section .note.GNU-stack,"",%progbits
