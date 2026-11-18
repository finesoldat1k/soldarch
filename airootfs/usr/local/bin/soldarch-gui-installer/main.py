#!/usr/bin/env python3
# soldarch-gui-installer — графический установщик Soldarch (GTK4 + GStreamer)

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gst', '1.0')
gi.require_version('GstVideo', '1.0')
from gi.repository import Gtk, GLib, Gst, GstVideo, Gdk, GdkPixbuf

import subprocess
import threading
import os
import json
import shutil
from pathlib import Path
from typing import Optional, List, Dict, Any
import sys

VIDEO_PATH = "/usr/share/soldarch/video/aot_s1e1_720p_hevc.mkv"
THEME_CSS = "/usr/share/soldarch/gui/theme.css"
CONFIG_DIR = Path("/tmp/soldarch-install")
CONFIG_DIR.mkdir(exist_ok=True)

PACKAGE_PROFILES = {
    "minimal": {"name": "Минимум", "desc": "Базовая система + Hyprland + SDDM (~3.5 GiB)", "packages": ["base", "linux", "linux-firmware", "hyprland", "sddm", "waybar", "foot", "wofi", "mako", "networkmanager", "iwd", "pipewire", "wireplumber", "pipewire-pulse", "pipewire-alsa", "pipewire-jack", "fish", "throne-bin", "soldarch-zapret"], "size_gib": 3.5},
    "developer": {"name": "Разработка", "desc": "Минимум + инструменты разработки (~5.2 GiB)", "packages": ["base-devel", "git", "github-cli", "docker", "docker-compose", "podman", "buildah", "code", "nodejs", "npm", "pnpm", "python", "python-pip", "python-poetry", "rustup", "go", "lua", "luarocks", "zig", "cmake", "meson", "ninja", "gdb", "valgrind", "strace", "ltrace", "perf"], "size_gib": 5.2},
    "gaming": {"name": "Игры", "desc": "Минимум + Steam + Proton + Lutris + Wine (~8.1 GiB)", "packages": ["steam", "lutris", "wine", "winetricks", "gamemode", "lib32-gamemode", "mangohud", "lib32-mangohud", "vulkan-tools", "lib32-vulkan-icd-loader", "vulkan-validation-layers", "lib32-vulkan-validation-layers", "dxvk-bin", "vkd3d", "lib32-vkd3d"], "size_gib": 8.1},
    "full": {"name": "Полный (всё)", "desc": "Все профили вместе (~12.4 GiB)", "packages": [], "size_gib": 12.4}
}

def run_cmd(cmd: List[str], capture=True) -> subprocess.CompletedProcess:
    print(f"$ {' '.join(cmd)}")
    return subprocess.run(cmd, capture_output=capture, text=True)

def get_disks() -> List[Dict[str, Any]]:
    result = run_cmd(["lsblk", "-J", "-o", "NAME,SIZE,TYPE,MOUNTPOINT,MODEL,TRAN"])
    if result.returncode != 0: return []
    data = json.loads(result.stdout)
    disks = []
    for dev in data.get("blockdevices", []):
        if dev.get("type") == "disk":
            disks.append({"name": f"/dev/{dev['name']}", "size": dev["size"], "model": dev.get("model", "Unknown"), "tran": dev.get("tran", "unknown"), "children": dev.get("children", [])})
    return disks

def get_partitions(disk: str) -> List[Dict[str, Any]]:
    result = run_cmd(["lsblk", "-J", "-o", "NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,UUID,PARTTYPE", disk])
    if result.returncode != 0: return []
    data = json.loads(result.stdout)
    parts = []
    for dev in data.get("blockdevices", []):
        for ch in dev.get("children", []):
            parts.append({"name": f"/dev/{ch['name']}", "size": ch["size"], "fstype": ch.get("fstype"), "mountpoint": ch.get("mountpoint"), "label": ch.get("label"), "uuid": ch.get("uuid"), "parttype": ch.get("parttype")})
    return parts

