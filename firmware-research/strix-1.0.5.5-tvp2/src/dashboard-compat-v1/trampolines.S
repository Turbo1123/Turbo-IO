.syntax unified
.cpu cortex-m33
.thumb
.section .text.tdc_trampolines,"ax",%progbits
.balign 2
.global tdc_stock_source
.type tdc_stock_source,%function
.thumb_func
tdc_stock_source:
 .byte 0xb0,0xb5,0x04,0x46
 b.w tdc_resume_source
.balign 2
.global tdc_stock_serialize
.type tdc_stock_serialize,%function
.thumb_func
tdc_stock_serialize:
 .byte 0x2d,0xe9,0xf0,0x41
 b.w tdc_resume_serialize
.balign 2
.global tdc_stock_message
.type tdc_stock_message,%function
.thumb_func
tdc_stock_message:
 .byte 0xb0,0xb5,0x00,0x24
 b.w tdc_resume_message
