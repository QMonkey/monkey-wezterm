local wezterm = require 'wezterm'
local config = {
  color_scheme = 'Monokai',
  window_background_opacity = 0.9,
  macOS_window_background_blur = 0,
  text_background_opacity = 0.9,
  window_decorations = 'NONE',
}

wezterm.on('format-tab-title', function(tab)
  local pane = tab.active_pane
  local title = pane.title
  return wezterm.format {
    { Text = title },
  }
end)

if wezterm.target_triple:find('windows') then
  config.default_domain = 'WSL:default~'
end

wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

config.keys = {
  {
    key = 'R',
    mods = 'CTRL|SHIFT',
    action = wezterm.action_callback(function(win, _)
      win:toast_notification('wezterm', 'Config reloaded')
      wezterm.reload_configuration()
    end)
  },
  { key = 'W', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentTab { confirm = true } },
  { key = 'Q', mods = 'CTRL|SHIFT', action = wezterm.action.QuitApplication },
}

return config