class AnimePlayer:
    def __init__(self, video_widget: Gtk.Video):
        self.video_widget = video_widget
        self.pipeline: Optional[Gst.Pipeline] = None
        self.playing = False
        Gst.init(None)

    def load(self, path: str) -> bool:
        if not os.path.exists(path):
            print(f"Video not found: {path}")
            return False
        pipeline_str = f"filesrc location={path} ! decodebin name=demux ! queue ! videoconvert ! gtksink name=sink demux. ! queue ! audioconvert ! autoaudiosink"
        self.pipeline = Gst.parse_launch(pipeline_str)
        if not self.pipeline: return False
        sink = self.pipeline.get_by_name("sink")
        if sink: self.video_widget.set_media_stream(sink.get_property("media-stream"))
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._on_bus_message)
        return True

    def _on_bus_message(self, bus, message):
        t = message.type
        if t == Gst.MessageType.EOS:
            self.playing = False; self.play()
        elif t == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            print(f"GStreamer error: {err}, {debug}")

    def play(self):
        if self.pipeline: self.pipeline.set_state(Gst.State.PLAYING); self.playing = True
    def pause(self):
        if self.pipeline: self.pipeline.set_state(Gst.State.PAUSED); self.playing = False
    def stop(self):
        if self.pipeline: self.pipeline.set_state(Gst.State.NULL); self.playing = False

class BasePage(Gtk.Box):
    def __init__(self, installer: "SoldarchInstaller"):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.installer = installer
        self.add_css_class("installer-page")
    def on_enter(self): pass
    def on_leave(self): pass
    def can_go_next(self) -> bool: return True
    def can_go_back(self) -> bool: return True

class WelcomePage(BasePage):
    def __init__(self, installer):
        super().__init__(installer)
        self.set_spacing(24); self.set_margin_top(48); self.set_margin_bottom(48); self.set_margin_start(48); self.set_margin_end(48)
        title = Gtk.Label(label="Добро пожаловать в Soldarch"); title.add_css_class("title-1"); title.set_halign(Gtk.Align.CENTER); self.append(title)
        subtitle = Gtk.Label(label="Установка Arch Linux с Hyprland, Throne и zapret"); subtitle.add_css_class("title-3"); subtitle.set_halign(Gtk.Align.CENTER); self.append(subtitle)
        self.video = Gtk.Video(); self.video.set_vexpand(True); self.video.set_hexpand(True); self.video.add_css_class("anime-video"); self.append(self.video)
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL); btn_box.set_halign(Gtk.Align.CENTER); btn_box.set_spacing(12)
        self.start_btn = Gtk.Button(label="Начать установку"); self.start_btn.add_css_class("suggested-action"); self.start_btn.set_size_request(200, 48); self.start_btn.connect("clicked", lambda _: self.installer.next_page()); btn_box.append(self.start_btn)
        self.append(btn_box)
        self.player = AnimePlayer(self.video)

    def on_enter(self):
        if self.player.load(VIDEO_PATH): self.player.play()
        else:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale("/usr/share/soldarch/gui/banner.png", 800, 450, True)
            self.video.set_paintable(Gdk.Texture.new_for_pixbuf(pixbuf))

