.syntax unified
.thumb
.fpu fpv5-sp-d16
.macro command name,op
.section .text.\name,"ax",%progbits
.global \name
.type \name,%function
.thumb_func
\name:
    push {r4,lr}
    mov r1,lr
    movs r0,#\op
    bl ce_serial_foreign
    pop {r4,pc}
.size \name,.-\name
.endm
command ce_serial_start_entry,1
command ce_serial_stop_entry,2
.macro body name,literal,resume
.section .text.\name,"ax",%progbits
.global \name
.type \name,%function
.thumb_func
\name:
    push {r4,r5,r7,lr}
    ldr r2,=\literal
    b.w \resume
.size \name,.-\name
.endm
body ce_stock_head_start_body,0x181ca732,ce_stock_head_start_resume
body ce_stock_head_stop_body,0x181ca70d,ce_stock_head_stop_resume
.macro save
    push.w {r0-r3,r12,lr}
    mrs r3,apsr
    vmrs r12,fpscr
    push.w {r3,r12}
    vpush {s0-s15}
.endm
.macro restore
    vpop {s0-s15}
    pop.w {r3,r12}
    vmsr fpscr,r12
    msr APSR_nzcvqg,r3
    pop.w {r0-r3,r12,lr}
.endm
.section .text.ce_serial_publish_entry,"ax",%progbits
.global ce_serial_publish_entry
.type ce_serial_publish_entry,%function
.thumb_func
ce_serial_publish_entry:
    save
    mov r0,r4
    mov r1,r6
    bl ce_serial_publish
    str r0,[sp,#72]
    restore
    bx lr
.size ce_serial_publish_entry,.-ce_serial_publish_entry
.section .text.ce_serial_retire_entry,"ax",%progbits
.global ce_serial_retire_entry
.type ce_serial_retire_entry,%function
.thumb_func
ce_serial_retire_entry:
    save
    mov r0,r4
    bl ce_serial_retire
    str r0,[sp,#72]
    restore
    bx lr
.size ce_serial_retire_entry,.-ce_serial_retire_entry
.section .text.ce_serial_destroy_entry,"ax",%progbits
.global ce_serial_destroy_entry
.type ce_serial_destroy_entry,%function
.thumb_func
ce_serial_destroy_entry:
    save
    bl ce_serial_before_destroy
    restore
    push {r3,r4,r7,lr}
    ldr r3,=0x181e6e8c
    b.w ce_stock_sys_destroy_resume
.size ce_serial_destroy_entry,.-ce_serial_destroy_entry
