.syntax unified
.thumb
.section .text,"ax",%progbits
.global validator_instruction
.type validator_instruction,%function
.thumb_func
validator_instruction:
 .byte 0x53,0xea,0x03,0x93
 bx lr
