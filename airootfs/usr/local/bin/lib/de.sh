#!/usr/bin/env bash
# lib/de.sh — Hyprland и графическое окружение

readonly HYPRLAND_PACKAGES=(
    hyprland swaybg hyprshot
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    hyprpolkitagent
    waybar wofi foot thunar
    xdg-utils firefox
    wl-clipboard
    brightnessctl playerctl mako
    pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber
    pavucontrol
    network-manager-applet nm-connection-editor
    blueman udiskie
    qt5-wayland qt6-wayland qt5ct qt6ct
    noto-fonts noto-fonts-emoji ttf-dejavu ttf-jetbrains-mono-nerd
    mesa vulkan-radeon vulkan-intel
    sddm
    fish
    qt6-declarative qt6-svg
)

# ═══════════════════════════════════════════════════════════
# Установка пакетов
# ═══════════════════════════════════════════════════════════

install_hyprland_packages() {
    ui_step "Установка Hyprland и сопутствующих пакетов"
    log "Hyprland packages: ${HYPRLAND_PACKAGES[*]}"

    if pacman --sysroot "$MOUNTPOINT" -Q jack2 &>/dev/null; then
        ui_info "Удаление конфликтующего jack2 из target..."
        run_cmd pacman --sysroot "$MOUNTPOINT" -Rdd --noconfirm jack2 || true
    fi

    if ! run_cmd pacstrap -K "$MOUNTPOINT" "${HYPRLAND_PACKAGES[@]}"; then
        ui_error "Не удалось установить пакеты Hyprland"
        return 1
    fi

    ui_success "Пакеты Hyprland установлены"
}

# ═══════════════════════════════════════════════════════════
# Конфиги в /etc/skel (копируются автоматически при useradd -m)
# ═══════════════════════════════════════════════════════════

deploy_hyprland_configs() {
    ui_step "Развёртывание конфигов Hyprland"

    local skel="$MOUNTPOINT/etc/skel"
    run_cmd mkdir -p "$skel/.config/hypr"
    run_cmd mkdir -p "$skel/.config/waybar"
    run_cmd mkdir -p "$skel/.config/wofi"
    run_cmd mkdir -p "$skel/.config/fish"
    run_cmd mkdir -p "$skel/.config/foot"
    run_cmd mkdir -p "$skel/.config/mako"

    run_cmd mkdir -p "$MOUNTPOINT/usr/share/sddm/themes/soldatik"
    run_cmd mkdir -p "$MOUNTPOINT/etc/sddm.conf.d"

    run_cmd cp /usr/share/sddm/themes/soldatik/theme.conf \
               "$MOUNTPOINT/usr/share/sddm/themes/soldatik/theme.conf"
    run_cmd cp /usr/share/sddm/themes/soldatik/Main.qml \
               "$MOUNTPOINT/usr/share/sddm/themes/soldatik/Main.qml"

    # Копируем конфиг
    run_cmd cp /etc/sddm.conf.d/10-soldatik.conf \
               "$MOUNTPOINT/etc/sddm.conf.d/10-soldatik.conf"

    run_cmd mkdir -p "$MOUNTPOINT/usr/share/backgrounds"
    run_cmd cp /usr/share/backgrounds/bg1_dark.jpg \
                "$MOUNTPOINT/usr/share/backgrounds/bg1_dark.jpg"
    run_cmd cp /usr/share/backgrounds/bg1_white.jpg \
                "$MOUNTPOINT/usr/share/backgrounds/bg1_white.jpg"
    run_cmd cp /usr/share/backgrounds/bg2_dark.jpg \
                "$MOUNTPOINT/usr/share/backgrounds/bg2_dark.jpg"

    # --- hypr/hyprland.lua ---
    cat > "$skel/.config/hypr/hyprland.lua" <<'EOF'
-- Soldatik Linux — базовая конфигурация Hyprland (Lua API)

------------------
---- MONITORS ----
------------------

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

---------------------
---- MY PROGRAMS ----
---------------------

-- Настройки программ-переменных
local terminal = "foot"
local menu     = "wofi --show drun"
local browser  = "firefox"
local fileManager  = "thunar"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function ()
  hl.exec_cmd("systemctl --user start hyprpolkitagent")
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
  hl.exec_cmd("udiskie --no-notify")
  hl.exec_cmd("waybar")
  hl.exec_cmd("swaybg -i /usr/share/backgrounds/bg1_dark.jpg -m fill")
  hl.exec_cmd("swaync")
  hl.exec_cmd("nm-applet --indicator")
  hl.exec_cmd("blueman-applet")
  hl.exec_cmd("sleep 1 && foot")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GTK_THEME", "Adwaita:dark")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,

        border_size = 2,

        col = {
            active_border   = "rgba(de382bee)",
            inactive_border = "rgba(404040aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled           = false,
            size              = 8,
            passes            = 3,
            vibrancy          = 0.1696,
            new_optimizations = true,
        },
    },

    animations = {
        enabled = true,
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us,ru",
        kb_variant = "",
        kb_model   = "",
        kb_options = "grp:alt_shift_toggle",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot --clipboard-only -m region"))

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + M", hl.dsp.exit())

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

local suppressMaximizeRule = hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

EOF

    # --- foot/foot.ini ---
    cat > "$skel/.config/foot/foot.ini" <<'EOF'
[main]
font=JetBrainsMono Nerd Font:size=12
pad=8x8
initial-window-size-chars=100x28

[colors-dark]
alpha=0.8
background=0a0a0a
foreground=e0e0e0
regular0=1a1a1a
regular1=de382b
regular2=e67e22
regular3=de382b
regular4=e67e22
regular5=de382b
regular6=e67e22
regular7=e0e0e0
bright0=2a2a2a
bright1=e64535
bright2=f09a3e
bright3=e64535
bright4=f09a3e
bright5=e64535
bright6=f09a3e
bright7=ffffff
cursor=e0e0e0 de382b

EOF

    # --- fish/config.fish ---
    cat > "$skel/.config/fish/config.fish" <<'EOF'
# Soldatik Linux fish config

if status is-interactive
  set -g fish_greeting ""

  fastfetch
end

EOF

    # --- mako/config ---
    cat > "$skel/.config/mako/config" <<'EOF'
# Глобальные настройки визуала
font=sans-serif 11
background-color=#0f0f0fee
text-color=#de382b
border-size=2
border-color=#de382bee
border-radius=8
progress-color=over #313244

# Геометрия и поведение
width=350
height=150
margin=20
padding=15
default-timeout=5000

# Стили для разных уровней важности (критерии)
[urgency=high]
border-color=#f38ba8
text-color=#f38ba8
default-timeout=0

EOF

    # --- wofi/style.css ---
    cat > "$skel/.config/wofi/style.css" <<'EOF'
/* Soldatik Linux Wofi Theme */
window {
    margin: 0px;
    border: 2px solid #de382b;
    background-color: #2c2c2c;
    border-radius: 10px;
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 14px;
}

#input {
    margin: 5px;
    border: none;
    color: #e0e0e0;
    background-color: #2c2c2c;
    border-radius: 5px;
    padding: 8px;
}

