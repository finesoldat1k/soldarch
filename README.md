# Soldarch

Live-ISO, которая после загрузки запускает **графический установщик** и ставит обычный
Arch Linux с Hyprland, SDDM, Throne и zapret.

Брендинг Soldarch есть только на ISO. Установленная система — чистый
Arch Linux без брендинга.

## Что получится

- Пользователь `iam` с `sudo`, root заблокирован.
- Хостнейм `arch`, локаль `en_US.UTF-8`, timezone `Europe/Moscow`.
- Раскладки `us,ru`, переключение Alt+Shift.
- Hyprland + SDDM (без автологина), NetworkManager + iwd, PipeWire, fish.
- Разметка: ESP + ext4 `/` + отдельный ext4 `/home` + swap-файл 4G.
- **Опционально: LUKS2 шифрование** `/` и `/home`.
- Офлайн-установка из репозитория внутри ISO.
- **Профили пакетов**: minimal, developer, gaming, full.
- Наборы «Разработка», «Общение», «Медиа», «Офис», «Игры».
- `throne-bin` и `soldarch-zapret` (zapret + конфигурация Snowy-Fluffy).
- **Post-install**: reflector, fwupd, xdg-user-dirs, красивый MOTD.

## Графический установщик (GUI)

После загрузки live-ISO автоматически запускается GTK4-установщик:

1. **Приветствие** — воспроизводится 1-я серия «Атаки титанов» (S1E1, 720p HEVC)
2. **Диск и разметка** — весь диск (GPT: ESP + `/` + `/home`) или существующий раздел (dual-boot)
3. **LUKS2** — опциональное шифрование корня и home
4. **Профиль пакетов** — minimal / developer / gaming / full
5. **Пользователь** — iam, пароль, хостнейм arch, локаль, таймзона
6. **Подтверждение** — сводка параметров + галочка согласия
7. **Установка** — видео продолжает играть, прогресс-бар показывает этапы
8. **Готово** — кнопки «Перезагрузить» / «Выключить»

## Сборка

Нужны `archiso`, `base-devel`, `fakeroot`, `qemu-system-x86_64`,
`edk2-ovmf`, `libisoburn`, `mtools`, `dosfstools`, `grub`, `syslinux`.
Сборка идёт от обычного пользователя, без sudo.

```bash
./scripts/build-repo.sh     # офлайн-репозиторий (долго, качает пакеты)
./scripts/build-iso.sh      # release ISO
./scripts/build-iso.sh test-auto  # тестовая ISO с автоустановкой
```

`build-repo.sh` скачивает свежие базы `core`/`extra`/`multilib`,
считает точный dependency closure, берёт совпавшие пакеты из
`/var/cache/pacman/pkg`, остальные докачивает параллельно, собирает
`throne-bin` и `soldarch-zapret` и создаёт `soldarch.db.tar.gz`.

Готовые ISO появятся в `out/`. Для release создаётся стабильный
symlink `out/soldarch.iso`.

## Установка

### Графическая (GUI)
Обычная загрузка: установщик автоматически открывается на tty1.
Проходите шаги мастера (см. выше).

### CLI (для автоматизации)
```bash
# Интерактивно
soldarch-install

# Автоматически на весь диск
soldarch-install --auto --disk /dev/nvme0n1 --password MyPass123 \
    --profile developer --luks --luks-password LuksPass123 --reboot

# В существующий раздел (UEFI)
soldarch-install --auto --partition /dev/nvme0n1p2 --efi /dev/nvme0n1p1 \
    --password MyPass123 --reboot
```

### Kernel cmdline параметры
```
soldarch.auto=1           # авторежим
soldarch.disk=/dev/vda    # целевой диск (для --disk)
soldarch.partition=/dev/sda5  # целевой раздел (для --partition)
soldarch.efi=/dev/sda1    # ESP (для режима раздела)
soldarch.password=secret  # пароль пользователя
soldarch.profile=minimal|developer|gaming|full  # профиль пакетов
soldarch.luks=1           # включить LUKS2 шифрование
soldarch.luks-password=secret  # пароль LUKS
soldarch.reboot=1|0       # reboot / poweroff после установки
soldarch.autologin=1      # автологин в SDDM (только тесты)
soldarch.serial=1         # serial console (для QEMU)
soldarch.username=iam     # пользователь (фиксирован)
```

## Тест в QEMU

