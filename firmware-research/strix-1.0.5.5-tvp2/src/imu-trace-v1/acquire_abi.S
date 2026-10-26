.syntax unified
.thumb
.fpu fpv5-sp-d16
.section .text.ti_rpmsg_entry,"ax",%progbits
.global ti_rpmsg_entry
.type ti_rpmsg_entry,%function
.thumb_func
ti_rpmsg_entry:
 push.w {r0-r3,r12,lr}
 mrs r3,apsr
 vmrs r12,fpscr
 push.w {r3,r12}
 vpush {s0-s15}
 bl ti_rpmsg_observe
 vpop {s0-s15}
 pop.w {r3,r12}
 vmsr fpscr,r12
 msr APSR_nzcvqg,r3
 pop.w {r0-r3,r12,lr}
 push {r4,r5,r7,lr}
 sub sp,#0x40
 ldr.w pc,1f
 .balign 4
1: .word 0x104e7e81
.size ti_rpmsg_entry,.-ti_rpmsg_entry
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
body ti_stock_start,0x196988bc,0x104e8ee1
body ti_stock_stop,0x19698884,0x104e8f4d
