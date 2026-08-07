local wezterm = require 'wezterm'

local config = {
  color_scheme = 'Monokai',
  window_background_opacity = 0.9,
  macos_window_background_blur = 0,
  text_background_opacity = 0.9,
  window_decorations = 'NONE',
}

local is_windows = wezterm.target_triple:find('windows') ~= nil

if is_windows then
  config.default_prog = { 'wsl.exe', '--cd', '~' }
  config.launch_menu = {}
  for _, dom in ipairs(wezterm.default_wsl_domains()) do
    table.insert(config.launch_menu, {
      label = dom.name,
      args = { 'wsl.exe', '-d', dom.distribution, '--cd', '~' },
      domain = { DomainName = 'local' },
    })
  end
  table.insert(config.launch_menu, {
    label = 'PowerShell',
    args = { 'powershell.exe' },
    domain = { DomainName = 'local' },
  })
end

wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

wezterm.on('format-tab-title', function(tab)
  local pane = tab.active_pane
  local title = pane.title
  return wezterm.format {
    { Text = title },
  }
end)

wezterm.on('new-tab-button-click', function(window, pane)
  if is_windows then
    window:perform_action(wezterm.action.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS' }, pane)
  else
    window:perform_action(wezterm.action.SpawnTab, pane)
  end
  return false
end)

config.keys = {
  {
    key = 'R',
    mods = 'CTRL|SHIFT',
    action = wezterm.action_callback(function(win, _)
      win:toast_notification('wezterm', 'Config reloaded')
      wezterm.reload_configuration()
    end),
  },
  { key = 'W', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true }, },
  { key = 'Q', mods = 'CTRL|SHIFT', action = wezterm.action.QuitApplication },
  {
    key = 'T',
    mods = 'CTRL|SHIFT',
    action = is_windows
        and wezterm.action.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS' }
        or wezterm.action.SpawnTab,
  },
  { key = '1', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(0) },
  { key = '2', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(1) },
  { key = '3', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(2) },
  { key = '4', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(3) },
  { key = '5', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(4) },
  { key = '6', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(5) },
  { key = '7', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(6) },
  { key = '8', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(7) },
  { key = '9', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTab(8) },
}

return config
