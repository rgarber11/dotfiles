return {
  'rgarber11/hyprland-keymap-picker.nvim',
  dependencies = 'nvim-lua/plenary.nvim',
  config = function()
    if os.getenv 'HYPRLAND_INSTANCE_SIGNATURE' then
      require('hyprland-keymap-picker').setup {}
    end
  end,
}
