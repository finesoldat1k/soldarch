#!/usr/bin/env python3
"""soldarch-gui-installer — графический установщик Soldarch.

Запускается в live-ISO внутри kiosk-композитора cage.
Настройки собираются в dict и передаются CLI-установщику
``soldarch-install --auto ...``; сам GUI не форматирует диски.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any, Dict, List, Optional

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gio", "2.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

VIDEO_PATH = Path(
    os.environ.get(
        "SOLDARCH_VIDEO", "/usr/share/soldarch/video/soldarch-intro.mp4"
    )
)
THEME_PATH = Path(
    os.environ.get("SOLDARCH_THEME", "/usr/share/soldarch/gui/theme.css")
)
INSTALLER = "/usr/local/bin/soldarch-install"
LOG_PATH = Path("/tmp/soldarch-install.log")

PROFILES: Dict[str, Dict[str, Any]] = {
    "minimal": {
        "name": "Стандарт",
        "desc": "Рабочий стол Hyprland, браузер, общение, медиа и офис",
        "size": "≈ 7 ГиБ",
    },
    "developer": {
        "name": "Разработка",
        "desc": "Стандарт + компиляторы, Docker, VS Code, Python, Rust, Go",
        "size": "≈ 10 ГиБ",
    },
    "gaming": {
        "name": "Игры",
        "desc": "Стандарт + Steam, Lutris, Wine, MangoHud, DXVK/VKD3D",
        "size": "≈ 11 ГиБ",
    },
    "full": {
        "name": "Всё вместе",
        "desc": "Стандарт + разработка + игры",
        "size": "≈ 14 ГиБ",
    },
}

TIMEZONES = [
    "Europe/Moscow",
    "Europe/Kaliningrad",
    "Europe/Samara",
    "Asia/Yekaterinburg",
    "Asia/Omsk",
    "Asia/Krasnoyarsk",
    "Asia/Irkutsk",
    "Asia/Yakutsk",
    "Asia/Vladivostok",
    "Asia/Magadan",
    "Asia/Kamchatka",
]

LOCALES = [
    ("en_US.UTF-8", "English (US)"),
    ("ru_RU.UTF-8", "Русский"),
]

ESP_GUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


# ─────────────────────────────────────────────────────────────
# Утилиты
# ─────────────────────────────────────────────────────────────

def run(cmd: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def human_size(num: int) -> str:
    size = float(num)
    for unit in ("Б", "КиБ", "МиБ", "ГиБ", "ТиБ"):
        if size < 1024 or unit == "ТиБ":
            return f"{size:.0f} {unit}" if unit == "Б" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{num} Б"


def get_disks() -> List[Dict[str, Any]]:
    proc = run(["lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,MODEL,TRAN"])
    if proc.returncode != 0:
        return []
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []

    disks: List[Dict[str, Any]] = []
    for dev in data.get("blockdevices", []):
        if dev.get("type") != "disk":
            continue
        name = dev.get("name", "")
        if name.startswith(("loop", "sr", "zram", "ram", "dm-", "md")):
            continue
        disks.append(
            {
                "name": f"/dev/{name}",
                "size": int(dev.get("size") or 0),
                "model": (dev.get("model") or "Неизвестная модель").strip(),
                "tran": dev.get("tran") or "—",
            }
        )
    return disks


def get_partitions(disk: str) -> List[Dict[str, Any]]:
    proc = run(
        [
            "lsblk",
            "-J",
            "-b",
            "-o",
            "NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,PARTTYPE",
            disk,
        ]
    )
    if proc.returncode != 0:
        return []
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []

    parts: List[Dict[str, Any]] = []
    for dev in data.get("blockdevices", []):
        for child in dev.get("children") or []:
            parts.append(
                {
                    "name": f"/dev/{child['name']}",
                    "size": int(child.get("size") or 0),
                    "fstype": child.get("fstype"),
                    "mountpoint": child.get("mountpoint"),
                    "label": child.get("label"),
                    "parttype": (child.get("parttype") or "").lower(),
                }
            )
    return parts


def clear_box(box: Gtk.Box) -> None:
    child = box.get_first_child()
    while child is not None:
        nxt = child.get_next_sibling()
        box.remove(child)
        child = nxt


def label(text: str, css: Optional[str] = None, wrap: bool = False) -> Gtk.Label:
    widget = Gtk.Label(label=text)
    widget.set_halign(Gtk.Align.START)
    widget.set_xalign(0)
    if wrap:
        widget.set_wrap(True)
        widget.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
    if css:
        widget.add_css_class(css)
    return widget


# ─────────────────────────────────────────────────────────────
# Страницы
# ─────────────────────────────────────────────────────────────

class Page(Gtk.Box):
    def __init__(self, app: "InstallerWindow", title: str, subtitle: str = ""):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.app = app
        self.add_css_class("page")
        self.set_margin_top(28)
        self.set_margin_bottom(20)
        self.set_margin_start(36)
        self.set_margin_end(36)

        heading = label(title, "title")
        self.append(heading)
        if subtitle:
            self.append(label(subtitle, "subtitle", wrap=True))

    def on_enter(self) -> None:
        pass

    def on_leave(self) -> None:
        pass

    def can_next(self) -> bool:
        return True


class WelcomePage(Page):
    def __init__(self, app: "InstallerWindow"):
        super().__init__(
            app,
            "Добро пожаловать в Soldarch",
            "Arch Linux с Hyprland, Throne и zapret. Пока идёт установка, можно посмотреть открытый мультфильм «Big Buck Bunny».",
        )

        self.video = Gtk.Video()
        self.video.set_hexpand(True)
        self.video.set_vexpand(True)
        self.video.set_size_request(-1, 380)
        self.video.set_loop(True)
        self.video.set_autoplay(True)
        self.video.add_css_class("video")
        self.append(self.video)

        if VIDEO_PATH.is_file():
            self.video.set_file(Gio.File.new_for_path(str(VIDEO_PATH)))
        else:
            self.append(
                label(
                    "Видео не найдено — установка продолжится без него.",
                    "muted",
                    wrap=True,
                )
            )

        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        controls.set_halign(Gtk.Align.CENTER)

        self.mute_btn = Gtk.ToggleButton(label="Без звука")
        self.mute_btn.set_active(False)
        self.mute_btn.connect("toggled", self._on_mute)
        controls.append(self.mute_btn)

        self.append(controls)

        start = Gtk.Button(label="Начать установку")
        start.add_css_class("suggested")
        start.set_size_request(240, 46)
        start.set_halign(Gtk.Align.CENTER)
        start.connect("clicked", lambda _: self.app.next_page())
        self.append(start)

    def _on_mute(self, btn: Gtk.ToggleButton) -> None:
        stream = self.video.get_media_stream()
        if stream is not None:
            stream.set_volume(0.0 if btn.get_active() else 1.0)

    def on_enter(self) -> None:
        stream = self.video.get_media_stream()
        if stream is not None:
            stream.set_loop(True)
            stream.play()

    def on_leave(self) -> None:
        stream = self.video.get_media_stream()
        if stream is not None:
            stream.pause()


class DiskPage(Page):
    def __init__(self, app: "InstallerWindow"):
        super().__init__(
            app,
            "Диск и разметка",
            "Выберите диск. В режиме раздела существующие разделы не изменяются, кроме выбранного корня.",
        )

        self.mode = "disk"
        self.disks: List[Dict[str, Any]] = []
        self.parts: List[Dict[str, Any]] = []
        self.selected_disk: Optional[Dict[str, Any]] = None
        self.root_part: Optional[Dict[str, Any]] = None
        self.esp_part: Optional[Dict[str, Any]] = None

        # Режим
        mode_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=20)
        self.rb_disk = Gtk.CheckButton(label="Весь диск")
        self.rb_disk.set_active(True)
        self.rb_disk.connect("toggled", self._on_mode)
        self.rb_part = Gtk.CheckButton(label="Существующий раздел (dual-boot)")
        self.rb_part.set_group(self.rb_disk)
        self.rb_part.connect("toggled", self._on_mode)
        mode_row.append(self.rb_disk)
        mode_row.append(self.rb_part)
        self.append(mode_row)

        # Список дисков
        disk_frame = Gtk.Frame(label="Целевой диск")
        self.disk_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.disk_box.set_margin_top(10)
        self.disk_box.set_margin_bottom(10)
        self.disk_box.set_margin_start(10)
        self.disk_box.set_margin_end(10)
        disk_scroll = Gtk.ScrolledWindow()
        disk_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        disk_scroll.set_min_content_height(110)
        disk_scroll.set_max_content_height(150)
        disk_scroll.set_child(self.disk_box)
        disk_frame.set_child(disk_scroll)
        self.append(disk_frame)

        # Разделы (для режима раздела)
        self.part_frame = Gtk.Frame(label="Существующие разделы")
        part_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        part_box.set_margin_top(10)
        part_box.set_margin_bottom(10)
        part_box.set_margin_start(10)
        part_box.set_margin_end(10)
        part_box.append(label("Корневой раздел (будет отформатирован):", "muted"))
        self.root_combo = Gtk.ComboBoxText()
        self.root_combo.connect("changed", self._on_root_changed)
        part_box.append(self.root_combo)
        part_box.append(label("EFI системный раздел (ESP, не форматируется):", "muted"))
        self.esp_combo = Gtk.ComboBoxText()
        self.esp_combo.connect("changed", self._on_esp_changed)
        part_box.append(self.esp_combo)
        self.part_frame.set_child(part_box)
        self.part_frame.set_visible(False)
        self.append(self.part_frame)

        # LUKS
        luks_frame = Gtk.Frame(label="Шифрование LUKS2")
        luks_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        luks_box.set_margin_top(10)
        luks_box.set_margin_bottom(10)
        luks_box.set_margin_start(10)
        luks_box.set_margin_end(10)

        self.luks_check = Gtk.CheckButton(
            label="Зашифровать / и /home (пароль потребуется при каждой загрузке)"
        )
        self.luks_check.connect("toggled", self._on_luks)
        luks_box.append(self.luks_check)
        luks_box.append(
            label("LUKS доступен только при установке на весь диск.", "muted", wrap=True)
        )

        self.luks_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.luks_row.set_visible(False)
        self.luks_pass = Gtk.PasswordEntry()
        self.luks_pass.set_hexpand(True)
        self.luks_pass.set_property("placeholder-text", "Пароль LUKS (минимум 8 символов)")
        self.luks_pass.connect("changed", self._validate)
        self.luks_pass2 = Gtk.PasswordEntry()
        self.luks_pass2.set_hexpand(True)
        self.luks_pass2.set_property("placeholder-text", "Повторите пароль")
        self.luks_pass2.connect("changed", self._validate)
        self.luks_row.append(self.luks_pass)
        self.luks_row.append(self.luks_pass2)
        luks_box.append(self.luks_row)

        luks_frame.set_child(luks_box)
        self.append(luks_frame)

        self.refresh_disks()

    # ── список дисков ────────────────────────────────────────
    def refresh_disks(self) -> None:
        clear_box(self.disk_box)
        self.disks = get_disks()
        self.selected_disk = None
        self._disk_buttons: List[Gtk.CheckButton] = []

        if not self.disks:
            self.disk_box.append(label("Диски не найдены.", "error"))
            self._validate()
            return

        first: Optional[Gtk.CheckButton] = None
        for disk in self.disks:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            rb = Gtk.CheckButton()
            rb.set_group(first)
            if first is None:
                first = rb
            rb.connect("toggled", self._on_disk, disk)
            row.append(rb)

            info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            info.append(label(f"{disk['name']}  ·  {human_size(disk['size'])}", "strong"))
            info.append(label(f"{disk['model']}  ·  {disk['tran']}", "muted"))
            row.append(info)
            self.disk_box.append(row)
            self._disk_buttons.append(rb)

        if self._disk_buttons:
            self._disk_buttons[0].set_active(True)
        self._validate()

    def _on_disk(self, btn: Gtk.CheckButton, disk: Dict[str, Any]) -> None:
        if not btn.get_active():
            return
        self.selected_disk = disk
        self._refresh_parts()
        self._validate()

    def _refresh_parts(self) -> None:
        self.parts = get_partitions(self.selected_disk["name"]) if self.selected_disk else []
        self.root_combo.remove_all()
        self.esp_combo.remove_all()
        self.root_part = None
        self.esp_part = None

        for part in self.parts:
            text = f"{part['name']}  ·  {human_size(part['size'])}"
            if part["fstype"]:
                text += f"  ·  {part['fstype']}"
            if part["label"]:
                text += f"  ·  {part['label']}"
            if part["parttype"] == ESP_GUID:
                self.esp_combo.append(part["name"], text)
            else:
                self.root_combo.append(part["name"], text)

        if self.esp_combo.get_model() is not None and len(self.esp_combo.get_model()) > 0:
            self.esp_combo.set_active(0)
        # Корень не выбираем автоматически: форматирование чужого раздела
        # должно быть осознанным действием.
        if self.root_combo.get_model() is not None and len(self.root_combo.get_model()) > 0:
            self.root_combo.set_active(-1)

    def _on_root_changed(self, combo: Gtk.ComboBoxText) -> None:
        active = combo.get_active_id()
        self.root_part = next((p for p in self.parts if p["name"] == active), None)
        self._validate()

    def _on_esp_changed(self, combo: Gtk.ComboBoxText) -> None:
        active = combo.get_active_id()
        self.esp_part = next((p for p in self.parts if p["name"] == active), None)
        self._validate()

    # ── режим / LUKS ─────────────────────────────────────────
    def _on_mode(self, btn: Gtk.CheckButton) -> None:
        if not btn.get_active():
            return
        self.mode = "disk" if btn is self.rb_disk else "partition"
        self.part_frame.set_visible(self.mode == "partition")
        if self.mode == "partition":
            self.luks_check.set_active(False)
            self.luks_check.set_sensitive(False)
            self._refresh_parts()
        else:
            self.luks_check.set_sensitive(True)
        self._validate()

    def _on_luks(self, btn: Gtk.CheckButton) -> None:
        self.luks_row.set_visible(btn.get_active() and self.mode == "disk")
        self._validate()

    def _validate(self, *_: Any) -> None:
        ok = self.selected_disk is not None
        if self.mode == "partition":
            ok = ok and self.root_part is not None and self.esp_part is not None
        if self.luks_check.get_active() and self.mode == "disk":
            p1 = self.luks_pass.get_text()
            p2 = self.luks_pass2.get_text()
            ok = ok and len(p1) >= 8 and p1 == p2
        self.app.set_next_enabled(ok)

    def can_next(self) -> bool:
        ok = self.selected_disk is not None
        if self.mode == "partition":
            ok = ok and self.root_part is not None and self.esp_part is not None
        if self.luks_check.get_active() and self.mode == "disk":
            p1 = self.luks_pass.get_text()
            p2 = self.luks_pass2.get_text()
            ok = ok and len(p1) >= 8 and p1 == p2
        return ok

    def on_enter(self) -> None:
        self.refresh_disks()

    def on_leave(self) -> None:
        cfg = self.app.config
        cfg["mode"] = self.mode
        cfg["disk"] = self.selected_disk["name"] if self.selected_disk else ""
        cfg["root_part"] = self.root_part["name"] if self.root_part else ""
        cfg["esp"] = self.esp_part["name"] if self.esp_part else ""
        cfg["luks"] = bool(self.luks_check.get_active() and self.mode == "disk")
        cfg["luks_password"] = self.luks_pass.get_text() if cfg["luks"] else ""


class ProfilePage(Page):
    def __init__(self, app: "InstallerWindow"):
        super().__init__(
            app,
            "Профиль пакетов",
            "Дополнительный набор ПО. Базовый рабочий стол устанавливается всегда.",
        )

        self.selected = "minimal"
        self._buttons: Dict[str, Gtk.CheckButton] = {}
        first: Optional[Gtk.CheckButton] = None

        for key in ("minimal", "developer", "gaming", "full"):
            profile = PROFILES[key]
            frame = Gtk.Frame()
            frame.add_css_class("card")
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            box.set_margin_top(10)
            box.set_margin_bottom(10)
            box.set_margin_start(12)
            box.set_margin_end(12)

            rb = Gtk.CheckButton(label=profile["name"])
            rb.add_css_class("strong")
            rb.set_group(first)
            if first is None:
                first = rb
            rb.set_active(key == "minimal")
            rb.connect("toggled", self._on_select, key)
            box.append(rb)
            box.append(label(profile["desc"], "muted", wrap=True))
            box.append(label(profile["size"], "caption"))
            frame.set_child(box)
            self.append(frame)
            self._buttons[key] = rb

        self._update_cards()

    def _on_select(self, btn: Gtk.CheckButton, key: str) -> None:
        if not btn.get_active():
            return
        self.selected = key
        self._update_cards()
        self.app.set_next_enabled(True)

    def _update_cards(self) -> None:
        for key, btn in self._buttons.items():
            parent = btn.get_parent()
            while parent is not None and not isinstance(parent, Gtk.Frame):
                parent = parent.get_parent()
            if parent is None:
                continue
            if key == self.selected:
                parent.add_css_class("selected")
            else:
                parent.remove_css_class("selected")

    def on_leave(self) -> None:
        self.app.config["profile"] = self.selected


class UserPage(Page):
    def __init__(self, app: "InstallerWindow"):
        super().__init__(
            app,
            "Пользователь и система",
            "Пользователь и хостнейм фиксированы. Пароль нужен для входа и sudo.",
        )

        grid = Gtk.Grid()
        grid.set_row_spacing(10)
        grid.set_column_spacing(14)
        grid.set_hexpand(True)
        self.append(grid)

        row = 0

        def add_row(title: str, widget: Gtk.Widget) -> None:
            nonlocal row
            grid.attach(label(title, "field-label"), 0, row, 1, 1)
            grid.attach(widget, 1, row, 1, 1)
            row += 1

        self.user_entry = Gtk.Entry()
        self.user_entry.set_text("iam")
        self.user_entry.set_editable(False)
        add_row("Пользователь", self.user_entry)

        self.pass_entry = Gtk.PasswordEntry()
        self.pass_entry.set_hexpand(True)
        self.pass_entry.set_property("placeholder-text", "Минимум 8 символов")
        self.pass_entry.connect("changed", self._validate)
        add_row("Пароль", self.pass_entry)

        self.pass_entry2 = Gtk.PasswordEntry()
        self.pass_entry2.set_hexpand(True)
        self.pass_entry2.set_property("placeholder-text", "Повторите пароль")
        self.pass_entry2.connect("changed", self._validate)
        add_row("Подтверждение", self.pass_entry2)

        self.host_entry = Gtk.Entry()
        self.host_entry.set_text("arch")
        self.host_entry.set_editable(False)
        add_row("Хостнейм", self.host_entry)

        self.locale_combo = Gtk.ComboBoxText()
        for code, name in LOCALES:
            self.locale_combo.append(code, name)
        self.locale_combo.set_active(0)
        add_row("Локаль", self.locale_combo)

        self.tz_combo = Gtk.ComboBoxText()
        for tz in TIMEZONES:
            self.tz_combo.append(tz, tz)
        self.tz_combo.set_active(0)
        add_row("Часовой пояс", self.tz_combo)

        self.kb_entry = Gtk.Entry()
        self.kb_entry.set_text("us,ru  (Alt+Shift)")
        self.kb_entry.set_editable(False)
        add_row("Раскладки", self.kb_entry)

        self.append(
            label(
                "root будет заблокирован, пользователь iam получит sudo. "
                "Сеть настраивается после первой загрузки через nmtui или nm-applet.",
                "muted",
                wrap=True,
            )
        )

    def _validate(self, *_: Any) -> None:
        self.app.set_next_enabled(self.can_next())

    def can_next(self) -> bool:
        p1 = self.pass_entry.get_text()
        p2 = self.pass_entry2.get_text()
        return bool(p1) and len(p1) >= 8 and p1 == p2

    def on_leave(self) -> None:
        cfg = self.app.config
        cfg["username"] = "iam"
        cfg["hostname"] = "arch"
        cfg["password"] = self.pass_entry.get_text()
        cfg["locale"] = self.locale_combo.get_active_id() or "en_US.UTF-8"
        cfg["timezone"] = self.tz_combo.get_active_id() or "Europe/Moscow"


class SummaryPage(Page):
    def __init__(self, app: "InstallerWindow"):
        super().__init__(app, "Подтверждение", "Проверьте параметры перед началом установки.")

        self.text = Gtk.TextView()
        self.text.set_editable(False)
        self.text.set_cursor_visible(False)
        self.text.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.text.set_monospace(True)
        self.text.add_css_class("summary")

        scroll = Gtk.ScrolledWindow()
        scroll.set_hexpand(True)
        scroll.set_vexpand(True)
        scroll.set_child(self.text)
        self.append(scroll)

        self.confirm = Gtk.CheckButton(
            label="Я понимаю, что данные на выбранном диске или разделе будут уничтожены"
        )
        self.confirm.connect("toggled", lambda b: self.app.set_next_enabled(b.get_active()))
        self.append(self.confirm)

    def on_enter(self) -> None:
        cfg = self.app.config
        target = cfg.get("disk", "—")
        if cfg.get("mode") == "partition":
            target = f"{cfg.get('root_part', '—')} (ESP: {cfg.get('esp', '—')})"

        lines = [
            "Параметры установки",
            "────────────────────",
            f"Цель          : {target}",
            f"Режим         : {'весь диск' if cfg.get('mode') == 'disk' else 'существующий раздел'}",
            f"LUKS2         : {'да' if cfg.get('luks') else 'нет'}",
            f"Профиль       : {PROFILES[cfg['profile']]['name']}",
            f"Пользователь  : {cfg.get('username')}",
            f"Хостнейм      : {cfg.get('hostname')}",
            f"Локаль        : {cfg.get('locale')}",
            f"Часовой пояс  : {cfg.get('timezone')}",
            f"Раскладки     : us,ru (Alt+Shift)",
            "",
            "Разметка: ESP + ext4 / + ext4 /home + swap-файл 4 ГиБ.",
            "Пакеты устанавливаются из офлайн-репозитория внутри ISO.",
            "",
            "После подтверждения установка начнётся сразу.",
        ]
        self.text.get_buffer().set_text("\n".join(lines))
        self.confirm.set_active(False)
        self.app.set_next_enabled(False)

    def can_next(self) -> bool:
        return self.confirm.get_active()


class InstallPage(Page):
    def __init__(self, app: "InstallerWindow"):
        super().__init__(app, "Установка системы", "Не выключайте компьютер до завершения.")
        self.started = False
        self.finished = False

        self.video = Gtk.Video()
        self.video.set_hexpand(True)
        self.video.set_vexpand(True)
        self.video.set_size_request(-1, 250)
        self.video.set_loop(True)
        self.video.set_autoplay(True)
        self.video.add_css_class("video")
        if VIDEO_PATH.is_file():
            self.video.set_file(Gio.File.new_for_path(str(VIDEO_PATH)))
        self.append(self.video)

        self.progress = Gtk.ProgressBar()
        self.progress.set_show_text(True)
        self.progress.set_fraction(0.0)
        self.progress.set_text("0 %")
        self.append(self.progress)

        self.status = label("Подготовка…", "status")
        self.append(self.status)

        self.log_expander = Gtk.Expander(label="Подробный лог")
        self.log = Gtk.TextView()
        self.log.set_editable(False)
        self.log.set_cursor_visible(False)
        self.log.set_monospace(True)
        self.log.add_css_class("log")
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_min_content_height(120)
        log_scroll.set_child(self.log)
        self.log_expander.set_child(log_scroll)
        self.append(self.log_expander)

        self.buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.buttons.set_halign(Gtk.Align.CENTER)
        self.buttons.set_visible(False)

        self.reboot_btn = Gtk.Button(label="Перезагрузить")
        self.reboot_btn.add_css_class("suggested")
        self.reboot_btn.connect("clicked", lambda _: run(["systemctl", "reboot"]))
        self.buttons.append(self.reboot_btn)

        self.poweroff_btn = Gtk.Button(label="Выключить")
        self.poweroff_btn.connect("clicked", lambda _: run(["systemctl", "poweroff"]))
        self.buttons.append(self.poweroff_btn)

        self.append(self.buttons)

    def on_enter(self) -> None:
        self.app.nav.set_visible(False)
        stream = self.video.get_media_stream()
        if stream is not None:
            stream.play()
        if not self.started:
            self.started = True
            threading.Thread(target=self._install, daemon=True).start()

    def on_leave(self) -> None:
        pass

    def can_next(self) -> bool:
        return False

    def _install(self) -> None:
        cfg = self.app.config
        args = [INSTALLER, "--auto", "--no-reboot"]
        if cfg.get("mode") == "disk":
            args += ["--disk", cfg["disk"]]
        else:
            args += ["--partition", cfg["root_part"], "--efi", cfg["esp"]]
        if cfg.get("luks"):
            args += ["--luks", "--luks-password", cfg["luks_password"]]
        args += [
            "--profile",
            cfg["profile"],
            "--username",
            cfg["username"],
            "--password",
            cfg["password"],
            "--hostname",
            cfg["hostname"],
            "--locale",
            cfg["locale"],
            "--timezone",
            cfg["timezone"],
            "--yes",
        ]

        GLib.idle_add(self._set_status, "Запуск установщика…")
        GLib.idle_add(self._set_progress, 0.02, "2 %")

        env = os.environ.copy()
        env["LC_ALL"] = "C.UTF-8"
        env["LANG"] = "C.UTF-8"
        env["TERM"] = "dumb"
        try:
            proc = subprocess.Popen(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                text=True,
                bufsize=1,
                env=env,
            )
        except OSError as exc:
            GLib.idle_add(self._failed, f"Не удалось запустить установщик: {exc}")
            return

        assert proc.stdout is not None
        for raw in proc.stdout:
            line = raw.rstrip("\n")
            GLib.idle_add(self._append_log, line)
            self._advance(line)

        code = proc.wait()
        if code == 0:
            GLib.idle_add(self._success)
        else:
            GLib.idle_add(self._failed, f"Установщик завершился с кодом {code}")

    def _advance(self, line: str) -> None:
        low = ANSI_RE.sub("", line).lower()
        stage: Optional[tuple[float, str]] = None
        if "разметка" in low:
            stage = (0.05, "Разметка диска…")
        elif "форматирование" in low:
            stage = (0.10, "Форматирование разделов…")
        elif "монтирование" in low or "монтир" in low:
            stage = (0.13, "Монтирование файловых систем…")
        elif "swap" in low:
            stage = (0.15, "Создание swap-файла…")
        elif "установка пакетов" in low or "пакетов:" in low:
            stage = (0.20, "Установка пакетов — самый долгий этап…")
        elif "конфигурац" in low or "копирование" in low:
            stage = (0.70, "Копирование конфигурации…")
        elif "настройка системы" in low:
            stage = (0.80, "Настройка системы…")
        elif "загрузчик" in low or "grub" in low:
            stage = (0.90, "Установка загрузчика…")
        elif "проверка" in low or "проверки" in low:
            stage = (0.97, "Проверка установки…")
        elif "soldarch установлен" in low:
            stage = (1.0, "Готово")
        if stage is not None:
            value, text = stage
            GLib.idle_add(self._set_progress, value, f"{int(value * 100)} %")
            GLib.idle_add(self._set_status, text)

    def _append_log(self, line: str) -> None:
        buf = self.log.get_buffer()
        buf.insert(buf.get_end_iter(), ANSI_RE.sub("", line) + "\n")
        mark = buf.create_mark(None, buf.get_end_iter(), True)
        self.log.scroll_mark_onscreen(mark)

    def _set_status(self, text: str) -> None:
        self.status.set_text(text)

    def _set_progress(self, value: float, text: str) -> None:
        self.progress.set_fraction(value)
        self.progress.set_text(text)

    def _success(self) -> None:
        self.finished = True
        self._set_progress(1.0, "100 %")
        self._set_status("Установка завершена успешно")
        self.buttons.set_visible(True)
        self.log_expander.set_expanded(True)
        stream = self.video.get_media_stream()
        if stream is not None:
            stream.pause()

    def _failed(self, message: str) -> None:
        self.finished = True
        self._set_status(message)
        self.status.add_css_class("error")
        self.buttons.set_visible(True)
        self.log_expander.set_expanded(True)


# ─────────────────────────────────────────────────────────────
# Окно
# ─────────────────────────────────────────────────────────────

class InstallerWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application):
        super().__init__(application=app, title="Soldarch Installer")
        self.set_default_size(1024, 768)
        self.set_size_request(900, 600)
        self.config: Dict[str, Any] = {}

        self._load_css()

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_child(root)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(180)
        self.stack.set_vexpand(True)
        self.stack.set_hexpand(True)
        root.append(self.stack)

        self.welcome = WelcomePage(self)
        self.disk = DiskPage(self)
        self.profile = ProfilePage(self)
        self.user = UserPage(self)
        self.summary = SummaryPage(self)
        self.install = InstallPage(self)
        self.pages = [
            self.welcome,
            self.disk,
            self.profile,
            self.user,
            self.summary,
            self.install,
        ]
        for idx, page in enumerate(self.pages):
            self.stack.add_named(page, f"page{idx}")
        self.index = 0

        self.nav = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.nav.add_css_class("nav")
        self.nav.set_margin_top(8)
        self.nav.set_margin_bottom(10)
        self.nav.set_margin_start(24)
        self.nav.set_margin_end(24)

        self.back_btn = Gtk.Button(label="Назад")
        self.back_btn.connect("clicked", lambda _: self.prev_page())
        self.nav.append(self.back_btn)

        self.steps = ["Диск", "Профиль", "Пользователь", "Подтверждение"]
        self.step_labels: List[Gtk.Label] = []
        for i, name in enumerate(self.steps):
            lbl = label(name, "step")
            lbl.set_hexpand(True)
            lbl.set_halign(Gtk.Align.CENTER)
            self.step_labels.append(lbl)
            self.nav.append(lbl)
            if i < len(self.steps) - 1:
                self.nav.append(label("›", "step-sep"))

        self.next_btn = Gtk.Button(label="Далее")
        self.next_btn.add_css_class("suggested")
        self.next_btn.connect("clicked", lambda _: self.next_page())
        self.nav.append(self.next_btn)
        root.append(self.nav)

        self._update_nav()

    def _load_css(self) -> None:
        provider = Gtk.CssProvider()
        try:
            if THEME_PATH.is_file():
                provider.load_from_path(str(THEME_PATH))
            else:
                provider.load_from_data(FALLBACK_CSS.encode())
        except GLib.Error as exc:
            print(f"CSS error: {exc}", file=sys.stderr)
            provider.load_from_data(FALLBACK_CSS.encode())
        display = Gdk.Display.get_default()
        if display is None:
            raise RuntimeError("Нет графического дисплея")
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def set_next_enabled(self, enabled: bool) -> None:
        btn = getattr(self, "next_btn", None)
        if btn is not None:
            btn.set_sensitive(bool(enabled))

    def next_page(self) -> None:
        page = self.pages[self.index]
        if not page.can_next():
            return
        page.on_leave()
        if self.index < len(self.pages) - 1:
            self.index += 1
            self.stack.set_visible_child_name(f"page{self.index}")
            self.pages[self.index].on_enter()
            self._update_nav()

    def prev_page(self) -> None:
        if self.index == 0 or self.index == len(self.pages) - 1:
            return
        self.pages[self.index].on_leave()
        self.index -= 1
        self.stack.set_visible_child_name(f"page{self.index}")
        self.pages[self.index].on_enter()
        self._update_nav()

    def _update_nav(self) -> None:
        self.back_btn.set_sensitive(self.index > 0 and self.index < len(self.pages) - 1)
        self.set_next_enabled(self.pages[self.index].can_next())

        stage = max(0, self.index - 1)
        for i, lbl in enumerate(self.step_labels):
            lbl.remove_css_class("active")
            lbl.remove_css_class("done")
            if i == stage and 0 < self.index < len(self.pages) - 1:
                lbl.add_css_class("active")
            elif i < stage:
                lbl.add_css_class("done")

        if self.index == len(self.pages) - 2:
            self.next_btn.set_label("Установить")
        else:
            self.next_btn.set_label("Далее")

    def do_close_request(self) -> bool:
        if getattr(self, "install", None) is not None and self.install.started and not self.install.finished:
            return True
        return False


FALLBACK_CSS = """
window { background-color: #1e1e2e; }
.page { background-color: #1e1e2e; }
.title { font-size: 26px; font-weight: 800; color: #cdd6f4; }
.subtitle { font-size: 14px; color: #a6adc8; }
.strong { font-weight: 700; color: #cdd6f4; }
.muted { font-size: 13px; color: #9399b2; }
.caption { font-size: 12px; color: #6c7086; }
.error { color: #f38ba8; }
.field-label { color: #a6adc8; }
.nav { background-color: #181825; border-top: 1px solid #313244; padding: 6px 10px; }
.step { color: #6c7086; font-size: 12px; }
.step.active { color: #89b4fa; font-weight: 700; }
.step.done { color: #a6e3a1; }
.step-sep { color: #45475a; }
button.suggested { background-color: #89b4fa; color: #11111b; font-weight: 700; padding: 7px 22px; border-radius: 8px; }
button.suggested:hover { background-color: #b4befe; }
.video { background-color: #11111b; border: 1px solid #313244; border-radius: 10px; }
.summary { font-size: 13px; background-color: #181825; border: 1px solid #313244; padding: 14px; border-radius: 8px; }
.log { font-size: 11px; background-color: #11111b; color: #a6adc8; }
frame { border: 1px solid #313244; border-radius: 8px; background-color: #181825; }
frame > label { color: #89b4fa; font-weight: 700; }
.card.selected { border: 2px solid #89b4fa; background-color: #1e1e2e; }
"""


class SoldarchApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.soldarch.installer")

    def do_activate(self) -> None:
        win = InstallerWindow(self)
        win.present()


def main() -> int:
    app = SoldarchApp()
    return app.run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
