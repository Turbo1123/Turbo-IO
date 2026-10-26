/* Pinned Strix 1.0.4.12 notifyHeadGestureOnUi entry trampoline.
 * Candidate builder must verify stock bytes at 0x106dd16c before a B.W patch.
 * Observe only: observer MUST NOT allocate, alter LVGL, dispatch an answer,
 * start/stop detection, or consume the original notification here. Capture a
 * bounded event with a generation, then let a later UI tick process it.
 * Not installed in any firmware by the context-English test runner.
 */
.syntax unified
.thumb
.fpu fpv5-sp-d16
.macro observer_save
    push.w {r0-r3,r12,lr}
    mrs r3,apsr
    vmrs r12,fpscr
    push.w {r3,r12}
    vpush {s0-s15}
.endm
.macro observer_restore
    vpop {s0-s15}
    pop.w {r3,r12}
    vmsr fpscr,r12
    msr APSR_nzcvqg,r3
    pop.w {r0-r3,r12,lr}
.endm
.section .text.ce_head_notify_entry,"ax",%progbits
.global ce_head_notify_entry
.type ce_head_notify_entry,%function
.thumb_func
ce_head_notify_entry:
    observer_save
    bl ce_native_head_observe
    observer_restore
    /* Exactly replay the one displaced instruction. Remaining stock code
     * still owns the original register frame and its matching epilogue. */
    push.w {r4,r5,r6,r7,r8,r9,lr}
    b.w ce_stock_head_notify_resume
.size ce_head_notify_entry,.-ce_head_notify_entry

/* Low-level start/stop also have a direct debug-command caller. Observe these
 * entries, not just LauncherAPI wrappers. This callback may be on another
 * thread: only bounded critical-section invalidation / counters, NEVER a walk
 * of LVGL timers, display mutation, allocation, logging or a blocking mutex.
 * An installed native service must provide that thread-safe binding first.
 */
.macro command_entry name,op,literal,resume
.section .text.\name,"ax",%progbits
.global \name
.type \name,%function
.thumb_func
\name:
    observer_save
    movs r0,#\op
    mov r1,lr
    bl ce_native_head_command
    observer_restore
    push {r4,r5,r7,lr}
    ldr r2,=\literal
    b.w \resume
.size \name,.-\name
.endm
command_entry ce_head_start_entry,1,0x181b5ce4,ce_stock_head_start_resume
command_entry ce_head_stop_entry,2,0x181b5cbf,ce_stock_head_stop_resume
