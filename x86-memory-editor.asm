section .data
    msgSuccess    db "Write reported success. Read-back value: ", 0
    msgFailOpen   db "Failed to open process (check PID / run as admin).", 13, 10, 0
    msgFailWrite  db "Failed to write memory (invalid address?).", 13, 10, 0
    msgFailRead   db "Write succeeded but read-back failed.", 13, 10, 0
    msgUsage      db "Usage: x86-memory-editor.exe <PID> <hex_address> <value>", 13, 10, 0
    newline       db 13, 10, 0

section .bss
    pidValue      resd 1      ; target process ID
    targetAddr    resd 1      ; memory address to write to
    newValue      resd 1      ; new value to write
    readBack      resd 1      ; value read back after writing, for verification
    hProcess      resd 1      ; handle to the opened process
    bytesWritten  resd 1      ; bytes actually written by WriteProcessMemory
    bytesRead     resd 1      ; bytes actually read by ReadProcessMemory
    hStdOut       resd 1      ; console output handle
    charsWritten  resd 1      ; bytes written by WriteConsoleA
    numBuffer     resb 16     ; scratch buffer for integer -> string conversion

section .text
    global main
    extern _GetCommandLineA@0
    extern _OpenProcess@12
    extern _WriteProcessMemory@20
    extern _ReadProcessMemory@20
    extern _CloseHandle@4
    extern _GetStdHandle@4
    extern _WriteConsoleA@20
    extern _ExitProcess@4

; ---------------------------------------------------------------------
; print_msg
; Prints a null-terminated string to stdout.
; In:  EAX = pointer to null-terminated string
; ---------------------------------------------------------------------
print_msg:
    push eax
    mov ecx, eax
.strlen_loop:
    cmp byte [ecx], 0
    je .strlen_done
    inc ecx
    jmp .strlen_loop
.strlen_done:
    pop eax
    sub ecx, eax                ; ECX = string length
    push 0
    push charsWritten
    push ecx
    push eax
    push dword [hStdOut]
    call _WriteConsoleA@20
    ret

; ---------------------------------------------------------------------
; print_number
; Converts an unsigned 32-bit integer to decimal text and prints it.
; In: EAX = number to print
; ---------------------------------------------------------------------
print_number:
    mov edi, numBuffer
    add edi, 15
    mov byte [edi], 0            ; null terminator
    mov ebx, 10
.convert_loop:
    xor edx, edx
    div ebx                      ; EAX / 10 -> quotient in EAX, remainder in EDX
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .convert_loop
    mov eax, edi
    call print_msg
    ret

; ---------------------------------------------------------------------
; skip_spaces
; Advances ESI past any space characters.
; ---------------------------------------------------------------------
skip_spaces:
.loop:
    cmp byte [esi], ' '
    jne .done
    inc esi
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------
; parse_number
; Parses a decimal integer starting at ESI, advancing ESI past it.
; Out: EAX = parsed value
; ---------------------------------------------------------------------
parse_number:
    xor eax, eax
.loop:
    movzx ecx, byte [esi]
    cmp ecx, '0'
    jl .done
    cmp ecx, '9'
    jg .done
    sub ecx, '0'
    imul eax, eax, 10
    add eax, ecx
    inc esi
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------
; parse_hex
; Parses a hexadecimal integer starting at ESI (optional "0x"/"0X"
; prefix), advancing ESI past it.
; Out: EAX = parsed value
; ---------------------------------------------------------------------
parse_hex:
    xor eax, eax

    cmp byte [esi], '0'
    jne .digits
    mov cl, [esi+1]
    cmp cl, 'x'
    je .skip_prefix
    cmp cl, 'X'
    je .skip_prefix
    jmp .digits
.skip_prefix:
    add esi, 2

.digits:
    movzx ecx, byte [esi]

    cmp ecx, '0'
    jl .done
    cmp ecx, '9'
    jle .is_digit

    cmp ecx, 'A'
    jl .done
    cmp ecx, 'F'
    jle .is_upper

    cmp ecx, 'a'
    jl .done
    cmp ecx, 'f'
    jg .done
    sub ecx, 'a'
    add ecx, 10
    jmp .accumulate

.is_upper:
    sub ecx, 'A'
    add ecx, 10
    jmp .accumulate

.is_digit:
    sub ecx, '0'

.accumulate:
    shl eax, 4
    add eax, ecx
    inc esi
    jmp .digits

.done:
    ret

; ---------------------------------------------------------------------
; main
; Entry point. Parses "<PID> <hex_address> <value>" from the command
; line, then opens the target process and writes the value.
; ---------------------------------------------------------------------
main:
    push -11                     ; STD_OUTPUT_HANDLE
    call _GetStdHandle@4
    mov [hStdOut], eax

    call _GetCommandLineA@0
    mov esi, eax

    ; Skip argv[0] (the program's own path), which may be quoted
    ; if it contains spaces (e.g. "C:\my folder\x86-memory-editor.exe").
    cmp byte [esi], '"'
    jne .skip_unquoted
    inc esi
.skip_quoted_loop:
    cmp byte [esi], '"'
    je .after_progname
    cmp byte [esi], 0
    je .usage_error
    inc esi
    jmp .skip_quoted_loop
.skip_unquoted:
    cmp byte [esi], ' '
    je .after_progname
    cmp byte [esi], 0
    je .usage_error
    inc esi
    jmp .skip_unquoted
.after_progname:
    inc esi

    ; arg1: PID (decimal)
    call skip_spaces
    cmp byte [esi], 0
    je .usage_error
    call parse_number
    mov [pidValue], eax

    ; arg2: target address (hex, with or without "0x")
    call skip_spaces
    cmp byte [esi], 0
    je .usage_error
    call parse_hex
    mov [targetAddr], eax

    ; arg3: new value (decimal)
    call skip_spaces
    cmp byte [esi], 0
    je .usage_error
    call parse_number
    mov [newValue], eax

    ; OpenProcess(PROCESS_VM_READ | PROCESS_VM_WRITE | PROCESS_VM_OPERATION,
    ;             FALSE, pid)
    push dword [pidValue]
    push 0
    push 0x0038
    call _OpenProcess@12
    mov [hProcess], eax
    cmp eax, 0
    je .fail_open

    ; WriteProcessMemory(hProcess, targetAddr, &newValue, 4, &bytesWritten)
    push bytesWritten
    push 4
    push newValue
    push dword [targetAddr]
    push dword [hProcess]
    call _WriteProcessMemory@20
    cmp eax, 0
    je .fail_write

    ; Read the value back to confirm what actually landed in memory.
    push bytesRead
    push 4
    push readBack
    push dword [targetAddr]
    push dword [hProcess]
    call _ReadProcessMemory@20
    cmp eax, 0
    je .fail_read

    push dword [hProcess]
    call _CloseHandle@4

    mov eax, msgSuccess
    call print_msg
    mov eax, [readBack]
    call print_number
    mov eax, newline
    call print_msg

    push 0
    call _ExitProcess@4

.fail_open:
    mov eax, msgFailOpen
    call print_msg
    push 1
    call _ExitProcess@4

.fail_write:
    push dword [hProcess]
    call _CloseHandle@4
    mov eax, msgFailWrite
    call print_msg
    push 1
    call _ExitProcess@4

.fail_read:
    push dword [hProcess]
    call _CloseHandle@4
    mov eax, msgFailRead
    call print_msg
    push 1
    call _ExitProcess@4

.usage_error:
    mov eax, msgUsage
    call print_msg
    push 1
    call _ExitProcess@4