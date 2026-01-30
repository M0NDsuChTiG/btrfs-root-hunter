#!/bin/bash

# =====================================================================
# Btrfs Root Hunter & Rescuer
# Скрипт для поиска живых "корней" файловой системы и восстановления данных
# =====================================================================

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ошибка: Этот скрипт нужно запускать от имени root (sudo).${NC}"
   exit 1
fi

# Проверка аргументов
DEVICE="$1"
DEST_DIR="$2"

if [[ -z "$DEVICE" ]]; then
    echo "Использование: sudo ./btrfs_magic.sh <УСТРОЙСТВО> [ПАПКА_НАЗНАЧЕНИЯ]"
    echo "Пример (только тест):  sudo ./btrfs_magic.sh /dev/sda1"
    echo "Пример (восстановление): sudo ./btrfs_magic.sh /dev/sda1 /media/usb/backup"
    exit 1
fi

# Проверка наличия утилиты
if ! command -v btrfs-find-root &> /dev/null; then
    echo -e "${RED}Ошибка: btrfs-find-root не найден. Установите btrfs-progs.${NC}"
    exit 1
fi

echo -e "${YELLOW}=== Шаг 1: Поиск корней файловой системы на $DEVICE ===${NC}"
echo "Это может занять некоторое время, подождите..."

# Создаем временный файл для списка корней
ROOT_LIST=$(mktemp)

# Запускаем поиск, фильтруем и сортируем по Generation (поколению) от нового к старому.
# Формат вывода btrfs-find-root: "Well block 12345 (gen: 500 level: 1)"
# Мы вытаскиваем: $3 (bytenr), $5 (gen).
btrfs-find-root "$DEVICE" | grep "Well block" | awk '{print $3, $5}' | sed 's/(gen://' | sort -rn -k2 > "$ROOT_LIST"

ROOT_COUNT=$(wc -l < "$ROOT_LIST")

if [[ "$ROOT_COUNT" -eq 0 ]]; then
    echo -e "${RED}К сожалению, btrfs-find-root не нашел ни одного целого заголовка.${NC}"
    rm "$ROOT_LIST"
    exit 1
fi

echo -e "${GREEN}Найдено $ROOT_COUNT потенциальных корней (транзакций).${NC}"
echo "Начинаем проверку от самых новых к старым."
echo "---------------------------------------------------"

# Читаем файл построчно
while read -r bytenr gen; do
    echo -e "\n${YELLOW}>>> Проверяем корень (Generation: $gen, Address: $bytenr)${NC}"
    
    # Тестовый прогон (Dry Run) - показываем первые 20 файлов
    echo "Попытка прочитать список файлов..."
    
    # Используем stdbuf чтобы вывод не буферизировался и мы видели ошибки сразу
    if OUTPUT=$(timeout 10s btrfs restore -D -v -t "$bytenr" "$DEVICE" /dev/null 2>&1 | head -n 20); then
        
        # Показываем, что нашли
        echo -e "${GREEN}Успех! Файловая система читается.${NC} Вот что я вижу:"
        echo "---------------------------------------"
        echo "$OUTPUT"
        echo "..."
        echo "---------------------------------------"
        
        # Если папка назначения не задана, мы просто тестируем
        if [[ -z "$DEST_DIR" ]]; then
            echo -e "${YELLOW}Режим тестирования.${NC} Чтобы восстановить эти файлы, запустите скрипт так:"
            echo "sudo $0 $DEVICE /путь/куда/сохранять"
            read -p "Нажмите Enter, чтобы проверить следующий корень (или Ctrl+C для выхода)..."
        else
            # Режим восстановления
            echo -e "${GREEN}Этот корень выглядит живым!${NC}"
            read -p "Хотите начать ПОЛНОЕ восстановление с этого момента? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                echo -e "${YELLOW}Начинаю восстановление в $DEST_DIR...${NC}"
                mkdir -p "$DEST_DIR"
                
                # Запуск реального восстановления
                btrfs restore -v -t "$bytenr" --path-regex '^/(|home|etc|var/www)' "$DEVICE" "$DEST_DIR"
                
                if [[ $? -eq 0 ]]; then
                    echo -e "${GREEN}Восстановление завершено успешно!${NC}"
                    rm "$ROOT_LIST"
                    exit 0
                else
                    echo -e "${RED}Произошла ошибка при копировании.${NC} Пробуем следующий корень?"
                    read -p "Enter - продолжить, Ctrl+C - выход."
                fi
            else
                echo "Пропускаем, ищем дальше..."
            fi
        fi

    else
        echo -e "${RED}Ошибка чтения этого корня (Checksum error или Metadata corruption).${NC}"
        # Вывод ошибки для отладки, если нужно
        # echo "$OUTPUT" 
    fi

done < "$ROOT_LIST"

echo "Список корней закончился."
rm "$ROOT_LIST"
