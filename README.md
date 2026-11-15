# Soldarch

Live-ISO, которая после загрузки запускает установщик и ставит обычный
Arch Linux с Hyprland, SDDM, Throne и zapret.

Брендинг Soldarch есть только на ISO. Установленная система — чистый
Arch Linux без брендинга.

## Что получится

- Пользователь `iam` с `sudo`, root заблокирован.
- Хостнейм `arch`, локаль `en_US.UTF-8`, timezone `Europe/Moscow`.
- Раскладки `us,ru`, переключение Alt+Shift.
- Hyprland + SDDM (без автологина), NetworkManager + iwd, PipeWire, fish.
- Разметка: ESP + ext4 `/` + отдельный ext4 `/home` + swap-файл 4G.
- Офлайн-установка из репозитория внутри ISO.
- Наборы «Разработка», «Общение», «Медиа», «Офис», «Игры».
- `throne-bin` и `soldarch-zapret` (zapret + конфигурация Snowy-Fluffy).

## Сборка

Нужны `archiso`, `base-devel`, `fakeroot`, `qemu-system-x86_64`,
`edk2-ovmf`, `libisoburn`, `mtools`, `dosfstools`, `grub`, `syslinux`.
Сборка идёт от обычного пользователя, без sudo.

```bash
./scripts/build-repo.sh     # офлайн-репозиторий (долго, качает пакеты)
./scripts/build-iso.sh      # release ISO
```

`build-repo.sh` скачивает свежие базы `core`/`extra`/`multilib`,
считает точный dependency closure, берёт совпавшие пакеты из
`/var/cache/pacman/pkg`, остальные докачивает параллельно, собирает
`throne-bin` и `soldarch-zapret` и создаёт `soldarch.db.tar.gz`.

Готовые ISO появятся в `out/`. Для release создаётся стабильный
symlink `out/soldarch.iso`.

## Установка

Обычная загрузка: установщик автоматически открывается на tty1.
Нужно выбрать диск или существующий раздел, задать пароль и
подтвердить установку. Дальше всё автоматически.

Установка на весь диск стирает его и создаёт ESP + `/` + `/home`.
Установка в существующий раздел форматирует только выбранный раздел,
использует существующий ESP и не трогает остальные разделы.

Авторежим (например, для QEMU):

```bash
soldarch-install --auto --disk /dev/vda --password test \
    --reboot --serial-console
```

Параметры можно передать через kernel cmdline:

```
soldarch.auto=1 soldarch.disk=/dev/vda soldarch.password=test
soldarch.reboot=0 soldarch.serial=1 soldarch.autologin=1
```

`--autologin` нужен только для тестовых прогонов: в обычной установке
SDDM всегда показывает экран входа.

## Тест в QEMU

```bash
./scripts/build-iso.sh test-auto
./scripts/test-qemu.sh          # UEFI
./scripts/test-qemu.sh bios     # BIOS
```

Тестовая ISO содержит kernel cmdline с автоустановкой на `/dev/vda`.
Логи: `test/serial-install.log` и `test/serial-boot.log`.
Диск `test/disk.qcow2` пересоздаётся при каждом запуске.

## Структура

- `airootfs/usr/local/bin/soldarch-install` — установщик и его `lib/`.
- `airootfs/opt/soldarch/` — целевые конфиги, список пакетов, скрипт
  настройки и офлайн-репозиторий.
- `packages/soldarch-zapret/` — локальный пакет zapret.
- `scripts/` — сборка репозитория, ISO и тест QEMU.
- `grub/`, `syslinux/`, `profiledef.sh`, `packages.x86_64` — live-ISO.