#inner-box {
    margin: 5px;
    border: none;
    background-color: transparent;
}

#outer-box {
    margin: 5px;
    border: none;
    background-color: transparent;
}

#scroll {
    margin: 0px;
    border: none;
}

#text {
    margin: 5px;
    border: none;
    color: #e0e0e0;
}

#entry:selected {
    background-color: #1c1c1c;
    border-radius: 5px;
}

#text:selected {
    color: #ffffff;
    font-weight: bold;
}
EOF

    # --- waybar/config.jsonc ---
    cat > "$skel/.config/waybar/config.jsonc" <<'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 34,
    "spacing": 4,
    "modules-left": ["hyprland/window", "hyprland/mode"],
    "modules-center": ["hyprland/workspaces"],
    "modules-right": ["tray", "hyprland/language", "pulseaudio", "clock"],

    "hyprland/window": {
        "format": " {title} ",
        "max-length": 40,
        "separate-outputs": true,
        "rewrite": {
             "^\\s*$": " Soldatik Linux "
        }
    },

    "hyprland/workspaces": {
        "disable-scroll": true,
        "all-outputs": true,
        "format": "{name}",
        "persistent-workspaces": {
            "*": 5 
        }
    },

    "tray": {
        "spacing": 10
    },

    "hyprland/language": {
        "format-en": "ENG",
        "format-ru": "RUS",
        "on-click": "hyprctl switchxkblayout current next"
    },
    
    "pulseaudio": {
        "format": " {volume}%",
        "format-muted": " {volume}%",
        "on-click": "pavucontrol"
    },

    "clock": {
        "format": "{:%H:%M}",
        "format-alt": "{:%d.%m.%Y}",
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"
    }
}

EOF

    # --- waybar/style.css ---
    cat > "$skel/.config/waybar/style.css" <<'EOF'
/* Основные настройки всей панели */
window#waybar {
    background-color: #111111; /* Чистый черный фон */
    color: #a5a5a5;            /* Белый текст */
    font-family: "JetBrainsMono Nerd Font";
    font-size: 13px;
}

#workspaces,
#window,
#clock,
#cpu,
#memory,
#network,
#pulseaudio,
#language,
#tray {
    padding: 0px 4px;
    margin: 4px 2px;
    border-radius: 4px;
}

#workspaces {
    padding: 0px 4px;
    background-color: #111111;
}

#workspaces button {
    padding: 0px 8px;
    color: #524d4d;
    background: transparent;
    background-color: transparent;
    box-shadow: none;
    border: none;
}

#workspaces button.active {
    color: #a5a5a5;
    background-color: #222222;
    border-radius: 4px;
}

#workspaces button:hover {
    background: transparent;
    background-color: #1c1c1c;
    box-shadow: none;
    text-shadow: none;
    color: #cccbcb;
    border-radius: 4px;
    transition: none;
}

#workspaces button.active:hover {
    background-color: #292929;
}

#cpu.critical,
#memory.critical,
#pulseaudio.muted {
    background-color: #222222;
    color: #ffffff;
}

#tray {
    background-color: transparent;
    border: none;
}

EOF

    # Права
    run_cmd chown -R root:root "$skel/.config"
    run_cmd sh -c "find $skel/.config -type d -exec chmod 755 {} \\;"
    run_cmd sh -c "find $skel/.config -type f -exec chmod 644 {} \\;"

    ui_success "Конфиги Hyprland развёрнуты в /etc/skel"
}

# ═══════════════════════════════════════════════════════════
# Сервисы (SDDM, PipeWire) внутри chroot
# ═══════════════════════════════════════════════════════════

enable_hyprland_services() {
    ui_step "Включение сервисов графики"

    run_chroot_sh "systemctl enable sddm"
    run_chroot_sh "systemctl --global enable pipewire.socket"
    run_chroot_sh "systemctl --global enable pipewire-pulse.socket"
    run_chroot_sh "systemctl --global enable wireplumber.service"

    ui_success "SDDM и PipeWire включены"
}

# ═══════════════════════════════════════════════════════════
# Общая функция
# ═══════════════════════════════════════════════════════════

run_de_setup() {
    install_hyprland_packages || return 1
    deploy_hyprland_configs || return 1
    # enable_hyprland_services вызывается в chroot.sh после users
}