.syntax unified
.cpu cortex-m33
.thumb
.section .text.trampolines,"ax",%progbits
.balign 2
.global stock_show
.type stock_show,%function
.thumb_func
stock_show:
.byte 0x90,0xb5,0x83,0xb0
b.w resume_show
.balign 2
.global stock_hide
.type stock_hide,%function
.thumb_func
stock_hide:
.byte 0xb0,0xb5,0x82,0xb0
b.w resume_hide
.balign 2
.global stock_destroy
.type stock_destroy,%function
.thumb_func
stock_destroy:
.byte 0xf0,0xb5,0x4,0x46
b.w resume_destroy
.balign 2
.global stock_wheel
.type stock_wheel,%function
.thumb_func
stock_wheel:
.byte 0x2d,0xe9,0xf0,0x41
b.w resume_wheel
.balign 2
.global stock_event
.type stock_event,%function
.thumb_func
stock_event:
.byte 0xb0,0xb5,0x82,0xb0
b.w resume_event
.balign 2
.global stock_message
.type stock_message,%function
.thumb_func
stock_message:
.byte 0xb0,0xb5,0xc,0x46
b.w resume_message
.balign 2
.global stock_dc_text
.type stock_dc_text,%function
.thumb_func
stock_dc_text:
.byte 0xf0,0xb5,0xc3,0xb0
b.w resume_dc_text
.balign 2
.global stock_names
.type stock_names,%function
.thumb_func
stock_names:
.byte 0x2d,0xe9,0xf0,0x4f
b.w resume_names
.balign 2
.global stock_dots
.type stock_dots,%function
.thumb_func
stock_dots:
.byte 0x2d,0xe9,0xf0,0x47
b.w resume_dots
.balign 2
.global stock_delete_dots
.type stock_delete_dots,%function
.thumb_func
stock_delete_dots:
.byte 0x98,0xb5,0x4,0x46
b.w resume_delete_dots
.balign 2
.global stock_lottie
.type stock_lottie,%function
.thumb_func
stock_lottie:
.byte 0xb0,0xb5,0x84,0xb0
b.w resume_lottie
.balign 2
.global stock_app_id
.type stock_app_id,%function
.thumb_func
stock_app_id:
.byte 0x80,0xb5,0x0,0xaf
b.w resume_app_id
.balign 2
.global stock_refresh_label
.type stock_refresh_label,%function
.thumb_func
stock_refresh_label:
.byte 0x2d,0xe9,0xf0,0x41
b.w resume_refresh_label
.balign 2
.global stock_vm_event
.type stock_vm_event,%function
.thumb_func
stock_vm_event:
.byte 0xf0,0xb5,0x85,0xb0
b.w resume_vm_event

.balign 2
.global stream_register_shim
.type stream_register_shim,%function
.thumb_func
stream_register_shim:
 movs r4,#0
 ldr r0,=0x196c6988
 ldr r3,=tio_hook_file
 str r3,[r0,#0x18]
 ldr r3,=0x10583605
 str r3,[r0]
 bx lr
.ltorg
.balign 2
.global m8_hook_frame_start
.type m8_hook_frame_start,%function
.thumb_func
m8_hook_frame_start:
push {r1,r2,r3,lr}
bl m8_impl_frame_start
pop {r1,r2,r3,pc}
.balign 2
.global m8_hook_frame_index
.type m8_hook_frame_index,%function
.thumb_func
m8_hook_frame_index:
push {r1,r2,r3,lr}
bl m8_impl_frame_index
pop {r1,r2,r3,pc}
