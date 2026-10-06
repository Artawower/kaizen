local M = {}

local ok, kaizen = pcall(require, "kaizen")
if not ok then
  kaizen = {
    layout = "colemak",
    preferred_vcs = "jj",
    nav_left = "h",
    nav_down = "n",
    nav_up = "e",
    nav_right = "i",
    nav_insert = "l",
    line_start = "0",
    line_end = "$",
    vcs_ui = "vl",
    vcs_history = "vh",
    has_colemak_rebinds = function()
      return true
    end,
    shortcuts = {},
    get = function(_, fallback)
      return fallback
    end,
    key = function(_, fallback)
      return fallback
    end,
  }
end
M.kaizen = kaizen

function M.right_split()
  local current = vim.api.nvim_get_current_win()

  vim.cmd("wincmd l")

  local right = vim.api.nvim_get_current_win()

  if right == current then
    vim.cmd("rightbelow vsplit")
    right = vim.api.nvim_get_current_win()
  end

  vim.api.nvim_set_current_win(current)

  return right
end

return M
