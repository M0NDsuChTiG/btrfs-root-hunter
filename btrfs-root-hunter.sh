#!/bin/bash

# btrfs-root-hunter: A script to find, manage, mount, unmount, and snapshot btrfs subvolumes.

set -e
set -o pipefail

# --- Глобальные массивы для хранения найденных данных ---
declare -a MENU_OPTIONS=()
declare -a SUBVOL_DEVICES=()
declare -a SUBVOL_IDS=()
declare -a SUBVOL_PATHS=()

# --- Dependency Check ---
check_dependencies() {
    local missing=0
    for cmd in btrfs lsblk blkid mount umount awk; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required command '$cmd' not found." >&2
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        echo "Please install the necessary packages (e.g., btrfs-progs, util-linux) and try again." >&2
        exit 1
    fi
}

# --- Functions ---

find_btrfs_subvolumes() {
    local device=$1
    local temp_mount
    temp_mount=$(mktemp -d -t btrfs-hunter-XXXXXX)

    trap 'umount "$temp_mount" &>/dev/null || true; rmdir "$temp_mount" &>/dev/null || true' RETURN

    if ! mount -o ro,subvolid=0 "$device" "$temp_mount" &>/dev/null; then
        return
    fi

    while IFS='|' read -r id path; do
        printf "     - ID: %-5s Path: %-30s Device: %s\n" "$id" "$path" "$device"
        
        MENU_OPTIONS+=("Device: $device | ID: $id | Path: $path")
        SUBVOL_DEVICES+=("$device")
        SUBVOL_IDS+=("$id")
        SUBVOL_PATHS+=("$path")
    done < <(btrfs subvolume list -p "$temp_mount" | awk '{
        id=$2;
        path="";
        for (i=9; i<=NF; i++) {
            path = path (i==9 ? "" : " ") $i
        }
        print id "|" path
    }')
}

interactive_snapshot_menu() {
    echo ""
    echo "------------------------------------------"
    echo "       Создание снапшота (Snapshot)       "
    echo "------------------------------------------"

    PS3="Выберите сабволум для создания снапшота (или 'q' для возврата): "
    select opt in "${MENU_OPTIONS[@]}"; do
        if [[ "$REPLY" == "q" || "$REPLY" == "Q" ]]; then
            break
        elif [[ -n "$opt" ]]; then
            local index=$((REPLY - 1))
            local dev="${SUBVOL_DEVICES[$index]}"
            local id="${SUBVOL_IDS[$index]}"
            local path="${SUBVOL_PATHS[$index]}"

            echo ""
            read -p "Введите имя для нового снапшота (без пробелов, например 'backup-root'): " snap_name

            if [[ -z "$snap_name" ]]; then
                echo "Ошибка: Имя снапшота не может быть пустым."
                break
            fi

            # Создаем временную директорию для монтирования корня Btrfs (id=5)
            local temp_mount
            temp_mount=$(mktemp -d -t btrfs-snap-XXXXXX)

            echo "Временное монтирование корня $dev для создания снапшота..."
            # Монтируем корень файловой системы (subvolid=5 - это верхний уровень в btrfs по умолчанию)
            if mount -o subvolid=5 "$dev" "$temp_mount"; then
                # Полный путь до оригинального сабволума и будущего снапшота
                local src_dir="$temp_mount/$path"
                local dest_dir="$temp_mount/$snap_name"

                if [[ ! -d "$src_dir" ]]; then
                    echo "❌ Ошибка: Исходный сабволум не найден по пути $src_dir."
                elif [[ -e "$dest_dir" ]]; then
                    echo "❌ Ошибка: Директория или файл '$snap_name' уже существует в корне файловой системы!"
                else
                    echo "Создание снапшота '$snap_name' из '$path'..."
                    if btrfs subvolume snapshot "$src_dir" "$dest_dir"; then
                        echo -e "\n✅ Снапшот '$snap_name' успешно создан на устройстве $dev!"
                    else
                        echo -e "\n❌ Произошла ошибка при создании снапшота."
                    fi
                fi
                
                # Убираем за собой
                umount "$temp_mount"
            else
                echo "❌ Не удалось примонтировать корень устройства $dev."
            fi
            
            rmdir "$temp_mount" &>/dev/null || true
            
            # Предлагаем пересканировать диски, чтобы новый снапшот появился в списке
            echo ""
            read -p "Пересканировать диски, чтобы обновить список? [Y/n]: " rescan
            rescan=${rescan:-Y}
            if [[ "$rescan" =~ ^[Yy]$ ]]; then
                MENU_OPTIONS=()
                SUBVOL_DEVICES=()
                SUBVOL_IDS=()
                SUBVOL_PATHS=()
                echo "Сканирование..."
                readarray -t devices < <(lsblk -l -n -o NAME,TYPE | awk '$2 ~ /part|disk/ {print "/dev/"$1}')
                for device in "${devices[@]}"; do
                    if [[ "$(blkid -s TYPE -o value "$device" 2>/dev/null)" == "btrfs" ]]; then
                        find_btrfs_subvolumes "$device" >/dev/null
                    fi
                done
            fi
            break
        else
            echo "Неверный выбор. Пожалуйста, введите номер из списка."
        fi
    done
}

