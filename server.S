.global _start

.equ sys_openat, 56
.equ sys_close, 57
.equ sys_lseek, 62
.equ sys_read, 63
.equ sys_write, 64
.equ sys_exit, 93
.equ sys_socket, 198
.equ sys_bind, 200
.equ sys_listen, 201
.equ sys_accept, 202
.equ sys_clone, 220
.equ sys_seccomp, 277

.text
_start:
    mov x29, sp

parse_args:
    # get argc but discard program name
    ldp x3, xzr, [sp], #16

    cmp x3, #3
    b.ne invalid_args

    # load first and second argument
    ldp x19, x20, [sp], #16

    # ipv4 to int
    mov x0, x19
    bl ipv4_to_int
    mov x19, x0

    # convert port to int then to network byte order
    mov x0, x20
    bl atoi
    bl htons
    mov x20, x0

    b exit

create_socket:
bind_socket:
listen_socket:
serve_loop:
accept_connection:
child_birth:
father_leave:
child_must_go_on:
handle_request:
read_http_verb:
read_http_path:
branch_on_http_verb:
handle_get:
.open_requested_file_r:
.read_requested_file:
.handle_get_finish:
handle_post:
.open_requested_file_w:
.extract_request_body:
.write_requested_file:
.handle_get_finish:

close_requested_file:
    mov x0, x21
    mov x8, #sys_close
    svc #0

send_response:
    mov x0, x20
    ldr x1, =egress_buffer
    ldr x2, =egress_buffer_size
    mov x8, #sys_write
    svc #0

close_client_connection:
    mov x0, x20
    mov x8, #sys_close
    svc #0

exit:
    eor x0, x0, x0
    mov x8, #sys_exit
    svc #0

# ERRORS

invalid_args:
    mov x0, #2
    ldr x1, =argument_error
    ldr x2, =argument_error_len
    mov x8, #sys_write
    svc #0

exit_err:
    mov x0, #1
    mov x8, #sys_exit
    svc #0

# HELPER FUNCTIONS

    # convert port from little endian to network endian
    # x0: little endian int
htons:
    ret

    # convert ipv4 to 32 bit int
    # x0: ipv4 string
ipv4_to_int:
    # get first octet
    # convert octet to int
    # bitshift and add int to result

    # get second octet
    # convert octet to int
    # bitshift and add int to result

    # get third octet
    # convert octet to int
    # bitshift and add int to result

    # get fourth octet
    # convert octet to int
    # bitshift and add int to result
    ret

    # convert string formatted number to 64 bit integer
    # x0: null padded string
    #
    # returns:
    # x0: integer if x1 is 0
    # x1: 0 if success, 1 if fail
atoi:
    # store result
    mov x9, #0
    # multiplier: 1, 10, 100, ...
    mov x10, #1
    # multiplier for multiplier
    mov x14, #10
    # number string
    mov x11, x0

    bl strlen
    # length of string
    mov x12, x0

    # loop from end to start
.atoi_loop:
    ldrb x13, [x11, x12]
    # make sure ascii value of digit is not less than that of "0"
    cmp x13, 48
    b.lt .atoi_fail

    # make sure ascii value of digit is not more than that of "9"
    cmp x13, 57
    b.bt .atoi_fail

    # convert string digit to integer digit
    sub x13, 48

    # multiply with multiplier and add to result
    madd x9, x13, x10, x9
    mul x10, x10, x14

    # loop
    sub x12, x12, #1
    cbnz .atoi_loop

.atoi_done:
    mov x0, x9
    mov x1, #0
    ret
.atoi_fail:
    mov x1, #1
    ret

    # x0: source buffer
    # x1: destination buffer
    # x2: delimiter
    # x3: max read length
strntok:
    eor x22, x22, x22
.strntok_loop:
    cmp x3, x22
    b.ge .strntok_done
    ldrb w11, [x0, x22]
    cmp w11, w2
    b.eq .strntok_done
    strb w11, [x1, x22]
    b .strntok_loop
.strntok_done:
    mov x0, x22
    ret

    # x0: haystack
    # x1: substring
    # x2: substring length
    # x3: haystack length
strstr:
    eor x19, x19, x19
    cmp x2, x3
    b.gt .strstr_diff
    sub x3, x3, x2
    mov x20, x0
.strstr_loop:
    cmp x19, x3
    b.ge .strstr_diff
    add x0, x20, x19
    bl memcmp
    cbz x0, .strstr_match
    add x19, x19, #1
    b .strstr_loop
.strstr_match:
    mov x0, x19
    ret
.strstr_diff:
    mov x0, #-1
    ret

    # x0: source buffer
    # x1: destination buffer
    # x2: count bytes
memcmp:
    eor x3, x3, x3
    and x19, x2, #~7
.memcmp_loop_chunk:
    cmp x3, x19
    b.eq .memcmp_loop_tail
    ldr x20, [x0, x3]
    ldr x21, [x1, x3]
    cmp x20, x21
    b.ne .memcmp_diff
    add x3, x3, #8
    b .memcmp_loop_chunk
.memcmp_loop_tail:
    cmp x3, x2
    b.eq .memcmp_match
    ldrb w10, [x0, x3]
    ldrb w11, [x1, x3]
    cmp w10, w11
    b.ne .memcmp_diff
    add x3, x3, #1
    b .memcmp_loop_tail
.memcmp_match:
    eor x0, x0, x0
    ret
.memcmp_diff:
    mov x0, #1
    ret

strlen:
    eor x22, x22, x22
.strlen_loop:
    ldrb w1, [x0, x22]
    cbz w1, .strlen_done
    add x22, x22, #1
    b .strlen_loop
.strlen_done:
    mov x0, x22
    ret

memcpy:
    eor x3, x3, x3
    and x20, x2, #~7
.memcpy_loop_chunk:
    cmp x3, x20
    b.eq .memcpy_loop_tail
    ldr x19, [x0, x3]
    str x19, [x1, x3]
    add x3, x3, #8
    b .memcpy_loop_chunk
.memcpy_loop_tail:
    cmp x3, x2
    b.eq .memcpy_done
    ldrb w9, [x0, x3]
    strb w9, [x1, x3]
    add x3, x3, #1
    b .memcpy_loop_tail
.memcpy_done:
    ret

.data
.align 4
ingress_buffer:
    .space 4096
    ingress_buffer_max = . - ingress_buffer

ingress_buffer_size:
    .word 0

egress_buffer:
    .space 4096
    egress_buffer_max = . - egress_buffer

egress_buffer_size:
    .word 0


.section .rodata
.align 4
http_separator:
    .byte 0xa, 0xd, 0xa, 0xd
    http_separator_length = . - http_separator

http_verb_get:
    .asciz "GET"

http_verb_post:
    .asciz "POST"

argument_error:
    .asciz "Invalid number of arguments.\n\nExample: listen on all interfaces on port 8000\n./server 0.0.0.0 8000\n         ^^^^^^^ ^^^^\n         IP      PORT\n"
    argument_error_len = . - argument_error
