local wezterm = require 'wezterm'

local config = {
  color_scheme = 'Monokai',
  window_background_opacity = 0.9,
  macOS_window_background_blur = 0,
  text_background_opacity = 0.9,
  window_decorations = 'NONE',
}

if wezterm.target_triple:find('windows') then
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

local function split_chooser(direction)
  local choices = {}
  for i, item in ipairs(config.launch_menu or {}) do
    choices[i] = { id = tostring(i), label = item.label }
  end
  return wezterm.action.InputSelector {
    title = 'Split ' .. (direction == 'Right' and 'Vertically' or 'Horizontally'),
    choices = choices,
    action = wezterm.action_callback(function(win, pane, id)
      local item = config.launch_menu[tonumber(id)]
      if item then
        win:perform_action(
          wezterm.action.SplitPane {
            direction = direction,
            command = { args = item.args, domain = item.domain },
          },
          pane
        )
      end
    end),
  }
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
  window:perform_action(wezterm.action.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS' }, pane)
  return false
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
  {
    key = 'W',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.CloseCurrentPane { confirm = true },
  },
  { key = 'Q', mods = 'CTRL|SHIFT', action = wezterm.action.QuitApplication },
  {
    key = 'T',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS' },
  },
  { key = 'V', mods = 'CTRL|SHIFT|ALT', action = split_chooser('Right') },
  { key = 'H', mods = 'CTRL|SHIFT|ALT', action = split_chooser('Down') },
}

return config

