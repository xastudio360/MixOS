; ============================================================================
; MixOS Bootloader - boot/boot.asm
; Минимальный Multiboot2 загрузчик для x86_64
; ============================================================================

; Константы Multiboot2
MULTIBOOT2_MAGIC           equ 0xE85250D6    ; Магическое число Multiboot2
MULTIBOOT2_ARCHITECTURE    equ 0             ; 0 = i386 (32-bit protected mode)
MULTIBOOT2_HEADER_LENGTH   equ (multiboot_header_end - multiboot_header_start)
MULTIBOOT2_CHECKSUM        equ -(MULTIBOOT2_MAGIC + MULTIBOOT2_ARCHITECTURE + MULTIBOOT2_HEADER_LENGTH)

; Константы для работы с памятью
KERNEL_STACK_SIZE equ 16384  ; 16 KB стек для ядра

; ============================================================================
; РАЗДЕЛ: Multiboot2 заголовок
; Должен быть в первых 32KB файла для распознавания GRUB
; ============================================================================
section .multiboot
align 8
multiboot_header_start:
    dd MULTIBOOT2_MAGIC              ; Магическое число
    dd MULTIBOOT2_ARCHITECTURE       ; Архитектура (i386)
    dd MULTIBOOT2_HEADER_LENGTH      ; Длина заголовка
    dd MULTIBOOT2_CHECKSUM           ; Контрольная сумма

    ; Framebuffer tag (опционально, для графического режима)
    align 8
    dw 5                             ; type = framebuffer
    dw 0                             ; flags
    dd 20                            ; size
    dd 1024                          ; width
    dd 768                           ; height
    dd 32                            ; depth (bits per pixel)

    ; Завершающий тег (обязательно!)
    align 8
    dw 0                             ; type = end
    dw 0                             ; flags
    dd 8                             ; size
multiboot_header_end:

; ============================================================================
; РАЗДЕЛ: BSS (неинициализированные данные)
; Здесь резервируем память под стек ядра
; ============================================================================
section .bss
align 16
stack_bottom:
    resb KERNEL_STACK_SIZE           ; Резервируем 16KB под стек
stack_top:

; Временные структуры для Page Tables (64-bit paging)
align 4096
pml4_table:     resb 4096            ; Page Map Level 4 (верхний уровень)
pdp_table:      resb 4096            ; Page Directory Pointer Table
pd_table:       resb 4096            ; Page Directory

; ============================================================================
; РАЗДЕЛ: Код загрузчика (32-bit protected mode)
; GRUB загружает нас в 32-битном режиме, нужно перейти в 64-bit long mode
; ============================================================================
section .text
bits 32                              ; Начинаем в 32-битном режиме

global _start
_start:
    ; GRUB передает в EAX магическое число, в EBX указатель на Multiboot info
    mov esp, stack_top               ; Устанавливаем стек (растет вниз)
    
    ; Сохраняем Multiboot info для передачи ядру
    push ebx                         ; Адрес структуры Multiboot info
    push eax                         ; Магическое число (должно быть 0x36d76289)

    ; Проверки перед переходом в long mode
    call check_multiboot
    call check_cpuid
    call check_long_mode

    ; Настройка paging для long mode
    call setup_page_tables
    call enable_paging

    ; Загрузка 64-битного GDT
    lgdt [gdt64.pointer]

    ; Переход в 64-битный режим через far jump
    jmp gdt64.code_segment:long_mode_start

    ; Если что-то пошло не так, зависаем
    cli
.hang:
    hlt
    jmp .hang

; ----------------------------------------------------------------------------
; Проверка: загружены ли мы через Multiboot-совместимый загрузчик
; ----------------------------------------------------------------------------
check_multiboot:
    cmp eax, 0x36d76289              ; Multiboot2 magic number
    jne .no_multiboot
    ret
.no_multiboot:
    mov al, 'M'
    jmp error

