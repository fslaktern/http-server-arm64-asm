# REGISTER USAGE
#
# x0 - x7: Arguments for syscalls and function calls
#     - x0: Also used as return value for syscalls and function calls
#     - x1: Also used as error code for function calls. (ok = 0, error = 1)
# x8: Syscall number
#
# x9 - x18: Scratch registers. Must be saved in function prologue, and restored in function epilogue
#
# x19 - x28: Static registers for long lived values
#     - x19: IP as string
#     - x20: Port as string
#     - x21: IP as int
#     - x22: Port as big endian int
#     - x23: Server socket file descriptor
#     - x24: Client socket file descriptor
#     - x25: Serve directory file descriptor
#     - x26: Requested file file descriptor
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
    .equ O_RDONLY, 0
    .equ AT_FDCWD, -100

.text
_start:
    # set stack frame size = 0
    mov x29, sp

parse_args:
    # stack
    # 00:0000│  sp 0x666ac3fff740 ◂— 3
    # 01:0008│     0x666ac3fff748 —▸ 0x666ac3fffa20 ◂— './server'
    # 02:0010│     0x666ac3fff750 —▸ 0x666ac3fffa29 ◂— 0x302e302e302e30 '0.0.0.0'
    # 03:0018│     0x666ac3fff758 —▸ 0x666ac3fffa31 ◂— 0x5f4d524554003038 '80'
    # [sp] = argc and [sp + 8..n8] = argv

    # store argc in x3, ignore progname
    # post-increment sp to addr of first argument to program
    ldp x3, xzr, [sp], #16
    cmp x3, #3
    b.ne invalid_args

    # load ip addr and port str args to x19 and x20
    ldp x19, x20, [sp], #16

    # ipv4 to 32 bit int
    mov x0, x19
    bl inet_aton
    cbnz x1, exit_err
    mov x21, x0

    # convert port to int then to network byte order (big endian)
    mov x0, x20

    bl atoi
    # exit if function returns err
    cbnz x1, exit_err
    # exit if port is too large
    mov x1, #0xffff
    cmp x0, x1
    b.hi exit_err

    bl htons
    mov x22, x0

create_socket:
    # server_sockfd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    mov x0, #AF_INET
    # Consider SOCK_STREAM | SOCK_CLOEXEC
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
    # accept(server_sockfd, *clientaddr_buf, *clientaddr_len, 0)
    mov x0, x23
    ldr x1, =clientaddr_buffer
    ldr x2, =clientaddr_len
    mov x3, #0
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
    cbz x0, child_must_grow_up
    # If not child, thus parent: leave immediatly

father_leave:
    # Close newly opened client_sockfd
    mov x0, x24
    mov x8, #sys_close
    svc #0

    # Listen for more connections
    b serve_loop

child_must_grow_up:
    # Close listening server_sockfd
    mov x0, x23
    mov x8, #sys_close
    svc #0