interactive_unmount_menu() {
    echo ""
    echo "------------------------------------------"
    echo "       Интерактивное размонтирование      "
    echo "------------------------------------------"

    readarray -t mounted_btrfs < <(mount -t btrfs | awk '{print $3 " (from " $1 ")"}')

    if [[ ${#mounted_btrfs[@]} -eq 0 ]]; then
        echo "Не найдено примонтированных Btrfs файловых систем."
        read -n 1 -s -r -p "Нажмите любую клавишу для возврата в главное меню..."
        echo
        return
    fi

    PS3="Выберите, что размонтировать (или 'q' для возврата): "
    select mount_point_info in "${mounted_btrfs[@]}"; do
        if [[ "$REPLY" == "q" || "$REPLY" == "Q" ]]; then
            break
        elif [[ -n "$mount_point_info" ]]; then
            local mount_point
            mount_point=$(echo "$mount_point_info" | awk '{print $1}')

            echo "Размонтирование $mount_point..."
            if umount "$mount_point"; then
                echo -e "\n✅ Успешно размонтировано!"
            else
                echo -e "\n❌ Ошибка при размонтировании. Возможно, точка монтирования занята."
            fi
            break
        else
            echo "Неверный выбор. Пожалуйста, введите номер из списка."
        fi
    done
}

interactive_menu() {
    while true; do
        local main_menu_options=()
        
        # Добавляем опцию монтирования только если что-то нашли
        if [[ ${#MENU_OPTIONS[@]} -gt 0 ]]; then
            main_menu_options+=("Примонтировать найденный сабволум")
            main_menu_options+=("Создать снапшот (snapshot) сабволума")
            main_menu_options+=("---")
        fi
        
        main_menu_options+=("Размонтировать файловую систему")
        main_menu_options+=("Выход")

        echo ""
        echo "=========================================="
        echo "            Главное меню                  "
        echo "=========================================="
        
        PS3="Выберите действие: "

        select opt in "${main_menu_options[@]}"; do
            if [[ "$opt" == "Выход" ]]; then
                echo "Завершение работы."
                return
            
            elif [[ "$opt" == "Размонтировать файловую систему" ]]; then
                interactive_unmount_menu
                break

            elif [[ "$opt" == "Создать снапшот (snapshot) сабволума" ]]; then
                interactive_snapshot_menu
                break

            elif [[ "$opt" == "Примонтировать найденный сабволум" ]]; then
                echo ""
                PS3="Выберите сабволум для монтирования (или 'q' для отмены): "
                select sub_opt in "${MENU_OPTIONS[@]}"; do
                    if [[ "$REPLY" == "q" || "$REPLY" == "Q" ]]; then
                        break
                    elif [[ -n "$sub_opt" ]]; then
                        local index=$((REPLY - 1))
                        local dev="${SUBVOL_DEVICES[$index]}"
                        local id="${SUBVOL_IDS[$index]}"
                        
                        echo ""
                        read -p "Введите точку монтирования (например, /mnt/recovery): " mount_point

                        if [[ -z "$mount_point" ]]; then
                            echo "Ошибка: Точка монтирования не может быть пустой."
                            break
                        fi

                        if [[ ! -d "$mount_point" ]]; then
                            read -p "Директория '$mount_point' не существует. Создать её? [Y/n]: " create_dir
                            create_dir=${create_dir:-Y}
                            if [[ "$create_dir" =~ ^[Yy]$ ]]; then
                                mkdir -p "$mount_point" || { echo "Ошибка: Не удалось создать директорию."; break; }
                            else
                                echo "Отмена монтирования."
                                break
                            fi
                        fi

                        echo "Монтируем $dev (subvolid=$id) в $mount_point ..."
                        if mount -o subvolid="$id" "$dev" "$mount_point"; then
                            echo -e "\n✅ Успешно примонтировано!"
                            echo "Просмотр файлов: ls -l $mount_point"
                        else
                            echo -e "\n❌ Ошибка при монтировании."
                        fi
                        break
                    else
                        echo "Неверный выбор."
                    fi
                done
                break # Возврат в главное меню
            elif [[ "$opt" == "---" ]]; then
                echo "Неверный выбор."
                break
            else
                echo "Неверный выбор. Пожалуйста, введите номер из списка."
                break
            fi
        done
    done
}

# --- Main Logic ---

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "Этот скрипт необходимо запускать с правами root (sudo)."
        exit 1
    fi

    check_dependencies

    echo "Поиск файловых систем btrfs на всех блочных устройствах..."

    readarray -t devices < <(lsblk -l -n -o NAME,TYPE | awk '$2 ~ /part|disk/ {print "/dev/"$1}')

    local found_any=0
    for device in "${devices[@]}"; do
        local fs_type
        fs_type=$(blkid -s TYPE -o value "$device" 2>/dev/null || echo "")

        if [[ "$fs_type" == "btrfs" ]]; then
            echo "-> Сканирование устройства: $device"
            find_btrfs_subvolumes "$device"
            found_any=1
        fi
    done

    if [[ $found_any -eq 0 ]]; then
        echo "Новых файловых систем btrfs для монтирования не найдено."
    fi

    interactive_menu

    echo "Работа скрипта завершена."
}

# Run the main function
main "$@"
