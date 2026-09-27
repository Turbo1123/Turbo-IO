/* ARM EABI helpers; exact argument shuffles, no writable global storage. */
.syntax unified
.thumb
.section .text.tap_abi,"ax",%progbits
.balign 2
.global __aeabi_memcpy
.global __aeabi_memcpy4
.global __aeabi_memcpy8
.type __aeabi_memcpy,%function
.type __aeabi_memcpy4,%function
.type __aeabi_memcpy8,%function
.thumb_func
__aeabi_memcpy:
.thumb_func
__aeabi_memcpy4:
.thumb_func
__aeabi_memcpy8:
 b.w memcpy
.size __aeabi_memcpy,.-__aeabi_memcpy
.size __aeabi_memcpy4,.-__aeabi_memcpy4
.size __aeabi_memcpy8,.-__aeabi_memcpy8
.global __aeabi_memclr4
.type __aeabi_memclr4,%function
.thumb_func
__aeabi_memclr4:
 mov r2,r1
 movs r1,#0
 b.w memset
.size __aeabi_memclr4,.-__aeabi_memclr4
