default rel

section .text
global _start

_start:
    mov r8, [rsp]
    cmp r8, 2
    jne .usage

    mov rsi, [rsp + 16]
    call trim_leading
    mov [rsp + 16], rax
    mov rsi, rax
    call trim_trailing

    cmp byte [rsi], 0
    je .empty_prompt

    lea r12, [rsp + r8*8 + 16]

    mov rdi, r12
    call find_env_var
    test rax, rax
    jz .default_runner

    lea rdi, [runner_buf]
    mov rsi, rax
    call strcpy_256
    lea r14, [runner_buf]
    jmp .do_fork

.default_runner:
    lea r14, [str_opencode]

.do_fork:
    mov [exec_argv], r14
    lea rax, [str_run]
    mov [exec_argv + 8], rax
    mov rax, [rsp + 16]
    mov [exec_argv + 16], rax
    mov qword [exec_argv + 24], 0

    mov rax, 57
    syscall
    test rax, rax
    js .fork_error
    jz .child

.parent:
    mov rdi, rax
    lea rsi, [status_buf]
    xor rdx, rdx
    mov rax, 61
    syscall
    mov eax, [status_buf]
    and eax, 0x7f
    jnz .signal_exit
    mov eax, [status_buf]
    shr eax, 8
    and eax, 0xff
    mov rdi, rax
    mov rax, 231
    syscall

.signal_exit:
    mov edi, 1
    mov rax, 231
    syscall

.child:
    mov rdi, [exec_argv]
    lea rsi, [exec_argv]
    mov rdx, r12
    mov rax, 59
    syscall

    mov rdi, 2
    lea rsi, [msg_exec_prefix]
    mov rdx, msg_exec_prefix_len
    call write_str
    mov rsi, r14
    call strlen
    mov rdx, rax
    mov rdi, 2
    mov rsi, r14
    call write_str
    mov rdi, 2
    lea rsi, [msg_exec_suffix]
    mov rdx, msg_exec_suffix_len
    call write_str
    mov edi, 127
    mov rax, 231
    syscall

.usage:
    mov rdi, 2
    lea rsi, [msg_usage]
    mov rdx, msg_usage_len
    call write_str
    mov edi, 1
    mov rax, 231
    syscall

.empty_prompt:
    mov rdi, 2
    lea rsi, [msg_empty]
    mov rdx, msg_empty_len
    call write_str
    mov edi, 1
    mov rax, 231
    syscall

.fork_error:
    mov rdi, 2
    lea rsi, [msg_fork]
    mov rdx, msg_fork_len
    call write_str
    mov edi, 1
    mov rax, 231
    syscall

strlen:
    mov rax, rsi
.sl_loop:
    cmp byte [rax], 0
    je .sl_done
    inc rax
    jmp .sl_loop
.sl_done:
    sub rax, rsi
    ret

write_str:
.ws_loop:
    mov rax, 1
    syscall
    test rax, rax
    jle .ws_done
    sub rdx, rax
    add rsi, rax
    test rdx, rdx
    jnz .ws_loop
.ws_done:
    ret

trim_leading:
.tl_loop:
    cmp byte [rsi], 0x09
    je .tl_ws
    cmp byte [rsi], 0x0a
    je .tl_ws
    cmp byte [rsi], 0x0b
    je .tl_ws
    cmp byte [rsi], 0x0c
    je .tl_ws
    cmp byte [rsi], 0x0d
    je .tl_ws
    cmp byte [rsi], 0x20
    je .tl_ws
    mov rax, rsi
    ret
.tl_ws:
    inc rsi
    jmp .tl_loop

trim_trailing:
    mov rdi, rsi
.tt_find_end:
    cmp byte [rdi], 0
    je .tt_back
    inc rdi
    jmp .tt_find_end
.tt_back:
    cmp rdi, rsi
    je .tt_done
    dec rdi
    cmp byte [rdi], 0x09
    je .tt_back
    cmp byte [rdi], 0x0a
    je .tt_back
    cmp byte [rdi], 0x0b
    je .tt_back
    cmp byte [rdi], 0x0c
    je .tt_back
    cmp byte [rdi], 0x0d
    je .tt_back
    cmp byte [rdi], 0x20
    je .tt_back
    inc rdi
.tt_done:
    mov byte [rdi], 0
    ret

find_env_var:
    mov r8, rdi
.fev_loop:
    mov r9, [r8]
    test r9, r9
    jz .fev_not_found
    lea r10, [env_key]
    mov rcx, 18
.fev_cmp:
    mov al, [r9]
    cmp al, [r10]
    jne .fev_next
    inc r9
    inc r10
    dec rcx
    jnz .fev_cmp
    mov rax, [r8]
    add rax, 18
    ret
.fev_next:
    add r8, 8
    jmp .fev_loop
.fev_not_found:
    xor rax, rax
    ret

strcpy_256:
    mov rcx, 255
.sc_loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .sc_done
    inc rsi
    inc rdi
    dec rcx
    jnz .sc_loop
    mov byte [rdi], 0
.sc_done:
    ret

section .rodata
msg_usage: db 'usage: ccc "<Prompt>"', 10
msg_usage_len equ $ - msg_usage
msg_empty: db 'prompt must not be empty', 10
msg_empty_len equ $ - msg_empty
msg_fork: db 'fork failed', 10
msg_fork_len equ $ - msg_fork
msg_exec_prefix: db 'failed to start '
msg_exec_prefix_len equ $ - msg_exec_prefix
msg_exec_suffix: db ': execve failed', 10
msg_exec_suffix_len equ $ - msg_exec_suffix
str_run: db 'run', 0
str_opencode: db 'opencode', 0
env_key: db 'CCC_REAL_OPENCODE=', 0

section .bss
exec_argv: resq 4
status_buf: resd 1
runner_buf: resb 256

section .note.GNU-stack noalloc noexec nowrite progbits
