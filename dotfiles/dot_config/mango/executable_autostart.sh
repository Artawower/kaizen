#!/usr/bin/env bash

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

if command -v systemctl >/dev/null; then
	systemctl --user unset-environment QT_PLUGIN_PATH
fi

if command -v dbus-update-activation-environment >/dev/null; then
	dbus-update-activation-environment --systemd \
		WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE MANGO_INSTANCE_SIGNATURE \
		__EGL_VENDOR_LIBRARY_FILENAMES __GLX_VENDOR_LIBRARY_NAME \
		LIBGL_DRIVERS_PATH GBM_BACKENDS_PATH VDPAU_DRIVER_PATH \
		VK_ICD_FILENAMES VK_LAYER_PATH XDG_DATA_DIRS
fi

xremap_bin=/usr/bin/xremap
if [[ ! -x "$xremap_bin" ]]; then
	xremap_bin="$HOME/.local/bin/xremap-wlroots"
fi
if [[ -x "$xremap_bin" ]]; then
	pkill -x xremap 2>/dev/null || true
	pkill -x xremap-wlroots 2>/dev/null || true
	"$xremap_bin" --device 'Apple SPI Keyboard' --watch=config,device "$HOME/.config/xremap/config.yml" &
fi

if command -v ydotoold >/dev/null; then
	ydotoold &
fi

if command -v vicinae >/dev/null; then
	vicinae server &
fi

if command -v noctalia >/dev/null; then
	noctalia --daemon
fi

if command -v hyprvoice >/dev/null; then
	hyprvoice serve &
fi

if command -v handy >/dev/null && ! pgrep -x handy >/dev/null; then
	handy --start-hidden &
fi

if command -v emacs >/dev/null && command -v emacsclient >/dev/null; then
	if ! emacsclient --eval t >/dev/null 2>&1; then
		emacs --daemon &
	fi
fi

if command -v swayidle >/dev/null; then
	swayidle -w \
		timeout 300 "noctalia msg session lock" \
		timeout 900 "systemctl suspend" \
		before-sleep "noctalia msg session lock" &
fi

if command -v sway-audio-idle-inhibit >/dev/null; then
	sway-audio-idle-inhibit &
fi

if command -v wl-clip-persist >/dev/null; then
	wl-clip-persist --clipboard regular --reconnect-tries 0 &
fi

if command -v wl-paste >/dev/null && command -v cliphist >/dev/null; then
	wl-paste --type text --watch cliphist store &
	wl-paste --type image --watch cliphist store &
fi