class DiskPage(BasePage):
    def __init__(self, installer):
        super().__init__(installer)
        self.set_spacing(16); self.set_margin_top(24); self.set_margin_bottom(24); self.set_margin_start(48); self.set_margin_end(48)
        title = Gtk.Label(label="Выбор диска и разметка"); title.add_css_class("title-1"); title.set_halign(Gtk.Align.START); self.append(title)
        mode_frame = Gtk.Frame(label="Режим установки")
        mode_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8); mode_box.set_margin_top(12); mode_box.set_margin_bottom(12); mode_box.set_margin_start(12); mode_box.set_margin_end(12)
        self.mode_whole = Gtk.CheckButton(label="Весь диск (авторазметка: ESP + / + /home + swap)"); self.mode_whole.set_active(True); self.mode_whole.connect("toggled", self._on_mode_changed); mode_box.append(self.mode_whole)
        self.mode_part = Gtk.CheckButton(label="Существующий раздел (не трогать другие разделы)"); self.mode_part.connect("toggled", self._on_mode_changed); mode_box.append(self.mode_part)
        mode_frame.set_child(mode_box); self.append(mode_frame)
        self.luks_frame = Gtk.Frame(label="Шифрование (LUKS2)")
        luks_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8); luks_box.set_margin_top(12); luks_box.set_margin_bottom(12); luks_box.set_margin_start(12); luks_box.set_margin_end(12)
        self.enable_luks = Gtk.CheckButton(label="Зашифровать / и /home (требует пароль при загрузке)"); self.enable_luks.connect("toggled", self._on_luks_changed); luks_box.append(self.enable_luks)
        self.luks_password_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12); self.luks_password_row.set_visible(False)
        luks_pass_label = Gtk.Label(label="Пароль LUKS:"); self.luks_password_row.append(luks_pass_label)
        self.luks_pass_entry = Gtk.PasswordEntry(); self.luks_pass_entry.set_placeholder_text("Введите пароль шифрования"); self.luks_pass_entry.set_hexpand(True); self.luks_pass_entry.connect("changed", self._validate); self.luks_password_row.append(self.luks_pass_entry)
        self.luks_pass_confirm = Gtk.PasswordEntry(); self.luks_pass_confirm.set_placeholder_text("Повторите пароль"); self.luks_pass_confirm.connect("changed", self._validate); self.luks_password_row.append(self.luks_pass_confirm)
        luks_box.append(self.luks_password_row); self.luks_frame.set_child(luks_box); self.append(self.luks_frame)
        disk_frame = Gtk.Frame(label="Целевой диск")
        self.disk_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8); self.disk_box.set_margin_top(12); self.disk_box.set_margin_bottom(12); self.disk_box.set_margin_start(12); self.disk_box.set_margin_end(12); disk_frame.set_child(self.disk_box); self.append(disk_frame)
        self.refresh_disks()
        self.esp_frame = Gtk.Frame(label="EFI системный раздел (ESP)")
        self.esp_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8); self.esp_box.set_margin_top(12); self.esp_box.set_margin_bottom(12); self.esp_box.set_margin_start(12); self.esp_box.set_margin_end(12); self.esp_frame.set_child(self.esp_box); self.esp_frame.set_visible(False); self.append(self.esp_frame)
        self._validate()

    def refresh_disks(self):
        while child := self.disk_box.get_first_child(): self.disk_box.remove(child)
        disks = get_disks(); self.disk_buttons = []; self.selected_disk = None
        for disk in disks:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12); row.add_css_class("disk-row")
            rb = Gtk.CheckButton(); rb.set_group(self.disk_buttons[0] if self.disk_buttons else None); rb.connect("toggled", self._on_disk_selected, disk); row.append(rb)
            info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            name_lbl = Gtk.Label(label=f"{disk['name']} ({disk['size']})"); name_lbl.set_halign(Gtk.Align.START); name_lbl.add_css_class("heading"); info.append(name_lbl)
            model_lbl = Gtk.Label(label=f"{disk['model']} • {disk['tran']}"); model_lbl.set_halign(Gtk.Align.START); model_lbl.add_css_class("dim-label"); info.append(model_lbl)
            row.append(info); self.disk_box.append(row); self.disk_buttons.append(rb)

    def _on_mode_changed(self, btn):
        if btn.get_active():
            if btn == self.mode_whole: self.mode_part.set_active(False); self.esp_frame.set_visible(False)
            else: self.mode_whole.set_active(False); self.esp_frame.set_visible(True); self.refresh_esp()
        self._validate()

    def _on_luks_changed(self, btn):
        self.luks_password_row.set_visible(btn.get_active()); self._validate()

    def _on_disk_selected(self, btn, disk):
        if btn.get_active(): self.selected_disk = disk
        self._validate()

    def refresh_esp(self):
        while child := self.esp_box.get_first_child(): self.esp_box.remove(child)
        if not self.selected_disk: return
        parts = get_partitions(self.selected_disk["name"]); esp_parts = [p for p in parts if p["parttype"] == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"]
        self.esp_buttons = []; self.selected_esp = None
        for part in esp_parts:
            rb = Gtk.CheckButton(label=f"{part['name']} ({part['size']})"); rb.set_group(self.esp_buttons[0] if self.esp_buttons else None); rb.connect("toggled", lambda b, p=part: self._on_esp_selected(b, p)); self.esp_box.append(rb); self.esp_buttons.append(rb)

    def _on_esp_selected(self, btn, part):
        if btn.get_active(): self.selected_esp = part
        self._validate()

    def _validate(self, *args):
        ok = True
        if self.mode_whole.get_active(): ok = self.selected_disk is not None
        else: ok = self.selected_disk is not None and self.selected_esp is not None
        if self.enable_luks.get_active():
            p1 = self.luks_pass_entry.get_text(); p2 = self.luks_pass_confirm.get_text()
            ok = ok and p1 and p1 == p2 and len(p1) >= 8
        self.installer.set_next_enabled(ok)

    def can_go_next(self) -> bool: return self._validate() or True
    def on_enter(self): self.refresh_disks(); self._validate()

class ProfilePage(BasePage):
    def __init__(self, installer):
        super().__init__(installer)
        self.set_spacing(16); self.set_margin_top(24); self.set_margin_bottom(24); self.set_margin_start(48); self.set_margin_end(48)
        title = Gtk.Label(label="Профиль пакетов"); title.add_css_class("title-1"); title.set_halign(Gtk.Align.START); self.append(title)
        desc = Gtk.Label(label="Выберите набор предустановленного ПО. Можно изменить позже."); desc.add_css_class("dim-label"); desc.set_halign(Gtk.Align.START); desc.set_wrap(True); self.append(desc)
        self.profile_cards = {}; self.selected_profile = "minimal"
        for key, profile in PACKAGE_PROFILES.items():
            card = self._create_profile_card(key, profile); self.append(card); self.profile_cards[key] = card
        self._update_selection()

    def _create_profile_card(self, key, profile):
        frame = Gtk.Frame(); frame.add_css_class("profile-card"); frame.set_hexpand(True)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8); box.set_margin_top(16); box.set_margin_bottom(16); box.set_margin_start(16); box.set_margin_end(16)
        rb = Gtk.CheckButton(label=profile["name"]); rb.set_group(next(iter(self.profile_cards.values())).get_first_child() if self.profile_cards else None); rb.connect("toggled", lambda b, k=key: self._on_select(k)); rb.set_active(key == "minimal"); box.append(rb)
        desc_lbl = Gtk.Label(label=profile["desc"]); desc_lbl.set_halign(Gtk.Align.START); desc_lbl.add_css_class("dim-label"); desc_lbl.set_wrap(True); box.append(desc_lbl)
        size_lbl = Gtk.Label(label=f"~{profile['size_gib']} GiB"); size_lbl.set_halign(Gtk.Align.START); size_lbl.add_css_class("caption"); box.append(size_lbl)
        frame.set_child(box); return frame

    def _on_select(self, key): self.selected_profile = key; self._update_selection(); self.installer.set_next_enabled(True)
    def _update_selection(self):
        for key, card in self.profile_cards.items():
            if key == self.selected_profile: card.add_css_class("selected")
            else: card.remove_css_class("selected")
    def can_go_next(self) -> bool: return True