```bash
# Собрать тестовую ISO
./scripts/build-iso.sh test-auto

# UEFI тест
./scripts/test-qemu.sh

# BIOS тест
./scripts/test-qemu.sh bios
```

Тестовая ISO содержит kernel cmdline с автоустановкой на `/dev/vda`.
Логи: `test/serial-install.log` и `test/serial-boot.log`.
Диск `test/disk.qcow2` пересоздаётся при каждом запуске.

## CI/CD (GitHub Actions)

```yaml
# Автоматически при push в main:
# 1. Сборка офлайн-репозитория
# 2. Сборка ISO (test-auto)
# 3. QEMU тесты UEFI + BIOS
# 4. Линтинг shellcheck + ruff (Python)
```

Ручной запуск:
```bash
gh workflow run ci.yml -f test_type=both
```

## Структура

```
.
├── airootfs/
│   ├── usr/local/bin/
│   │   ├── soldarch-install          # CLI установщик
│   │   ├── soldarch-gui-installer    # GUI установщик (GTK4)
│   │   └── lib/                      # общие библиотеки
│   ├── opt/soldarch/
│   │   ├── configs/                  # целевые конфиги (skel, etc)
│   │   ├── packages-target.txt       # список пакетов таргета
│   │   ├── target-setup.sh           # настройка таргета в chroot
│   │   └── repo/                     # офлайн-репозиторий
│   ├── usr/lib/soldarch/
│   │   └── soldarch-postinstall.sh   # post-install скрипт
│   └── usr/lib/systemd/system/
│       └── soldarch-postinstall.service
├── packages/
│   └── soldarch-zapret/              # локальный пакет zapret
├── scripts/
│   ├── build-repo.sh                 # сборка офлайн-репо
│   ├── build-iso.sh                  # сборка ISO (mkarchiso)
│   ├── test-qemu.sh                  # QEMU тесты
│   └── download-anime.sh             # скачивание аниме для ISO
├── docs/
│   └── install.md                    # полное руководство по установке
├── .github/workflows/ci.yml          # GitHub Actions CI
├── grubs/, syslinux/                 # загрузчики
├── profiledef.sh                     # профиль archiso
├── packages.x86_64                   # пакеты live-системы
└── CHANGELOG.md
```

## После установки

### Первая загрузка
1. Извлеките флешку
2. GRUB → **Arch Linux**
3. Пароль LUKS (если включено)
4. SDDM → войдите как `iam`
5. Hyprland с предустановленными конфигами

### Горячие клавиши Hyprland
| Клавиша | Действие |
|---------|----------|
| `SUPER + Enter` | Терминал (foot) |
| `SUPER + R` | Лаунчер (wofi) |
| `SUPER + Q` | Закрыть окно |
| `SUPER + E` | Thunar |
| `SUPER + B` | Firefox |
| `SUPER + 1-0` | Рабочие столы |
| `SUPER + S` | Scratchpad |

### Post-install (автоматически)
- Обновление mirrorlist (`reflector`)
- Создание папок `~/Downloads`, `~/Pictures` и т.д.
- Проверка прошивок (`fwupdmgr`)
- Очистка кэша pacman (3 последние версии)
- Красивый MOTD с IP, uptime, kernel

```bash
sudo pacman -Syu           # обновление системы
journalctl -u soldarch-postinstall  # лог пост-установки
```

## Устранение неполадок

| Проблема | Решение |
|----------|---------|
| Не загружается live-ISO | Отключите Secure Boot, попробуйте BIOS-режим |
| Нет интернета | `systemctl restart NetworkManager` |
| Hyprland не запускается | `journalctl -u sddm`, `~/.local/share/hyprland/hyprland.log` |
| Нет звука | `systemctl --user restart pipewire pipewire-pulse wireplumber` |
| Забыт пароль LUKS | Восстановление невозможно без бэкапа заголовка LUKS |

## Dual-boot с Windows

1. Установите Windows первой (создаст ESP)
2. Загрузитесь в Soldarch live
3. Режим «Существующий раздел» → укажите пустой раздел для `/` и существующий ESP
4. GRUB автоматически добавит Windows

## Обновление

Soldarch после установки — обычный Arch Linux:
```bash
sudo pacman -Syu
```
Конфиги в `~/.config/` не перезаписываются.

## Поддержка

- GitHub Issues: https://github.com/ваш-ник/soldarch/issues
- Документация: `docs/install.md`
- CHANGELOG: `CHANGELOG.md`