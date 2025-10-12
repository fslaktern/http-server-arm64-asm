# REGISTER USAGE
#
# x0 - x7: Arguments for syscalls and function calls
#     - x0: Also used as return value for syscalls and function calls
#     - x1: Also used as error code for function calls. (ok = 0, error = 1)
# x8: Syscall number
#
# x9 - x18: Scratch registers. Must be saved in function prologue, and restored in function epilogue
#
# x19 - 28: Static registers for long lived values
#     - x19: IP as string
#     - x20: Port as string
#     - x21: IP as int
#     - x22: Port as big endian int
#     - x23: Server socket file descriptor
#     - x24: Client socket file descriptor
#     - x25: Requested file file descriptor
#
# x29: Base pointer
# sp: Stack pointer

    .global _start

    .equ sys_openat, 56
    .equ sys_close, 57
    .equ sys_lseek, 62
    .equ sys_read, 63
    .equ sys_write, 64
    .equ sys_exit, 93
    .equ sys_getpid, 172
    .equ sys_socket, 198
    .equ sys_bind, 200
    .equ sys_listen, 201
    .equ sys_accept, 202
    .equ sys_clone, 220
    .equ sys_seccomp, 277

    .equ AF_INET, 2
    .equ SOCK_STREAM, 1
    .equ IPPROTO_TCP, 0
    .equ O_CLOEXEC, 02000000

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
    bl inet_aton
    cbnz x1, exit_err
    mov x21, x0

    # convert port to int then to network byte order
    mov x0, x20

    bl atoi
    # exit if function returns err
    cbnz x1, exit_err

    bl htons
    mov x22, x0

create_socket:
    # server_sockfd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    mov x0, #AF_INET
    mov x1, #SOCK_STREAM
    mov x2, #IPPROTO_TCP
    mov x8, #sys_socket
    svc #0
    mov x23, x0

