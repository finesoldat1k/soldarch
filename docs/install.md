# Soldarch — Установка

Руководство по установке Soldarch Linux на физическое железо или виртуальную машину.

## Требования

| Компонент | Минимум | Рекомендуется |
|-----------|---------|---------------|
| CPU | x86_64 (2 ядра) | 4+ ядер |
| RAM | 2 ГБ | 8+ ГБ |
| Диск | 32 ГБ | 64+ ГБ (NVMe) |
| Видео | Любое (KMS) | Intel/AMD GPU с Vulkan |
| UEFI | Опционально | Да (рекомендуется) |

> **Важно**: Установка **полностью стирает** выбранный диск. Сохраните важные данные заранее.

---

## Скачивание и запись ISO

```bash
# Скачайте последнюю версию с GitHub Releases
wget https://github.com/ваш-ник/soldarch/releases/latest/download/soldarch-<date>-x86_64.iso

# Проверьте контрольную сумму
sha256sum soldarch-*.iso

# Запишите на флешку (замените /dev/sdX на вашу флешку!)
sudo dd if=soldarch-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## Загрузка

1. Вставьте флешку и перезагрузитесь
2. В BIOS/UEFI выберите загрузку с USB
3. В меню GRUB выберите **Soldarch Linux** (или нажмите Enter)
4. Система загрузится в live-окружение с автозапуском установщика

### Режимы загрузки

| Параметр kernel cmdline | Описание |
|-------------------------|----------|
| `soldarch.auto=1` | Автоустановка (требует `soldarch.disk` и `soldarch.password`) |
| `soldarch.disk=/dev/nvme0n1` | Целевой диск для автоустановки |
| `soldarch.password=secret` | Пароль пользователя `iam` |
| `soldarch.profile=minimal\|developer\|gaming\|full` | Профиль пакетов (default: minimal) |
| `soldarch.luks=1` | Включить LUKS2 шифрование |
| `soldarch.luks-password=secret` | Пароль для LUKS |
| `soldarch.username=iam` | Имя пользователя |
| `soldarch.hostname=arch` | Хостнейм |
| `soldarch.locale=en_US.UTF-8` | Локаль |
| `soldarch.timezone=Europe/Moscow` | Часовой пояс |
| `soldarch.gui=0` | Не запускать GUI, сразу открыть TUI |
| `soldarch.autologin=1` | Автологин в SDDM (только для тестов) |
| `soldarch.serial=1` | Включить serial console (для QEMU) |

Пример для автоматизации:
```bash
kernel cmdline: soldarch.auto=1 soldarch.disk=/dev/nvme0n1 soldarch.password=MyPass123 soldarch.profile=developer soldarch.luks=1 soldarch.luks-password=LuksPass123 soldarch.reboot=1
```

---

## Графический установщик (GUI)

После загрузки live-системы на tty1 автоматически запускается графический
установщик внутри kiosk-композитора `cage`. Если композитор или GUI
недоступны, открывается TUI-установщик. Принудительно выбрать TUI можно
параметром `soldarch.gui=0`.

### 1. Приветствие
- Воспроизводится открытый мультфильм «Big Buck Bunny» (720p, CC BY 3.0)
- Кнопка «Без звука» отключает звук
- Нажмите **«Начать установку»**

### 2. Выбор диска и разметка
- **Весь диск** — автоматическая GPT разметка:
  - ESP (1 GiB, FAT32)
  - `/` (ext4, до 60 GiB или половина диска)
  - `/home` (ext4, остальное место)
  - Swap-файл 4 GiB на корневом разделе
- **Существующий раздел** — dual-boot режим (только UEFI):
  - Выбираете существующий корневой раздел (форматируется)
  - Выбираете существующий ESP (не форматируется)
  - Остальные разделы не трогаются
- **LUKS2 шифрование** (опционально, только для всего диска):
  - Шифрует `/` и `/home` отдельными контейнерами
  - Требует пароль при каждой загрузке
  - ESP остаётся незашифрованным и монтируется в `/boot`

### 3. Профиль пакетов
| Профиль | Размер | Содержимое |
|---------|--------|------------|
| **Стандарт** (~7 GiB) | Базовая система + Hyprland + SDDM + waybar + foot + wofi + mako + NetworkManager + PipeWire + fish + throne-bin + zapret |
| **Разработка** (~10 GiB) | Стандарт + base-devel, git, Docker, Podman, VS Code, Node.js, Python, Rust, Go, Zig, CMake, GDB |
| **Игры** (~11 GiB) | Стандарт + Steam, Lutris, Wine, gamemode, MangoHud, gamescope, DXVK, VKD3D |
| **Всё вместе** (~14 GiB) | Стандарт + разработка + игры |

Списки пакетов лежат в `airootfs/opt/soldarch/packages-target.txt`,
`packages-developer.txt` и `packages-gaming.txt`.

### 4. Пользователь и сеть
- Пользователь: **iam** (фиксировано)
- Пароль: минимум 8 символов
- Хостнейм: **arch** (фиксировано)
- Локаль: en_US.UTF-8 / ru_RU.UTF-8
- Таймзона: Europe/Moscow (или другая)
- Раскладки: us,ru (Alt+Shift)

### 5. Подтверждение и установка
- Проверьте сводку параметров
- Поставьте галочку согласия
- Нажмите **«Установить»**

### 6. Процесс установки
- Видео продолжает играть
- Прогресс-бар показывает этапы:
  1. Установка пакетов (pacstrap)
  2. Копирование конфигурации
  3. Установка GRUB
  4. Проверка системы
- При успехе — кнопки «Перезагрузить» / «Выключить»

---

## После установки

### Первая загрузка
1. Извлеките флешку
2. Загрузитесь в GRUB → **Arch Linux**
3. Введите пароль LUKS (если включено)
4. SDDM покажет экран входа
5. Войдите как `iam` с вашим паролем
6. Hyprland запустится с настройками Soldarch

### Горячие клавиши Hyprland (по умолчанию)

| Клавиша | Действие |
|---------|----------|
| `SUPER + Enter` | Терминал (foot) |
| `SUPER + R` | Лаунчер (wofi) |
| `SUPER + Q` | Закрыть окно |
| `SUPER + E` | Файловый менеджер (thunar) |
| `SUPER + B` | Браузер (firefox) |
| `SUPER + V` | Переключить плавающее |
| `SUPER + F` | Полноэкранный режим |
| `SUPER + 1-0` | Рабочие столы |
| `SUPER + SHIFT + 1-0` | Переместить окно на стол |
| `SUPER + S` | Специальный рабочий стол (scratchpad) |
| `SUPER + колесо` | Переключение столов |
| `SUPER + LMB` | Перетаскивание окна |
| `SUPER + RMB` | Изменение размера |

### Пост-установка (автоматически при первой загрузке)
Скрипт `soldarch-postinstall` выполняет:
- Обновление mirrorlist через `reflector`
- Создание пользовательских папок (`~/Downloads`, `~/Pictures` и т.д.)
- Проверку обновлений прошивок (`fwupdmgr`)
- Очистку кэша pacman (остаются 3 последние версии)
- Генерацию красивого MOTD

### Полезные команды

```bash
# Обновление системы
sudo pacman -Syu

