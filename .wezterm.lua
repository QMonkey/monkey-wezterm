local wezterm = require 'wezterm'
local tabline = wezterm.plugin.require 'https://github.com/michaelbrusegard/tabline.wez'

local config = wezterm.config_builder()

config.color_scheme = 'Monokai'
config.window_background_opacity = 0.9
config.macos_window_background_blur = 0
config.text_background_opacity = 0.9
config.window_decorations = 'NONE'

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

tabline.setup {
  options = {
    theme = config.colors,
    icons_enabled = false,
    tabs_enabled = true,
    section_separators = '',
    component_separators = '',
    tab_separators = '',
  },
  sections = {
    tabline_a = { 'mode' },
    tabline_b = { 'workspace' },
    tabline_c = { ' ' },
    tab_active = { 'index', { 'parent', padding = 0 }, '/', 'cwd' },
    tab_inactive = { 'index', { 'process', padding = { left = 0, right = 1 } } },
    tabline_x = {},
    tabline_y = {},
    tabline_z = { 'domain' },
  },
  extensions = {},
}
tabline.apply_to_config(config)

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
    end),
  },
  { key = 'W', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = true }, },
  { key = 'Q', mods = 'CTRL|SHIFT', action = wezterm.action.QuitApplication },
  {
    key = 'U',
    mods = 'CTRL|SHIFT',
    action = wezterm.action_callback(function(win, _)
      win:toast_notification('wezterm', 'Updating plugins...')
      wezterm.plugin.update_all()
      win:toast_notification('wezterm', 'Plugins updated, reloading config')
      wezterm.reload_configuration()
    end),
  },
  {
    key = 'O',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.QuickSelect,
  },
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
