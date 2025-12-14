/*
 * ============================================================================
 * MixOS Kernel - kernel/kernel.c
 * Точка входа ядра операционной системы
 * ============================================================================
 */

#include <stdint.h>
#include <stddef.h>

/* ============================================================================
 * VGA текстовый режим (для отладочного вывода)
 * ============================================================================ */

#define VGA_WIDTH 80
#define VGA_HEIGHT 25
#define VGA_MEMORY 0xB8000

/* Цвета VGA */
enum vga_color {
    VGA_BLACK = 0,
    VGA_BLUE = 1,
    VGA_GREEN = 2,
    VGA_CYAN = 3,
    VGA_RED = 4,
    VGA_MAGENTA = 5,
    VGA_BROWN = 6,
    VGA_LIGHT_GREY = 7,
    VGA_DARK_GREY = 8,
    VGA_LIGHT_BLUE = 9,
    VGA_LIGHT_GREEN = 10,
    VGA_LIGHT_CYAN = 11,
    VGA_LIGHT_RED = 12,
    VGA_LIGHT_MAGENTA = 13,
    VGA_YELLOW = 14,
    VGA_WHITE = 15,
};

/* Создание байта цвета (foreground + background) */
static inline uint8_t vga_entry_color(enum vga_color fg, enum vga_color bg) {
    return fg | bg << 4;
}

/* Создание VGA символа (символ + цвет) */
static inline uint16_t vga_entry(unsigned char c, uint8_t color) {
    return (uint16_t)c | (uint16_t)color << 8;
}

/* Глобальные переменные терминала */
static size_t terminal_row;
static size_t terminal_column;
static uint8_t terminal_color;
static uint16_t* terminal_buffer;

/* Инициализация терминала */
void terminal_initialize(void) {
    terminal_row = 0;
    terminal_column = 0;
    terminal_color = vga_entry_color(VGA_LIGHT_GREY, VGA_BLACK);
    terminal_buffer = (uint16_t*)VGA_MEMORY;
    
    /* Очищаем экран */
    for (size_t y = 0; y < VGA_HEIGHT; y++) {
        for (size_t x = 0; x < VGA_WIDTH; x++) {
            const size_t index = y * VGA_WIDTH + x;
            terminal_buffer[index] = vga_entry(' ', terminal_color);
        }
    }
}

/* Установка цвета терминала */
void terminal_setcolor(uint8_t color) {
    terminal_color = color;
}

/* Вывод символа в указанную позицию */
void terminal_putentryat(char c, uint8_t color, size_t x, size_t y) {
    const size_t index = y * VGA_WIDTH + x;
    terminal_buffer[index] = vga_entry(c, color);
}

/* Прокрутка экрана вверх на одну строку */
void terminal_scroll(void) {
    /* Копируем все строки на одну вверх */
    for (size_t y = 0; y < VGA_HEIGHT - 1; y++) {
        for (size_t x = 0; x < VGA_WIDTH; x++) {
            const size_t src_index = (y + 1) * VGA_WIDTH + x;
            const size_t dst_index = y * VGA_WIDTH + x;
            terminal_buffer[dst_index] = terminal_buffer[src_index];
        }
    }
    
    /* Очищаем последнюю строку */
    for (size_t x = 0; x < VGA_WIDTH; x++) {
        const size_t index = (VGA_HEIGHT - 1) * VGA_WIDTH + x;
        terminal_buffer[index] = vga_entry(' ', terminal_color);
    }
}

/* Вывод одного символа */
void terminal_putchar(char c) {
    /* Обработка специальных символов */
    if (c == '\n') {
        terminal_column = 0;
        if (++terminal_row == VGA_HEIGHT) {
            terminal_row = VGA_HEIGHT - 1;
            terminal_scroll();
        }
        return;
    }
    
    if (c == '\t') {
        terminal_column = (terminal_column + 4) & ~3;
        if (terminal_column >= VGA_WIDTH) {
            terminal_column = 0;
            if (++terminal_row == VGA_HEIGHT) {
                terminal_row = VGA_HEIGHT - 1;
                terminal_scroll();
            }
        }
        return;
    }
    
    /* Обычный символ */
    terminal_putentryat(c, terminal_color, terminal_column, terminal_row);
    
    if (++terminal_column == VGA_WIDTH) {
        terminal_column = 0;
        if (++terminal_row == VGA_HEIGHT) {
            terminal_row = VGA_HEIGHT - 1;
            terminal_scroll();
        }
    }
}

/* Вывод строки */
void terminal_write(const char* data, size_t size) {
    for (size_t i = 0; i < size; i++) {
        terminal_putchar(data[i]);
    }
}

/* Вывод null-terminated строки */
void terminal_writestring(const char* data) {
    size_t len = 0;
    while (data[len]) {
        len++;
    }
    terminal_write(data, len);
}

/* ============================================================================
 * Базовые библиотечные функции (kernel/lib/)
 * ============================================================================ */

/* Длина строки */
size_t strlen(const char* str) {
    size_t len = 0;
    while (str[len]) {
        len++;
    }
    return len;
}

/* Сравнение строк */
int strcmp(const char* s1, const char* s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(unsigned char*)s1 - *(unsigned char*)s2;
}

