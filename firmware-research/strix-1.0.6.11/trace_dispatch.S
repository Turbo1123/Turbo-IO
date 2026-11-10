.syntax unified
.thumb
.cpu cortex-m33
.fpu fpv5-sp-d16
.text
.global ti_raw_sample_entry
.type ti_raw_sample_entry,%function
.thumb_func
ti_raw_sample_entry:
    /* Entered ONLY in the verified 0x26 TBH arm. r4=packet; r3=payload size.
       The stock header and transport length checks have already succeeded.
       For other sizes leave all processing to stock. */
    push.w {r0-r3,r12,lr}
    mrs r0,apsr
    vmrs r1,fpscr
    push {r0,r1}
    cmp r3,#40
    bne 1f
    vpush {s0-s15}
    movs r0,#0           /* observer does not use endpoint */
    mov r1,r4
    movs r2,#48
    bl ti_rpmsg_observe
    vpop {s0-s15}
1:  pop {r0,r1}
    vmsr fpscr,r1
    msr APSR_nzcvqg,r0
    pop.w {r0-r3,r12,lr}
    /* Replay the two displaced loads, including the original subscriber. */
    ldr r2,=0x19826538
    ldr r2,[r2]
    b.w ti_raw_resume
.ltorg
