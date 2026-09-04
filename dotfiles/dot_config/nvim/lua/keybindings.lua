vim.pack.add({
  { src = "https://github.com/folke/which-key.nvim" },
})

require("which-key").setup({
  delay = 400
})

local map = vim.keymap.set

-- WhichKey
map("n", "<leader>?", function()
  require("which-key").show({ global = false })
end, {
  desc = "Keymaps",
})

-- Colemak navigation
map({ "n", "x" }, "n", "gj", { desc = "Down" })
map({ "n", "x" }, "e", "gk", { desc = "Up" })
map({ "n", "x" }, "i", "l", { desc = "Right" })

-- Insert
map("n", "l", "i", { desc = "Insert" })
map("n", "L", "I", { desc = "Insert at line start" })
map("x", "l", "<Esc>`<i", {
  desc = "Insert before selection",
})

map("x", "L", "<Esc>`>a", {
  desc = "Insert after selection",
  nowait = true,
})

-- Word movement
map({ "n", "x" }, "j", "e", { desc = "Next word end" })
map({ "n", "x" }, "J", "E", { desc = "Next WORD end" })

-- Search navigation
map({ "n", "x" }, "k", "n", { desc = "Next search result" })
map({ "n", "x" }, "K", "N", { desc = "Previous search result" })

-- LSP hover
map("n", "E", vim.lsp.buf.hover, {
  desc = "Hover",
})

function visual_search()
  local lines = vim.fn.getregion(
    vim.fn.getpos("v"),
    vim.fn.getpos("."),
    { type = vim.fn.mode() }
  )

  if #lines == 0 then
    return
  end

  for i, line in ipairs(lines) do
    lines[i] = vim.fn.escape(line, "\\")
  end

  local pattern = "\\V" .. table.concat(lines, "\\n")

  -- Leave selection
  vim.cmd("normal! \27")

  vim.fn.setreg("/", pattern)
  vim.o.hlsearch = true

  -- Go to next occurrence
  vim.cmd("normal! n")
end

map("x", "/", visual_search, {
  desc = "Search selection",
})


-- Matching bracket
map("n", "mm", "<Plug>(MatchitNormalForward)", {
  desc = "Matching bracket",
})

-- Select entire buffer
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    map("n", "<D-a>", "ggVG", {
      desc = "Select entire buffer",
    })
  end,
})

-- Text objects
map("n", "mi", "vi", {
  desc = "Select inside text object",
})

map("x", "mi", "i", {
  desc = "Select inside text object",
})

map("n", "ma", "va", {
  desc = "Select around text object",
})

map("x", "ma", "a", {
  desc = "Select around text object",
})

-- Buffer navigation
map("n", "<M-[>", "<cmd>bprevious<CR>", {
  desc = "Previous buffer",
})

map("n", "<M-]>", "<cmd>bnext<CR>", {
  desc = "Next buffer",
})

map("n", "<leader>[", "<cmd>bprevious<CR>", {
  desc = "Previous buffer",
})

map("n", "<leader>]", "<cmd>bnext<CR>", {
  desc = "Next buffer",
})

map("n", "<leader>q", "<cmd>bdelete<CR>", {
  desc = "Close buffer",
})

map("n", "<leader>Q", "<cmd>qa<CR>", {
  desc = "Quit all",
})

-- Window splits
map("n", "<leader>wv", "<cmd>vsplit<CR>", {
  desc = "Vertical split",
})

map("n", "<leader>wh", "<cmd>split<CR>", {
  desc = "Horizontal split",
})


-- Save
map({ "n", "i", "x" }, "<D-s>", "<cmd>write<CR>", {
  desc = "Save",
})

-- Selection
-- Expand selection
map({ "n", "x" }, "+", function()
  vim.treesitter.select("parent")
end, {
  desc = "Expand selection",
})

-- Shrink selection
map("x", "-", function()
  vim.treesitter.select("child")
end, {
  desc = "Shrink selection",
})

map("n", "x", "V", {
  desc = "Select line",
})

map("x", "x", "j", {
  desc = "Select next line",
})

map("x", "X", "k", {
  desc = "Select previous line",
})

-- Editing
map("i", "<M-BS>", "<C-w>", {
  desc = "Delete previous word",
})

map("c", "<M-BS>", "<C-w>", {
  desc = "Delete previous word",
})

vim.keymap.set('n', 'U', '<C-r>', { desc = 'Redo' })
