return {
  'refractalize/oil-git-status.nvim',
  dependencies = {
    'rgarber11/oil.nvim',
    branch = 'rgarber/local-changes_to_oil',
    opts = {
      view_options = {
        show_hidden = true,
      },
      win_options = {
        signcolumn = 'yes:2',
      },
    },
    dependencies = { 'nvim-tree/nvim-web-devicons' },
  },
  config = true,
}