/* Копирование памяти */
void* memcpy(void* dest, const void* src, size_t n) {
    uint8_t* d = (uint8_t*)dest;
    const uint8_t* s = (const uint8_t*)src;
    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dest;
}

/* Заполнение памяти */
void* memset(void* s, int c, size_t n) {
    uint8_t* p = (uint8_t*)s;
    for (size_t i = 0; i < n; i++) {
        p[i] = (uint8_t)c;
    }
    return s;
}

/* ============================================================================
 * Multiboot2 структуры
 * ============================================================================ */

struct multiboot_tag {
    uint32_t type;
    uint32_t size;
};

struct multiboot_tag_string {
    uint32_t type;
    uint32_t size;
    char string[0];
};

struct multiboot_tag_module {
    uint32_t type;
    uint32_t size;
    uint32_t mod_start;
    uint32_t mod_end;
    char cmdline[0];
};

struct multiboot_tag_basic_meminfo {
    uint32_t type;
    uint32_t size;
    uint32_t mem_lower;
    uint32_t mem_upper;
};

/* ============================================================================
 * Парсинг Multiboot информации
 * ============================================================================ */

void parse_multiboot_info(uint64_t multiboot_addr) {
    struct multiboot_tag* tag;
    
    terminal_writestring("Multiboot information at: 0x");
    // TODO: добавить функцию для вывода hex чисел
    terminal_writestring("\n");
    
    /* Пропускаем первые 8 байт (total_size и reserved) */
    for (tag = (struct multiboot_tag*)(multiboot_addr + 8);
         tag->type != 0;
         tag = (struct multiboot_tag*)((uint8_t*)tag + ((tag->size + 7) & ~7))) {
        
        switch (tag->type) {
            case 1: { /* Boot command line */
                struct multiboot_tag_string* cmd = (struct multiboot_tag_string*)tag;
                terminal_writestring("  Command line: ");
                terminal_writestring(cmd->string);
                terminal_writestring("\n");
                break;
            }
            case 2: { /* Boot loader name */
                struct multiboot_tag_string* loader = (struct multiboot_tag_string*)tag;
                terminal_writestring("  Bootloader: ");
                terminal_writestring(loader->string);
                terminal_writestring("\n");
                break;
            }
            case 4: { /* Basic memory info */
                struct multiboot_tag_basic_meminfo* mem = (struct multiboot_tag_basic_meminfo*)tag;
                terminal_writestring("  Memory detected\n");
                // TODO: вывести количество памяти
                (void)mem; // Убираем warning
                break;
            }
        }
    }
}

/* ============================================================================
 * Главная функция ядра
 * ============================================================================ */

void kernel_main(uint64_t magic, uint64_t multiboot_addr) {
    /* Инициализация терминала */
    terminal_initialize();
    
    /* Приветственное сообщение */
    terminal_setcolor(vga_entry_color(VGA_LIGHT_CYAN, VGA_BLACK));
    terminal_writestring("=================================\n");
    terminal_writestring("    MixOS Kernel v0.1.0\n");
    terminal_writestring("=================================\n\n");
    
    terminal_setcolor(vga_entry_color(VGA_LIGHT_GREY, VGA_BLACK));
    
    /* Проверка Multiboot magic number */
    if (magic != 0x36d76289) {
        terminal_setcolor(vga_entry_color(VGA_LIGHT_RED, VGA_BLACK));
        terminal_writestring("[ERROR] Invalid Multiboot magic number!\n");
        terminal_writestring("System halted.\n");
        goto halt;
    }
    
    terminal_setcolor(vga_entry_color(VGA_LIGHT_GREEN, VGA_BLACK));
    terminal_writestring("[OK] Multiboot2 boot detected\n");
    terminal_setcolor(vga_entry_color(VGA_LIGHT_GREY, VGA_BLACK));
    
    /* Парсинг Multiboot информации */
    terminal_writestring("\n[INFO] Parsing multiboot information...\n");
    parse_multiboot_info(multiboot_addr);
    
    /* Инициализация архитектурно-зависимых модулей */
    terminal_writestring("\n[INFO] Initializing architecture (x86_64)...\n");
    // TODO: arch_init() - GDT, IDT, interrupts
    
    /* Инициализация управления памятью */
    terminal_writestring("[INFO] Initializing memory management...\n");
    // TODO: mm_init() - PMM, VMM, heap
    
    /* Инициализация планировщика */
    terminal_writestring("[INFO] Initializing scheduler...\n");
    // TODO: sched_init()
    
    /* Инициализация драйверов */
    terminal_writestring("[INFO] Initializing drivers...\n");
    // TODO: drivers_init() - timer, keyboard, disk
    
    /* Инициализация файловой системы */
    terminal_writestring("[INFO] Initializing filesystem...\n");
    // TODO: vfs_init(), ramfs_init()
    
    terminal_writestring("\n");
    terminal_setcolor(vga_entry_color(VGA_YELLOW, VGA_BLACK));
    terminal_writestring("[READY] Kernel initialization complete!\n");
    terminal_setcolor(vga_entry_color(VGA_LIGHT_GREY, VGA_BLACK));
    terminal_writestring("\nMixOS is now running in kernel mode.\n");
    terminal_writestring("Next step: implement userspace and system calls.\n");
    
halt:
    /* Бесконечный цикл (пока нет планировщика) */
    while (1) {
        __asm__ volatile ("hlt");
    }
}
