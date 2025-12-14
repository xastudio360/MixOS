# ============================================================================
# MixOS Makefile
# Сборка ядра, создание ISO образа и запуск в QEMU
# ============================================================================

# Компиляторы и инструменты
AS := nasm
CC := gcc
LD := ld

# Флаги для NASM (Intel синтаксис, ELF64 формат)
ASFLAGS := -f elf64

# Флаги для GCC (кросс-компиляция для bare metal x86_64)
CFLAGS := -std=c11 \
          -ffreestanding \
          -fno-stack-protector \
          -fno-pic \
          -mno-red-zone \
          -mno-mmx \
          -mno-sse \
          -mno-sse2 \
          -mcmodel=kernel \
          -Wall \
          -Wextra \
          -O2

# Флаги для линкера
LDFLAGS := -n \
           -T linker.ld \
           -nostdlib

# Директории проекта
BUILD_DIR := build
BOOT_DIR := boot
KERNEL_DIR := kernel
ISO_DIR := isofiles

# Исходные файлы
ASM_SOURCES := $(BOOT_DIR)/boot.asm
C_SOURCES := $(KERNEL_DIR)/kernel.c

# Объектные файлы
ASM_OBJECTS := $(BUILD_DIR)/boot.o
C_OBJECTS := $(BUILD_DIR)/kernel.o

ALL_OBJECTS := $(ASM_OBJECTS) $(C_OBJECTS)

# Итоговые файлы
KERNEL_BIN := $(BUILD_DIR)/mixos.bin
ISO_FILE := $(BUILD_DIR)/mixos.iso

# ============================================================================
# Основные цели
# ============================================================================

.PHONY: all clean run iso

# Сборка всего проекта
all: $(KERNEL_BIN)

# Сборка ISO образа
iso: $(ISO_FILE)

# Запуск в QEMU
run: $(ISO_FILE)
	@echo "[RUN] Starting MixOS in QEMU..."
	qemu-system-x86_64 -cdrom $(ISO_FILE) -m 512M

# Запуск с отладочной информацией
debug: $(ISO_FILE)
	@echo "[DEBUG] Starting MixOS with QEMU debugger..."
	qemu-system-x86_64 -cdrom $(ISO_FILE) -m 512M -d int -no-reboot

# ============================================================================
# Компиляция
# ============================================================================

# Создание директории для сборки
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Компиляция загрузчика (ASM -> OBJ)
$(ASM_OBJECTS): $(ASM_SOURCES) | $(BUILD_DIR)
	@echo "[ASM] $<"
	@$(AS) $(ASFLAGS) $< -o $@

# Компиляция ядра (C -> OBJ)
$(BUILD_DIR)/%.o: $(KERNEL_DIR)/%.c | $(BUILD_DIR)
	@echo "[CC]  $<"
	@$(CC) $(CFLAGS) -c $< -o $@

# Линковка (OBJ -> BIN)
$(KERNEL_BIN): $(ALL_OBJECTS) linker.ld
	@echo "[LD]  Linking kernel..."
	@$(LD) $(LDFLAGS) $(ALL_OBJECTS) -o $@
	@echo "[OK]  Kernel built: $(KERNEL_BIN)"

# ============================================================================
# Создание загрузочного ISO образа
# ============================================================================

$(ISO_FILE): $(KERNEL_BIN)
	@echo "[ISO] Creating bootable ISO image..."
	@mkdir -p $(ISO_DIR)/boot/grub
	@cp $(KERNEL_BIN) $(ISO_DIR)/boot/mixos.bin
	@echo 'set timeout=0'                          > $(ISO_DIR)/boot/grub/grub.cfg
	@echo 'set default=0'                         >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo ''                                      >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo 'menuentry "MixOS" {'                   >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '    multiboot2 /boot/mixos.bin'       >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '    boot'                              >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '}'                                     >> $(ISO_DIR)/boot/grub/grub.cfg
	@grub-mkrescue -o $(ISO_FILE) $(ISO_DIR) 2>/dev/null
	@echo "[OK]  ISO image created: $(ISO_FILE)"

# ============================================================================
# Утилиты
# ============================================================================

# Очистка сборки
clean:
	@echo "[CLEAN] Removing build files..."
	@rm -rf $(BUILD_DIR) $(ISO_DIR)

# Проверка установленных инструментов
check:
	@echo "Checking build tools..."
	@which $(AS) > /dev/null && echo "  [OK] NASM found" || echo "  [FAIL] NASM not found"
	@which $(CC) > /dev/null && echo "  [OK] GCC found" || echo "  [FAIL] GCC not found"
	@which $(LD) > /dev/null && echo "  [OK] LD found" || echo "  [FAIL] LD not found"
	@which grub-mkrescue > /dev/null && echo "  [OK] GRUB found" || echo "  [FAIL] GRUB not found"
	@which qemu-system-x86_64 > /dev/null && echo "  [OK] QEMU found" || echo "  [FAIL] QEMU not found"

# Показать размер ядра
size: $(KERNEL_BIN)
	@echo "Kernel size:"
	@size $(KERNEL_BIN)

# Дамп ассемблерного кода
disasm: $(KERNEL_BIN)
	@objdump -d $(KERNEL_BIN) | less

# Помощь
help:
	@echo "MixOS Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make all    - Build kernel binary"
	@echo "  make iso    - Create bootable ISO image"
	@echo "  make run    - Build and run in QEMU"
	@echo "  make debug  - Run with QEMU debugging output"
	@echo "  make clean  - Remove build files"
	@echo "  make check  - Check if build tools are installed"
	@echo "  make size   - Show kernel binary size"
	@echo "  make disasm - Disassemble kernel binary"
	@echo "  make help   - Show this message"
