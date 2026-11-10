.syntax unified
.cpu cortex-m33
.thumb
.section .text.ce_extension_idle,"ax",%progbits
.global ce_extension_idle
.type ce_extension_idle,%function
.thumb_func
ce_extension_idle:
IDLE_105a2f34:
 push {r4, r7, lr}
IDLE_105a2f36:
 sub sp, #0x1c
IDLE_105a2f38:
 add r7, sp, #8
IDLE_105a2f3a:
 bl ce_ext_106e7b5c
IDLE_105a2f3e:
 mov r4, r0
IDLE_105a2f40:
 bl ce_ext_106e8458
IDLE_105a2f44:
 cbnz r0, IDLE_105a2f64
IDLE_105a2f46:
 mov r0, r4
IDLE_105a2f48:
 bl ce_ext_106e8460
IDLE_105a2f4c:
 cbnz r0, IDLE_105a2f70
IDLE_105a2f4e:
 bl ce_ext_106d3310
IDLE_105a2f52:
 mov r4, r0
IDLE_105a2f54:
 cbnz r0, IDLE_105a2f7a
IDLE_105a2f56:
 movs r0,#0
IDLE_105a2f5a:
 cbz r0, IDLE_105a2f98
IDLE_105a2f5c:
 movs r0, #0
IDLE_105a2f5e:
 adds r7, #0x14
IDLE_105a2f60:
 mov sp, r7
IDLE_105a2f62:
 pop {r4, r7, pc}
IDLE_105a2f64:
 bl ce_ext_106d4c48
IDLE_105a2f68:
 cmp r0, #0
IDLE_105a2f6a:
 beq IDLE_105a2f46
IDLE_105a2f6c:
 movs r0, #1
IDLE_105a2f6e:
 b IDLE_105a2f5e
IDLE_105a2f70:
 bl ce_ext_106d693c
IDLE_105a2f74:
 cmp r0, #0
IDLE_105a2f76:
 beq IDLE_105a2f4e
IDLE_105a2f78:
 b IDLE_105a2f6c
IDLE_105a2f7a:
 ldrb r3, [r0]
IDLE_105a2f7c:
 cmp r3, #0
IDLE_105a2f7e:
 beq IDLE_105a2f56
IDLE_105a2f80:
 ldr r1, =0x18052630
IDLE_105a2f82:
 bl ce_ext_10941968
IDLE_105a2f86:
 cmp r0, #0
IDLE_105a2f88:
 beq IDLE_105a2f56
IDLE_105a2f8a:
 mov r0, r4
IDLE_105a2f8c:
 ldr r1, =0x18052a44
IDLE_105a2f8e:
 bl ce_ext_10941968
IDLE_105a2f92:
 cmp r0, #0
IDLE_105a2f94:
 beq IDLE_105a2f56
IDLE_105a2f96:
 b IDLE_105a2f5c
IDLE_105a2f98:
 bl ce_ext_106d245c
IDLE_105a2f9c:
 mov r4, r0
IDLE_105a2f9e:
 cmp r0, #0
IDLE_105a2fa0:
 beq IDLE_105a2f6c
IDLE_105a2fa2:
 movs r2, #0x10
IDLE_105a2fa4:
 ldr r1, =0x18187b3e
IDLE_105a2fa6:
 adds r0, r7, #4
IDLE_105a2fa8:
 bl ce_ext_106b61f0
IDLE_105a2fac:
 mov r0, r4
IDLE_105a2fae:
 adds r1, r7, #4
IDLE_105a2fb0:
 bl ce_ext_106b60c4
IDLE_105a2fb4:
 mov r4, r0
IDLE_105a2fb6:
 adds r0, r7, #4
IDLE_105a2fb8:
 bl ce_ext_106b6028
IDLE_105a2fbc:
 cmp r4, #0
IDLE_105a2fbe:
 beq IDLE_105a2f6c
IDLE_105a2fc0:
 ldr r4, [r4, #0x14]
IDLE_105a2fc2:
 cbnz r4, IDLE_105a2fda
IDLE_105a2fc4:
 ldr r3, =0x18042b4a
IDLE_105a2fc6:
 mov r2, r4
IDLE_105a2fc8:
 str r3, [sp]
IDLE_105a2fca:
 mov r1, r4
IDLE_105a2fcc:
 mov r3, r4
IDLE_105a2fce:
 movs r0, #1
IDLE_105a2fd0:
 bl ce_ext_107d5cd8
IDLE_105a2fd4:
 eor r0, r4, #1
IDLE_105a2fd8:
 b IDLE_105a2f5e
IDLE_105a2fda:
 ldrb r4, [r4, #8]
IDLE_105a2fdc:
 b IDLE_105a2fd4
.size ce_extension_idle,.-ce_extension_idle
.ltorg
