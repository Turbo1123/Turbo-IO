.syntax unified
.thumb
.section .text.ce_extension_idle,"ax",%progbits
.global ce_extension_idle
.type ce_extension_idle,%function
.thumb_func
ce_extension_idle:
CEL_106d334c:
push {r4, r7, lr}
CEL_106d334e:
sub sp, #0x1c
CEL_106d3350:
add r7, sp, #8
CEL_106d3352:
bl ce_ext_106e7b5c
CEL_106d3356:
mov r4, r0
CEL_106d3358:
bl ce_ext_106e8458
CEL_106d335c:
cbnz r0, CEL_106d337c
CEL_106d335e:
mov r0, r4
CEL_106d3360:
bl ce_ext_106e8460
CEL_106d3364:
cbnz r0, CEL_106d3388
CEL_106d3366:
bl ce_ext_106d3310
CEL_106d336a:
mov r4, r0
CEL_106d336c:
cbnz r0, CEL_106d3392
CEL_106d336e:
movs r0,#0
nop
CEL_106d3372:
cbz r0, CEL_106d33b0
CEL_106d3374:
movs r0, #0
CEL_106d3376:
adds r7, #0x14
CEL_106d3378:
mov sp, r7
CEL_106d337a:
pop {r4, r7, pc}
CEL_106d337c:
bl ce_ext_106d4c48
CEL_106d3380:
cmp r0, #0
CEL_106d3382:
beq CEL_106d335e
CEL_106d3384:
movs r0, #1
CEL_106d3386:
b CEL_106d3376
CEL_106d3388:
bl ce_ext_106d693c
CEL_106d338c:
cmp r0, #0
CEL_106d338e:
beq CEL_106d3366
CEL_106d3390:
b CEL_106d3384
CEL_106d3392:
ldrb r3, [r0]
CEL_106d3394:
cmp r3, #0
CEL_106d3396:
beq CEL_106d336e
CEL_106d3398:
ldr r1, =0x18052201
CEL_106d339a:
bl ce_ext_10941968
CEL_106d339e:
cmp r0, #0
CEL_106d33a0:
beq CEL_106d336e
CEL_106d33a2:
mov r0, r4
CEL_106d33a4:
ldr r1, =0x1805240d
CEL_106d33a6:
bl ce_ext_10941968
CEL_106d33aa:
cmp r0, #0
CEL_106d33ac:
beq CEL_106d336e
CEL_106d33ae:
b CEL_106d3374
CEL_106d33b0:
bl ce_ext_106d245c
CEL_106d33b4:
mov r4, r0
CEL_106d33b6:
cmp r0, #0
CEL_106d33b8:
beq CEL_106d3384
CEL_106d33ba:
movs r2, #0x10
CEL_106d33bc:
ldr r1, =0x18177273
CEL_106d33be:
adds r0, r7, #4
CEL_106d33c0:
bl ce_ext_106b61f0
CEL_106d33c4:
mov r0, r4
CEL_106d33c6:
adds r1, r7, #4
CEL_106d33c8:
bl ce_ext_106b60c4
CEL_106d33cc:
mov r4, r0
CEL_106d33ce:
adds r0, r7, #4
CEL_106d33d0:
bl ce_ext_106b6028
CEL_106d33d4:
cmp r4, #0
CEL_106d33d6:
beq CEL_106d3384
CEL_106d33d8:
ldr r4, [r4, #0x14]
CEL_106d33da:
cbnz r4, CEL_106d33f2
CEL_106d33dc:
ldr r3, =0x1804300a
CEL_106d33de:
mov r2, r4
CEL_106d33e0:
str r3, [sp]
CEL_106d33e2:
mov r1, r4
CEL_106d33e4:
mov r3, r4
CEL_106d33e6:
movs r0, #1
CEL_106d33e8:
bl ce_ext_107d5cd8
CEL_106d33ec:
eor r0, r4, #1
CEL_106d33f0:
b CEL_106d3376
CEL_106d33f2:
ldrb r4, [r4, #8]
CEL_106d33f4:
b CEL_106d33ec
.size ce_extension_idle,.-ce_extension_idle
.ltorg