; ----------------------------------------------------------------------------
; Проверка: поддерживает ли процессор инструкцию CPUID
; ----------------------------------------------------------------------------
check_cpuid:
    pushfd                           ; Сохраняем EFLAGS
    pop eax
    mov ecx, eax                     ; Копия для сравнения
    xor eax, 1 << 21                 ; Инвертируем ID bit
    push eax
    popfd                            ; Загружаем измененный EFLAGS
    pushfd
    pop eax
    push ecx
    popfd                            ; Восстанавливаем оригинальный EFLAGS
    cmp eax, ecx                     ; Если биты изменились - CPUID доступен
    je .no_cpuid
    ret
.no_cpuid:
    mov al, 'C'
    jmp error

; ----------------------------------------------------------------------------
; Проверка: поддерживает ли процессор Long Mode (64-bit)
; ----------------------------------------------------------------------------
check_long_mode:
    mov eax, 0x80000000              ; Расширенная функция CPUID
    cpuid
    cmp eax, 0x80000001              ; Проверяем доступность extended functions
    jb .no_long_mode
    
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29                ; LM bit (Long Mode)
    jz .no_long_mode
    ret
.no_long_mode:
    mov al, 'L'
    jmp error

; ----------------------------------------------------------------------------
; Настройка Page Tables для identity mapping первых 2MB
; (виртуальные адреса = физическим адресам)
; ----------------------------------------------------------------------------
setup_page_tables:
    ; Обнуляем таблицы
    mov edi, pml4_table
    mov ecx, 3 * 4096 / 4            ; 3 таблицы по 4KB
    xor eax, eax
    rep stosd
    
    ; PML4[0] -> PDP Table
    mov eax, pdp_table
    or eax, 0b11                     ; Present + Writable
    mov [pml4_table], eax
    
    ; PDP[0] -> PD Table
    mov eax, pd_table
    or eax, 0b11
    mov [pdp_table], eax
    
    ; PD[0] -> 2MB huge page (identity mapped)
    mov eax, 0x0
    or eax, 0b10000011               ; Present + Writable + Huge Page
    mov [pd_table], eax
    
    ret

; ----------------------------------------------------------------------------
; Включение Paging и переход в Long Mode
; ----------------------------------------------------------------------------
enable_paging:
    ; Загружаем PML4 в CR3
    mov eax, pml4_table
    mov cr3, eax
    
    ; Включаем PAE (Physical Address Extension) в CR4
    mov eax, cr4
    or eax, 1 << 5                   ; PAE bit
    mov cr4, eax
    
    ; Включаем Long Mode в EFER MSR
    mov ecx, 0xC0000080              ; EFER MSR
    rdmsr
    or eax, 1 << 8                   ; LM bit
    wrmsr
    
    ; Включаем paging в CR0
    mov eax, cr0
    or eax, 1 << 31                  ; PG bit
    mov cr0, eax
    
    ret

; ----------------------------------------------------------------------------
; Обработка критических ошибок
; Выводим код ошибки в верхний левый угол экрана (VGA текстовый режим)
; ----------------------------------------------------------------------------
error:
    mov dword [0xb8000], 0x4f524f45  ; "ER" красным на белом
    mov byte [0xb8004], al           ; Код ошибки
    mov byte [0xb8005], 0x4f
    cli
.hang:
    hlt
    jmp .hang

; ============================================================================
; РАЗДЕЛ: GDT для Long Mode (64-bit)
; ============================================================================
section .rodata
gdt64:
    dq 0                             ; Нулевой дескриптор (обязательно)
.code_segment: equ $ - gdt64
    dq (1<<43) | (1<<44) | (1<<47) | (1<<53) ; Code segment (executable, 64-bit)
.pointer:
    dw $ - gdt64 - 1                 ; Размер GDT - 1
    dq gdt64                         ; Адрес GDT

; ============================================================================
; РАЗДЕЛ: 64-битный код
; Точка входа после перехода в Long Mode
; ============================================================================
section .text
bits 64
long_mode_start:
    ; Обнуляем сегментные регистры (в long mode они не используются)
    xor ax, ax
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; Восстанавливаем Multiboot info из стека
    pop rdi                          ; Магическое число
    pop rsi                          ; Адрес Multiboot info структуры
    
    ; Вызываем C функцию kernel_main(magic, multiboot_info)
    extern kernel_main
    call kernel_main
    
    ; Если ядро вернуло управление - зависаем
    cli
.hang:
    hlt
    jmp .hang
