# Changelog

Все заметные изменения в проекте Soldarch.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/),
проект следует [Semantic Versioning](https://semver.org/lang/ru/).

---

## [1.0.0] - 2026-11-18

### Added
- **Графический установщик (GUI)** на GTK4 + GStreamer, запускается в kiosk-композиторе
  `cage` на tty1; при недоступности GUI автоматически открывается TUI
- Воспроизведение открытого мультфильма «Big Buck Bunny» (720p, CC BY 3.0)
  на экранах приветствия и установки; кнопка «Без звука»
- **LUKS2 шифрование** корневого раздела и /home отдельными контейнерами;
  ESP монтируется в `/boot`, чтобы GRUB мог загрузить ядро и initramfs
- **Профили пакетов**: Стандарт, Разработка, Игры, Всё вместе
  (`packages-target.txt`, `packages-developer.txt`, `packages-gaming.txt`)
- **Post-install systemd unit** (`soldarch-postinstall.service`):
  - Обновление mirrorlist через reflector
  - Создание XDG пользовательских директорий
  - Проверка обновлений прошивок (fwupdmgr)
  - Еженедельный fstrim
  - Очистка кэша pacman
  - Генерация MOTD
- **GitHub Actions CI/CD**:
  - Сборка офлайн-репозитория
  - Сборка ISO (test-auto)
  - QEMU тесты UEFI и BIOS
  - Линтинг shell-скриптов (shellcheck) и Python (ruff)
- Документация: `docs/install.md` с полным руководством
- Скрипт `scripts/download-video.sh` для загрузки открытого видео
- Поддержка `xdg-user-dirs`, `reflector`, `fwupd` в целевой системе

### Changed
- **Hyprland 0.57**: конфиг мигрирован с `hyprland.conf` на `hyprland.lua`
- **foot**: секция `[colors]` переименована в `[colors-dark]`
- **build-iso.sh**: принудительная очистка work-директории перед сборкой
- **test-qemu.sh**: ожидание `arch login:` в serial вместо полного таймаута
- CLI установщик (`soldarch-install`): новые аргументы `--profile`, `--luks`,
  `--luks-password`, `--username`, `--hostname`, `--locale`, `--timezone`, `--no-reboot`
- Режим раздела форматирует только выбранный корень; ESP не форматируется
- GUI-установщик вызывает CLI с `--auto --no-reboot` и сам показывает результат

### Fixed
- GUI-установщик больше не падает с `SyntaxError` и корректно заполняет конфигурацию
- В live-ISO добавлены `cage`, GTK4, GStreamer и `gst-plugin-gtk`
- Автозапуск GUI на tty1 с откатом на TUI; повторный TUI не запускается
  после завершения GUI (защита от случайной переустановки)
- GRUB корректно генерируется для LUKS (`cryptdevice` параметр)
- mkinitcpio ставит `encrypt` до `filesystems`
- `--yes --no-reboot` не перезагружает систему

### Removed
- Старый `hyprland.conf` (несовместим с Hyprland 0.57+)
- Защищённое авторским правом видео и скрипт `download-anime.sh`

---

## [0.9.0] - 2026-11-15

### Added
- Базовая TUI установка с авторежимом (`soldarch.auto=1`)
- Офлайн-репозиторий (936 пакетов, 2.5 GiB)
- Локальные пакеты: `throne-bin`, `soldarch-zapret` (v72.13 + списки Snowy-Fluffy)
- UEFI (GRUB) + BIOS (syslinux) загрузка
- Пользователь `iam`, хостнейм `arch`, root заблокирован, sudo для wheel
- Hyprland + SDDM + waybar + foot + wofi + mako + NetworkManager + iwd + PipeWire
- fish shell, раскладки us/ru (Alt+Shift), locale en_US.UTF-8, timezone Europe/Moscow
- Разметка: ESP + ext4 / + ext4 /home + swapfile 4G
- Предустановленные наборы: разработка, общение, медиа, офис, игры
- QEMU тесты UEFI и BIOS с serial логированием

### Fixed
- Удалены лишние nvidia/egl пакеты из репозитория
- Добавлены lib32-vulkan-* и vulkan-swrast для игр
- ROOT_MIN_MB = 24 GiB, HOME_MIN_MB = 6 GiB

---

## [0.1.0] - 2026-11-10

### Added
- Инициализация проекта
- Базовая структура: airootfs, scripts, profiledef.sh, packages.x86_64
- Первый рабочий прототип ISO

---

## Планируемые изменения (roadmap)

### v1.1.0
- [ ] Поддержка Btrfs + снапшоты (snapper)
- [ ] TPM2 + systemd-homed для LUKS
- [ ] Ventoy-совместимый образ
- [ ] Локализация установщика (EN/RU переключатель в GUI)

### v1.2.0
- [ ] AUR-хелпер (yay/paru) опционально
- [ ] Профиль "Server" (headless, docker, k8s)
- [ ] Автоматическое определение видеодрайверов
- [ ] Интеграция с Timeshift/Borg для бэкапов

### v2.0.0
- [ ] Web-based установщик (опционально, для удалённой установки)
- [ ] Поддержка ARM64 (Raspberry Pi, Apple Silicon)
- [ ] Immutable-вариант (snapper + read-only root)