bind_socket:
    # create instance of struct sockaddr_in
    ldr x0, =sockaddr_in_buffer

    # set sin_family (short)
    mov w1, #2
    strh w1, [x0, #0]

    # set sin_port (unsigned short)
    mov w1, w22
    strh w1, [x0, #2]

    # set sin_addr (unsigned int)
    mov w1, w21
    str w1, [x0, #4]

    # bind(server_sockfd, sockaddr, socklen)
    mov x0, x23
    ldr x1, =sockaddr_in_buffer
    mov x2, #sockaddr_in_size
    mov x8, #sys_bind
    svc #0

listen_socket:
    # listen(server_sockfd, backlog=0)
    mov x0, x23
    mov x1, #0
    mov x8, #sys_listen
    svc #0

serve_loop:
accept_connection:
    # accept(server_sockfd, *sockaddr, *sockaddr_size, O_CLOEXEC)
    mov x0, x23
    ldr x1, =sockaddr_in_buffer
    ldr x2, =sockaddr_in_size
    # Why O_CLOEXEC: https://tzimmermann.org/2017/08/17/file-descriptors-during-fork-and-exec/
    mov x3, #O_CLOEXEC
    mov x8, #sys_accept
    svc #0
    # save client_sockfd
    mov x24, x0

    b father_leave

child_birth:
    # Create a new child process
    mov x8, #sys_clone
    svc #0

    # Only way to distinguish parent from child, is by checking pid of current process (after fork, there are 2 processes: one parent and one child)
    # Parent will keep its original PID, but child will have PID 0
    mov x8, #sys_getpid
    svc #0
    # Branch if pid indicates that current process is the child
    cbz x0, child_must_go_on
    # If not child, thus parent: leave immediatly

father_leave:
    # Close newly opened client_sockfd
    mov x0, x24
    mov x8, #sys_close
    svc #0

    # Listen for more connections
    # b serve_loop

child_must_go_on:
    # Close listening server_sockfd
    mov x0, x23
    mov x8, #sys_close
    svc #0

    b exit

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
    mov x0, x25
    mov x8, #sys_close
    svc #0

send_response:
    mov x0, x24
    ldr x1, =egress_buffer
    ldr x2, =egress_buffer_size
    mov x8, #sys_write
    svc #0

close_client_connection:
    mov x0, x24
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

    b exit_err

exit_err:
    mov x0, #1
    mov x8, #sys_exit
    svc #0

# HELPER FUNCTIONS

    # convert port from little endian to network endian
    # x0: little endian int
htons:
    rev16 x0, x0
    ret

    # convert ipv4 to 32 bit int in network byte order
    # x0: ipv4 string
inet_aton:
    # save registers
    stp lr, x9, [sp, #-16]!
    stp x10, x11, [sp, #-16]!
    stp x12, x13, [sp, #-16]!

    # ipv4 string
    mov x9, x0
    # result
    mov x10, #0
    # loop counter
    mov x11, #0
    # loop counter max
    mov x12, #4
    # string cursor
    mov x13, #0

.inet_aton_per_octet:
    cmp x11, x12
    b.hs .inet_aton_done

    # get octet + offset from start of string
    add x0, x9, x13

    ldr x1, =ip_octet_buffer
    # zero buffer
    str xzr, [x1]

    # read until '.'
    mov x2, #46

    # allow reading more than 3 digits, to catch invalid values
    ldr x3, =ip_octet_buffer_max

    bl strntok
    # add length of substr
    add x13, x13, x0
    # add one to account for '.'
    add x13, x13, #1

    # convert octet to int
    ldr x0, =ip_octet_buffer
    bl atoi

    # fail if str->int parsing failed
    cbnz x1, .inet_aton_fail
    # fail if int is larger than 255
    cmp x0, #255
    b.hi .inet_aton_fail

    # bitshift and add int to result
    lsl x10, x10, 8
    orr x10, x10, x0

    # increment and loop
    add x11, x11, #1
    b .inet_aton_per_octet

.inet_aton_done:
    # swap endiannes of result
    rev32 x0, x10
    eor x1, x1, x1
    b .inet_aton_ret
.inet_aton_fail:
    mov x1, #1
    b .inet_aton_ret
.inet_aton_ret:
    # Restore registers
    ldp x12, x13, [sp], #16
    ldp x10, x11, [sp], #16
    ldp lr, x9, [sp], #16
    ret

    # convert string formatted number to 64 bit integer
    # x0: null padded string
    #
    # returns:
    # x0: integer if x1 is 0
    # x1: 0 if success, 1 if fail
atoi:
    # save registers
    stp x9, x10, [sp, #-16]!
    stp x11, x12, [sp, #-16]!
    stp x13, xzr, [sp, #-16]!

    # store result
    mov x9, #0
    # multiplier
    mov x10, #10
    # number string
    mov x11, x0
    # index
    mov x12, #0

    # loop over each digit, most significant to least significant
.atoi_loop:
    ldrb w13, [x11, x12]

    # if byte is null byte, we are done
    cbz x13, .atoi_done

    # make sure ascii value of digit is not less than that of "0"
    cmp x13, 48
    b.lo .atoi_fail

    # make sure ascii value of digit is not more than that of "9"
    cmp x13, 57
    b.hi .atoi_fail

    # convert string digit to integer digit
    sub x13, x13, 48

    # multiply with 10 and add digit
    mul x9, x9, x10
    add x9, x9, x13

    # loop
    add x12, x12, #1
    b .atoi_loop

.atoi_done:
    mov x0, x9
    mov x1, #0
    b .atoi_ret
.atoi_fail:
    mov x1, #1
    b .atoi_ret
.atoi_ret:
    # restore registers
    ldp x13, xzr, [sp], #16
    ldp x11, x12, [sp], #16
    ldp x9, x10, [sp], #16
    ret

    # x0: source buffer
    # x1: destination buffer
    # x2: delimiter
    # x3: max read length
strntok:
    eor x4, x4, x4
.strntok_loop:
    cmp x4, x3
    b.hs .strntok_done

    ldrb w5, [x0, x4]
    cmp w5, w2
    b.eq .strntok_done

    strb w5, [x1, x4]
    add x4, x4, #1
    b .strntok_loop
.strntok_done:
    mov x0, x4
    ret

    # x0: haystack
    # x1: substring
    # x2: substring length
    # x3: haystack length
strstr:
    # save registers
    stp lr, x9, [sp, #-16]!
    stp x10, xzr, [sp, #-16]!

    eor x9, x9, x9
    cmp x2, x3
    b.hi .strstr_diff
    sub x3, x3, x2
    mov x10, x0
.strstr_loop:
    cmp x9, x3
    b.hs .strstr_diff

    add x0, x10, x9
    bl memcmp
    cbz x0, .strstr_match

    add x9, x9, #1
    b .strstr_loop

.strstr_match:
    mov x0, x9
    eor x1, x1, x1
    b .strstr_ret
.strstr_diff:
    mov x1, #1
    b .strstr_ret
.strstr_ret:
    # restore registers
    ldp x10, xzr, [sp], #16
    ldp lr, x9, [sp], #16
    ret

    # x0: source buffer
    # x1: destination buffer
    # x2: count bytes
memcmp:
    # save registers
    stp x9, x10, [sp, #-16]!
    stp x11, xzr, [sp, #-16]!

    eor x3, x3, x3
    and x9, x2, #~7
.memcmp_loop_chunk:
    cmp x3, x9
    b.eq .memcmp_loop_tail
    ldr x10, [x0, x3]
    ldr x11, [x1, x3]
    cmp x10, x11
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
    eor x1, x1, x1
    b .memcmp_ret
.memcmp_diff:
    mov x1, #1
    b .memcmp_ret
.memcmp_ret:
    # restore registers
    ldp x11, xzr, [sp], #16
    ldp x9, x10, [sp], #16
    ret

    # x0: string to count length of
strlen:
    eor x1, x1, x1
.strlen_loop:
    ldrb w2, [x0, x1]
    cbz w2, .strlen_done
    add x1, x1, #1
    b .strlen_loop
.strlen_done:
    mov x0, x1
    ret

    # x0: source buffer
    # x1: destination buffer
memcpy:
    eor x3, x3, x3
    and x4, x2, #~7
.memcpy_loop_chunk:
    cmp x3, x4
    b.eq .memcpy_loop_tail
    ldr x5, [x0, x3]
    str x5, [x1, x3]
    add x3, x3, #8
    b .memcpy_loop_chunk
.memcpy_loop_tail:
    cmp x3, x2
    b.eq .memcpy_done
    ldrb w5, [x0, x3]
    strb w5, [x1, x3]
    add x3, x3, #1
    b .memcpy_loop_tail
.memcpy_done:
    ret

.data
.align 4
sockaddr_in_buffer:
    # sin_family
    .space 2
    # sin_port
    .space 2
    # sin_addr
    .space 4
    # sin_zero
    .space 8
    sockaddr_in_size = . - sockaddr_in_buffer

ip_octet_buffer:
    .space 4
    ip_octet_buffer_max = . - ip_octet_buffer

ingress_buffer:
    .space 4096
    ingress_buffer_max = . - ingress_buffer

ingress_buffer_size:
    .space 4

egress_buffer:
    .space 4096
    egress_buffer_max = . - egress_buffer

egress_buffer_size:
    .space 4


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