class UserPage(BasePage):
    def __init__(self, installer):
        super().__init__(installer)
        self.set_spacing(16); self.set_margin_top(24); self.set_margin_bottom(24); self.set_margin_start(48); self.set_margin_end(48)
        title = Gtk.Label(label="Пользователь и сеть"); title.add_css_class("title-1"); title.set_halign(Gtk.Align.START); self.append(title)
        user_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        user_lbl = Gtk.Label(label="Пользователь:"); user_lbl.set_size_request(150, -1); user_box.append(user_lbl)
        self.username_entry = Gtk.Entry(); self.username_entry.set_text("iam"); self.username_entry.set_editable(False); self.username_entry.add_css_class("readonly"); user_box.append(self.username_entry); self.append(user_box)
        pass_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        pass_lbl = Gtk.Label(label="Пароль:"); pass_lbl.set_size_request(150, -1); pass_box.append(pass_lbl)
        self.pass_entry = Gtk.PasswordEntry(); self.pass_entry.set_placeholder_text("Введите пароль"); self.pass_entry.connect("changed", self._validate); self.pass_entry.set_hexpand(True); pass_box.append(self.pass_entry); self.append(pass_box)
        confirm_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        confirm_lbl = Gtk.Label(label="Подтверждение:"); confirm_lbl.set_size_request(150, -1); confirm_box.append(confirm_lbl)
        self.confirm_entry = Gtk.PasswordEntry(); self.confirm_entry.set_placeholder_text("Повторите пароль"); self.confirm_entry.connect("changed", self._validate); self.confirm_entry.set_hexpand(True); confirm_box.append(self.confirm_entry); self.append(confirm_box)
        host_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        host_lbl = Gtk.Label(label="Хостнейм:"); host_lbl.set_size_request(150, -1); host_box.append(host_lbl)
        self.host_entry = Gtk.Entry(); self.host_entry.set_text("arch"); self.host_entry.set_editable(False); self.host_entry.add_css_class("readonly"); host_box.append(self.host_entry); self.append(host_box)
        locale_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        locale_lbl = Gtk.Label(label="Локаль:"); locale_lbl.set_size_request(150, -1); locale_box.append(locale_lbl)
        self.locale_combo = Gtk.ComboBoxText(); self.locale_combo.append("en_US.UTF-8", "English (US)"); self.locale_combo.append("ru_RU.UTF-8", "Русский (RU)"); self.locale_combo.set_active(0); self.locale_combo.set_hexpand(True); locale_box.append(self.locale_combo); self.append(locale_box)
        tz_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        tz_lbl = Gtk.Label(label="Часовой пояс:"); tz_lbl.set_size_request(150, -1); tz_box.append(tz_lbl)
        self.tz_combo = Gtk.ComboBoxText()
        for tz in ["Europe/Moscow", "Europe/Kaliningrad", "Europe/Samara", "Asia/Yekaterinburg", "Asia/Omsk", "Asia/Krasnoyarsk", "Asia/Irkutsk", "Asia/Yakutsk", "Asia/Vladivostok", "Asia/Magadan", "Asia/Kamchatka"]: self.tz_combo.append(tz, tz)
        self.tz_combo.set_active(0); self.tz_combo.set_hexpand(True); tz_box.append(self.tz_combo); self.append(tz_box)
        kb_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        kb_lbl = Gtk.Label(label="Раскладки:"); kb_lbl.set_size_request(150, -1); kb_box.append(kb_lbl)
        self.kb_entry = Gtk.Entry(); self.kb_entry.set_text("us,ru"); self.kb_entry.set_editable(False); self.kb_entry.add_css_class("readonly"); kb_box.append(self.kb_entry); self.append(kb_box)
        self._validate()

    def _validate(self, *args):
        p1 = self.pass_entry.get_text(); p2 = self.confirm_entry.get_text()
        ok = p1 and p1 == p2 and len(p1) >= 8
        self.installer.set_next_enabled(ok)
    def can_go_next(self) -> bool:
        p1 = self.pass_entry.get_text(); p2 = self.confirm_entry.get_text()
        return p1 and p1 == p2 and len(p1) >= 8