# Поиск пакетов
pacman -Ss <запрос>
yay -Ss <запрос>  # если установлен AUR-хелпер

# Логи установки
cat /tmp/soldarch-install.log       # в live-системе, во время установки
cat /var/log/soldarch-postinstall.log  # после первой загрузки

# Статус zapret
systemctl status zapret

# Перезапуск Hyprland (без выхода из сессии)
hyprctl reload
```

---

## Устранение неполадок

| Проблема | Решение |
|----------|---------|
| Не загружается live-ISO | Проверьте Secure Boot (отключите), попробуйте BIOS-режим |
| Нет интернета после установки | `systemctl restart NetworkManager`, проверьте `ip a` |
| Hyprland не запускается | Проверьте логи: `journalctl -u sddm`, `~/.local/share/hyprland/hyprland.log` |
| Нет звука | `systemctl --user restart pipewire pipewire-pulse wireplumber` |
| Забыт пароль LUKS | Восстановление невозможно без бэкапа заголовка LUKS |
| Ошибка GRUB при установке | Убедитесь, что диск не GPT+BIOS без bios_grub раздела |
| Чёрный экран вместо GUI | Проверьте `/tmp/soldarch-gui.log`; загрузитесь с `soldarch.gui=0` для TUI |

---

## Dual-boot с Windows

1. Установите Windows первой (она создаст ESP)
2. Загрузитесь в Soldarch live
3. Выберите режим **«Существующий раздел»**
4. Укажите пустой раздел для `/` и существующий ESP
5. GRUB можно дополнительно настроить для Windows: включите `os-prober`
   в `/etc/default/grub` (`GRUB_DISABLE_OS_PROBER=false`) и выполните
   `sudo grub-mkconfig -o /boot/grub/grub.cfg`

---

## Обновление Soldarch

Soldarch — это **обычный Arch Linux** после установки. Обновляйте стандартными средствами:

```bash
sudo pacman -Syu
```

Конфигурации Hyprland/waybar/foot и т.д. лежат в `~/.config/` и не перезаписываются при обновлении.

---

## Поддержка

- GitHub Issues: https://github.com/ваш-ник/soldarch/issues
- Документация: https://github.com/ваш-ник/soldarch/wiki
- Telegram: https://t.me/soldarch_chat