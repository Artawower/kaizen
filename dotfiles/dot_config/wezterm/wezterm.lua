local wezterm = require "wezterm"
local config = {}

local theme_config = {
  window_themes = {},
  themes = {
    "Catppuccin Latte",
    "Tokyo Night",
    "Catppuccin Frappe",
    "Builtin Solarized Light",
    "Builtin Solarized Dark",
  },
}

function theme_config.get_appearance_themes()
  return theme_config.themes
end

function theme_config.get_initial_theme_name()
  if wezterm.gui and wezterm.gui.get_appearance then
    local appearance = wezterm.gui.get_appearance()
    if appearance:find("Dark") then
      return "Tokyo Night"
    end
  end

  return "Catppuccin Latte"
end

function theme_config.get_theme_overrides(theme_name)
  return { color_scheme = theme_name }
end

function theme_config.apply_theme_to_window(window, theme_name)
  theme_config.window_themes[window:window_id()] = theme_name
  window:set_config_overrides(theme_config.get_theme_overrides(theme_name))
end

local function switch_theme(window, pane)
  local themes = theme_config.get_appearance_themes()
  local window_id = window:window_id()
  local current_theme = theme_config.window_themes[window_id]
  local next_index = 1

  for index, theme_name in ipairs(themes) do
    if theme_name == current_theme then
      next_index = index % #themes + 1
      break
    end
  end

  theme_config.apply_theme_to_window(window, themes[next_index])
end

config.font = wezterm.font("JetBrains Mono", { weight = 400 })
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.9
config.macos_window_background_blur = 25

if wezterm.target_triple:find("linux") then
  config.font_size = 12.0
else
  config.font_size = 14.0
end


config.use_fancy_tab_bar = false
config.enable_kitty_keyboard = true
config.enable_kitty_graphics = true
config.window_padding = {
  left = 32,
  right = 32,
  top = 32,
  bottom = 32
}
config.enable_tab_bar = false
config.enable_csi_u_key_encoding = true

local act = wezterm.action

if wezterm.target_triple:find("linux") then
  config.front_end = "OpenGL"
  config.enable_wayland = true
  local current_path = os.getenv("PATH") or ""
  config.set_environment_variables = {
    PATH = current_path .. ":" .. wezterm.home_dir .. "/.config/bin",
  }
end

if not wezterm.target_triple:find("linux") then
  local current_path = os.getenv("PATH") or ""
  local home = os.getenv("HOME") or ""
  local my_paths = "/opt/homebrew/bin:" .. home .. "/.nix-profile/bin:/usr/local/bin:" .. current_path

  config.set_environment_variables = {
    PATH = my_paths
  }
end

wezterm.on(
  "window-config-reloaded",
  function(window, pane)
    local window_id = window:window_id()
    local current_theme = theme_config.window_themes[window_id]

    if current_theme then
      theme_config.apply_theme_to_window(window, current_theme)
    else
      local themes = theme_config.get_appearance_themes()
      local theme_name = themes[(window_id % #themes) + 1]
      theme_config.apply_theme_to_window(window, theme_name)
    end
  end
)

wezterm.on(
  "window-close",
  function(window, pane)
    theme_config.window_themes[window:window_id()] = nil
  end
)

local initial_overrides = theme_config.get_theme_overrides(theme_config.get_initial_theme_name())
config.color_scheme = initial_overrides.color_scheme
config.colors = initial_overrides.colors

config.keys = {
  {
    key = "T",
    mods = "CMD|SHIFT",
    action = wezterm.action_callback(
      function(window, pane)
        local themes = theme_config.get_appearance_themes()
        math.randomseed(os.time())
        local theme_name = themes[math.random(#themes)]
        theme_config.apply_theme_to_window(window, theme_name)
      end
    )
  },
  {
    key = "w",
    mods = "CMD",
    action = wezterm.action.CloseCurrentPane { confirm = true }
  },
  {
    key = "c",
    mods = "CMD",
    action = wezterm.action.CopyTo("Clipboard")
  },
  {
    key = "v",
    mods = "CMD",
    action = wezterm.action.PasteFrom("Clipboard")
  },
  {
    key = "RightArrow",
    mods = "CMD|SHIFT",
    action = wezterm.action.MoveTabRelative(1)
  },
  {
    key = "LeftArrow",
    mods = "CMD|SHIFT",
    action = wezterm.action.MoveTabRelative(-1)
  },
  {
    key = "`",
    mods = "CTRL",
    action = act.SendKey { key = "b", mods = "CTRL" }
  },
  {
    key = "~",
    mods = "CTRL|SHIFT",
    action = act.SendKey { key = "b", mods = "CTRL" }
  },
  {
    key = "f",
    mods = "CMD",
    action = wezterm.action.DisableDefaultAssignment
  },
  {
    key = "r",
    mods = "CMD|SHIFT",
    action = wezterm.action.ReloadConfiguration
  },
  {
    key = "y",
    mods = "CMD|SHIFT",
    action = wezterm.action_callback(switch_theme)
  }
}

config.default_prog = { "zellij" }
-- config.set_environment_variables = {
--   PATH = "<home>/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
-- }

return config