class SummaryPage(BasePage):
    def __init__(self, installer):
        super().__init__(installer)
        self.set_spacing(16); self.set_margin_top(24); self.set_margin_bottom(24); self.set_margin_start(48); self.set_margin_end(48)
        title = Gtk.Label(label="Подтверждение установки"); title.add_css_class("title-1"); title.set_halign(Gtk.Align.START); self.append(title)
        self.summary_text = Gtk.TextView(); self.summary_text.set_editable(False); self.summary_text.set_cursor_visible(False); self.summary_text.set_wrap_mode(Gtk.WrapMode.WORD_CHAR); self.summary_text.add_css_class("summary-text")
        scrolled = Gtk.ScrolledWindow(); scrolled.set_child(self.summary_text); scrolled.set_vexpand(True); scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC); self.append(scrolled)
        self.confirm_check = Gtk.CheckButton(label="Я понимаю, что данные на выбранном диске будут уничтожены"); self.confirm_check.connect("toggled", self._on_confirm); self.append(self.confirm_check)

    def _on_confirm(self, btn): self.installer.set_next_enabled(btn.get_active())
    def on_enter(self): self._build_summary()
    def _build_summary(self):
        cfg = self.installer.config
        lines = ["Параметры установки:", "", f"  Режим:           {'Весь диск' if cfg.get('mode_whole') else 'Существующий раздел'}", f"  Диск:            {cfg.get('disk', '—')}", f"  LUKS:            {'Да' if cfg.get('luks') else 'Нет'}", f"  Профиль:         {PACKAGE_PROFILES[cfg.get('profile', 'minimal')]['name']}", f"  Пользователь:    {cfg.get('username', 'iam')}", f"  Хостнейм:        {cfg.get('hostname', 'arch')}", f"  Локаль:          {cfg.get('locale', 'en_US.UTF-8')}", f"  Таймзона:        {cfg.get('timezone', 'Europe/Moscow')}", "", "После подтверждения начнётся установка.", "Видео продолжит играть во время процесса."]
        buffer = self.summary_text.get_buffer(); buffer.set_text("\n".join(lines))
    def can_go_next(self) -> bool: return self.confirm_check.get_active()

