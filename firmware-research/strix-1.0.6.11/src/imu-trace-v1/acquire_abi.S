.syntax unified
.thumb
.fpu fpv5-sp-d16
.macro body name,literal,resume
.section .text.\name,"ax",%progbits
.global \name
.type \name,%function
.thumb_func
\name:
 push {r4,r5,r7,lr}
 ldr r0,=\literal
 ldr.w pc,1f
 .balign 4
1: .word \resume
.size \name,.-\name
.endm
/* Literal values are checked against the sealed stock image in build.py. */
body ti_stock_start,0x198266d4,0x10663bf5
body ti_stock_stop,0x1982669c,0x10663c61
