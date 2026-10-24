local M = {}

function M.map(mode, keys, action, opts)
  for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
    vim.keymap.set(mode, key, action, opts)
  end
end

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