class InstallPage(BasePage):
    def __init__(self, installer):
        super().__init__(installer)
        self.set_spacing(16); self.set_margin_top(24); self.set_margin_bottom(24); self.set_margin_start(48); self.set_margin_end(48)
        title = Gtk.Label(label="Установка системы"); title.add_css_class("title-1"); title.set_halign(Gtk.Align.START); self.append(title)
        self.video = Gtk.Video(); self.video.set_vexpand(True); self.video.set_hexpand(True); self.video.add_css_class("anime-video-small"); self.append(self.video)
        self.progress = Gtk.ProgressBar(); self.progress.set_show_text(True); self.progress.set_hexpand(True); self.append(self.progress)
        self.status_label = Gtk.Label(label="Подготовка..."); self.status_label.add_css_class("heading"); self.status_label.set_halign(Gtk.Align.START); self.append(self.status_label)
        self.log_expander = Gtk.Expander(label="Подробный лог")
        self.log_text = Gtk.TextView(); self.log_text.set_editable(False); self.log_text.set_cursor_visible(False); self.log_text.set_monospace(True); self.log_text.add_css_class("log-text")
        log_scrolled = Gtk.ScrolledWindow(); log_scrolled.set_child(self.log_text); log_scrolled.set_vexpand(True); log_scrolled.set_min_content_height(200); self.log_expander.set_child(log_scrolled); self.append(self.log_expander)
        self.btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12); self.btn_box.set_halign(Gtk.Align.CENTER); self.btn_box.set_visible(False)
        self.reboot_btn = Gtk.Button(label="Перезагрузить"); self.reboot_btn.add_css_class("suggested-action"); self.reboot_btn.set_size_request(160, 48); self.reboot_btn.connect("clicked", self._on_reboot); self.btn_box.append(self.reboot_btn)
        self.poweroff_btn = Gtk.Button(label="Выключить"); self.poweroff_btn.set_size_request(160, 48); self.poweroff_btn.connect("clicked", self._on_poweroff); self.btn_box.append(self.poweroff_btn)
        self.append(self.btn_box); self.player = AnimePlayer(self.video)

    def on_enter(self):
        if self.player.load(VIDEO_PATH): self.player.play()
        self._start_install()

    def _start_install(self):
        thread = threading.Thread(target=self._run_install, daemon=True); thread.start()

    def _run_install(self):
        cfg = self.installer.config
        args = ["soldarch-install"]
        if cfg.get("mode_whole"): args += ["--disk", cfg["disk"]]
        else: args += ["--partition", cfg["root_part"], "--esp", cfg["esp"]]
        if cfg.get("luks"): args += ["--luks", "--luks-password", cfg["luks_password"]]
        args += ["--profile", cfg["profile"], "--username", cfg["username"], "--password", cfg["password"], "--hostname", cfg["hostname"], "--locale", cfg["locale"], "--timezone", cfg["timezone"], "--yes"]
        GLib.idle_add(self._update_status, "Запуск установщика..."); GLib.idle_add(self._update_progress, 0.05)
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in proc.stdout:
            GLib.idle_add(self._append_log, line.strip())
            if "pacstrap" in line or "Установка пакетов" in line: GLib.idle_add(self._update_progress, 0.15); GLib.idle_add(self._update_status, "Установка пакетов...")
            elif "copy_target_configs" in line or "Конфигурация" in line: GLib.idle_add(self._update_progress, 0.65); GLib.idle_add(self._update_status, "Копирование конфигурации...")
            elif "grub" in line.lower() or "bootloader" in line.lower() or "GRUB" in line: GLib.idle_add(self._update_progress, 0.85); GLib.idle_add(self._update_status, "Установка загрузчика...")
            elif "verify_install" in line or "Проверка" in line: GLib.idle_add(self._update_progress, 0.95); GLib.idle_add(self._update_status, "Проверка установки...")
        proc.wait()
        if proc.returncode == 0: GLib.idle_add(self._install_success)
        else: GLib.idle_add(self._install_failed, proc.returncode)

    def _update_progress(self, value): self.progress.set_fraction(value); self.progress.set_text(f"{int(value * 100)}%")
    def _update_status(self, text): self.status_label.set_text(text)
    def _append_log(self, line):
        buffer = self.log_text.get_buffer(); end = buffer.get_end_iter(); buffer.insert(end, line + "\n")
        mark = buffer.create_mark(None, buffer.get_end_iter(), True); self.log_text.scroll_mark_onscreen(mark)
    def _install_success(self): self._update_progress(1.0); self._update_status("Установка завершена успешно!"); self.btn_box.set_visible(True); self.log_expander.set_expanded(True)
    def _install_failed(self, code): self._update_status(f"Ошибка установки (код {code})"); self.log_expander.set_expanded(True)
    def _on_reboot(self, _): run_cmd(["reboot"])
    def _on_poweroff(self, _): run_cmd(["poweroff"])
    def can_go_next(self) -> bool: return False
    def can_go_back(self) -> bool: return False