handle_request:
    # Read entire HTTP request into buffer
    mov x0, x24
    ldr x1, =ingress_buffer
    ldr x2, =ingress_buffer_max
    mov x8, #sys_read
    svc #0
    # Save number of bytes read
    ldr x1, =ingress_buffer_size
    str x0, [x1, #0]

read_http_verb:
    # Reads up to 7 characters until first space
    ldr x0, =ingress_buffer
    ldr x1, =http_request_verb
    mov x2, #' '
    ldr x3, =http_request_verb_max
    bl strntok

    mov x9, x0
read_http_path:
    # Read up to 255 bytes or until next space, continuing where previous read left off
    ldr x0, =ingress_buffer

    # Skip bytes_read + 1 (space) to read next field
    add x0, x0, x9
    add x0, x0, #1

    ldr x1, =http_request_path
    mov x2, #' '
    ldr x3, =http_request_path_max
    bl strntok

current_directory_fd:
    # mov x0, #0
    # ldr x1, serve_directory
    # mov x2,
    # mov x3, O_DIRECTORY
    # eor x4, x4, x4
    # mov x8, #sys_openat
    # svc #0
    # mov x25, x0

branch_on_http_verb:
    # http_request_verb == "GET"
    ldr x0, =http_request_verb
    ldr x1, =http_verb_get
    mov x2, x9
    bl memcmp
    b handle_get

    # http_request_verb == "POST"
    ldr x0, =http_request_verb
    ldr x1, =http_verb_post
    mov x2, x9
    bl memcmp
    b handle_post

    # No match == no answer
    b exit_client

handle_get:
.open_requested_file_r:
    mov x0, #AT_FDCWD
    ldr x1, =http_request_path
    mov x2, #O_RDONLY
    # Mode is unused unless O_CREAT is used
    mov x3, #0
    mov x8, #sys_openat
    svc #0

.read_requested_file:
    mov x8, #sys_read
    svc #0

.handle_get_finish:
    b close_requested_file

handle_post:
.open_requested_file_w:
    mov x8, #sys_openat
    svc #0
    # Save requested_file_fd
    mov x26, x0

.extract_request_body:
    ldr x9, =ingress_buffer_size
    ldr x10, =http_separator_size

    # Find header-body separator
    ldr x0, =ingress_buffer
    ldr x1, =http_separator
    ldr x2, =http_separator_size
    mov x3, x9
    bl strstr

    # Close connection on error
    cbnz x1, exit_client

    # Body size + http_separator
    sub x11, x9, x0
    # Subtract size of http_separator
    sub x11, x11, x10
    # x11 = entire body size

.write_requested_file:
    # write(requested_file_fd, ingress_buffer + header_size + http_separator_size, body_size)
    mov x0, x26

    # Start of body
    ldr x1, =ingress_buffer
    add x1, x1, x9
    add x1, x1, x10

    mov x2, x11

    mov x8, #sys_write
    svc #0
    # exit if we couldn't write a single byte
    cbz x0, exit_client

.handle_post_finish:
    b close_requested_file

close_requested_file:
    # close(requested_file_fd)
    mov x0, x26
    mov x8, #sys_close
    svc #0

send_response:
    # write(client_sockfd, egress_buffer, egress_buffer_size)
    mov x0, x24
    ldr x1, =egress_buffer
    ldr x2, =egress_buffer_size
    mov x8, #sys_write
    svc #0

exit_client:
close_client_connection:
    # close(client_sockfd)
    mov x0, x24
    mov x8, #sys_close
    svc #0

exit:
    # exit(0)
    eor x0, x0, x0
    mov x8, #sys_exit
    svc #0

# ERRORS

invalid_args:
    # write(stderr, error_message, error_message_size)
    mov x0, #2
    ldr x1, =argument_error
    ldr x2, =argument_error_len
    mov x8, #sys_write
    svc #0

    b exit_err

exit_err:
    # exit(1)
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
    mov x2, #'.'

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
    cmp x13, #'0'
    b.lo .atoi_fail

    # make sure ascii value of digit is not more than that of "9"
    cmp x13, #'9'
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

    # x0: buffer #1
    # x1: buffer #2
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

    # No IPv6 support
clientaddr_buffer:
    # sin_family
    .space 2
    # sin_port
    .space 2
    # sin_addr
    .space 4
    # sin_zero
    .space 8
    clientaddr_size = . - clientaddr_buffer

clientaddr_len:
    .word clientaddr_size


ip_octet_buffer:
    .space 4
    ip_octet_buffer_max = . - ip_octet_buffer

http_request_verb:
    .space 8
    http_request_verb_max = . - http_request_verb - 1

http_request_path:
    .space 256
    http_request_path_max = . - http_request_path - 1

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
    .ascii "\n\r\n\r"
    http_separator_size = . - http_separator

http_verb_get:
    .asciz "GET"
http_verb_post:
    .asciz "POST"
http_verb_head:
    .asciz "HEAD"
http_verb_put:
    .asciz "PUT"
http_verb_delete:
    .asciz "DELETE"

argument_error:
    .asciz "Invalid number of arguments.\n\nExample: listen on all interfaces on port 8000\n./server 0.0.0.0 8000\n         ^^^^^^^ ^^^^\n         IP      PORT\n"
    argument_error_len = . - argument_error