class SoldarchInstaller(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Soldarch Installer")
        self.set_default_size(1024, 768); self.set_resizable(True)
        self.config: Dict[str, Any] = {}
        self.pages = [WelcomePage(self), DiskPage(self), ProfilePage(self), UserPage(self), SummaryPage(self), InstallPage(self)]
        self.current_page_idx = 0
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL); self.set_child(main_box)
        self.stack = Gtk.Stack(); self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT); self.stack.set_vexpand(True); self.stack.set_hexpand(True)
        for i, page in enumerate(self.pages): self.stack.add_named(page, f"page_{i}")
        main_box.append(self.stack)
        nav_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12); nav_box.add_css_class("nav-bar"); nav_box.set_margin_top(12); nav_box.set_margin_bottom(12); nav_box.set_margin_start(24); nav_box.set_margin_end(24)
        self.back_btn = Gtk.Button(label="Назад"); self.back_btn.connect("clicked", lambda _: self.prev_page()); nav_box.append(self.back_btn)
        nav_box.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        self.step_labels = []; steps = ["Приветствие", "Диск", "Профиль", "Пользователь", "Подтверждение", "Установка"]
        for i, step in enumerate(steps):
            lbl = Gtk.Label(label=step); lbl.add_css_class("step-label"); if i == 0: lbl.add_css_class("active"); self.step_labels.append(lbl); nav_box.append(lbl)
            if i < len(steps) - 1: sep = Gtk.Label(label="→"); sep.add_css_class("step-sep"); nav_box.append(sep)
        nav_box.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        self.next_btn = Gtk.Button(label="Далее"); self.next_btn.add_css_class("suggested-action"); self.next_btn.connect("clicked", lambda _: self.next_page()); nav_box.append(self.next_btn)
        main_box.append(nav_box)
        self._load_css(); self._update_nav()

    def _load_css(self):
        css_provider = Gtk.CssProvider()
        if os.path.exists(THEME_CSS): css_provider.load_from_path(THEME_CSS)
        else: css_provider.load_from_data(DEFAULT_CSS.encode())
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def next_page(self):
        if self.current_page_idx < len(self.pages) - 1:
            self.pages[self.current_page_idx].on_leave(); self.current_page_idx += 1
            self.stack.set_visible_child_name(f"page_{self.current_page_idx}")
            self.pages[self.current_page_idx].on_enter(); self._update_nav()

    def prev_page(self):
        if self.current_page_idx > 0:
            self.pages[self.current_page_idx].on_leave(); self.current_page_idx -= 1
            self.stack.set_visible_child_name(f"page_{self.current_page_idx}")
            self.pages[self.current_page_idx].on_enter(); self._update_nav()

    def set_next_enabled(self, enabled: bool): self.next_btn.set_sensitive(enabled)

    def _update_nav(self):
        self.back_btn.set_sensitive(self.current_page_idx > 0)
        can_next = self.pages[self.current_page_idx].can_go_next(); self.next_btn.set_sensitive(can_next)
        for i, lbl in enumerate(self.step_labels):
            if i == self.current_page_idx: lbl.add_css_class("active")
            else: lbl.remove_css_class("active")
            if i < self.current_page_idx: lbl.add_css_class("done")
            else: lbl.remove_css_class("done")
        if self.current_page_idx == len(self.pages) - 1: self.next_btn.set_label("Завершить")
        else: self.next_btn.set_label("Далее")

DEFAULT_CSS = """
.installer-page { background-color: #1e1e2e; color: #cdd6f4; }
.title-1 { font-size: 28px; font-weight: bold; color: #89b4fa; }
.title-3 { font-size: 18px; color: #a6adc8; }
.heading { font-size: 14px; font-weight: bold; color: #cdd6f4; }
.dim-label { color: #6c7086; font-size: 13px; }
.caption { color: #585b70; font-size: 12px; }
.nav-bar { background-color: #181825; border-top: 1px solid #313244; padding: 8px 16px; }
.step-label { color: #6c7086; font-size: 12px; padding: 4px 8px; border-radius: 4px; }
.step-label.active { color: #89b4fa; font-weight: bold; background-color: #313244; }
.step-label.done { color: #a6e3a1; }
.step-sep { color: #313244; margin: 0 4px; }
.profile-card { border: 2px solid #313244; border-radius: 12px; background-color: #181825; transition: all 200ms ease; }
.profile-card:selected { border-color: #89b4fa; background-color: #1e1e2e; }
.profile-card:hover { border-color: #585b70; }
.disk-row { padding: 8px; border-radius: 8px; }
.disk-row:hover { background-color: #313244; }
.anime-video { border-radius: 12px; border: 2px solid #89b4fa; background-color: #11111b; }
.anime-video-small { border-radius: 8px; border: 1px solid #313244; background-color: #11111b; }
.summary-text { font-family: monospace; font-size: 13px; background-color: #181825; border: 1px solid #313244; border-radius: 8px; padding: 16px; }
.log-text { font-family: monospace; font-size: 11px; background-color: #11111b; border: 1px solid #313244; border-radius: 8px; padding: 8px; color: #a6adc8; }
button.suggested-action { background-color: #89b4fa; color: #1e1e2e; font-weight: bold; border-radius: 8px; padding: 8px 24px; }
button.suggested-action:hover { background-color: #74c7ec; }
button:disabled { opacity: 0.5; }
entry.readonly { background-color: #313244; color: #6c7086; }
frame { border: 1px solid #313244; border-radius: 8px; background-color: #181825; }
frame > label { font-weight: bold; color: #89b4fa; padding: 4px 8px; }
checkbutton { font-size: 13px; }
progressbar { min-height: 12px; border-radius: 6px; }
progressbar progress { background-color: #89b4fa; border-radius: 6px; }
progressbar trough { background-color: #313244; border-radius: 6px; }
"""

class SoldarchApp(Gtk.Application):
    def __init__(self): super().__init__(application_id="org.soldarch.installer"); GLib.set_application_name("Soldarch Installer")
    def do_activate(self): win = SoldarchInstaller(self); win.present()

def main(): app = SoldarchApp(); return app.run(sys.argv)
if __name__ == "__main__": sys.exit(main())
