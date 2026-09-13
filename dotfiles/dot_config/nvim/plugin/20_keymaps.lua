local map = vim.keymap.set

vim.pack.add({
  {
    src = "https://github.com/folke/which-key.nvim",
    data = {
      event = "DeferredUIEnter",
      cmd = "WhichKey",
      after = function()
        require("which-key").setup({
          delay = 400,
        })
      end,
    },
  },
  {
    src = "https://github.com/nvim-mini/mini.jump2d",
    data = {
      after = function()
        require("mini.jump2d").setup({
          labels = "arstneioqwfpghjluyzxcvbkm",
        })
      end,
    },
  },
  {
    src = "https://github.com/s1n7ax/nvim-window-picker",
    version = vim.version.range("2.*"),
    data = {
      after = function()
        require("window-picker").setup({
          hint = "floating-big-letter",
          filter_rules = {
            include_current_win = false,
            autoselect_one = true,
            include_unfocusable_windows = true,
            bo = {
              filetype = { "notify" },
              buftype = { "terminal" },
            },
          },
        })
      end,
    },
  },
}, { load = require("lz.n").load })

map("n", "<leader>?", function()
  require("lz.n").trigger_load("which-key.nvim")
  require("which-key").show({ global = false })
end, {
  desc = "Keymaps",
})

map({ "n", "x" }, "n", "gj", { desc = "Down" })
map({ "n", "x" }, "e", "gk", { desc = "Up" })
map({ "n", "x" }, "i", "l", { desc = "Right" })

map("n", "l", "i", { desc = "Insert" })
map("n", "L", "I", { desc = "Insert at line start" })

map("x", "L", "<Esc>`<i", {
  desc = "Insert before selection",
})

map("x", "l", "<Esc>`>a", {
  desc = "Insert after selection",
  nowait = true,
})

map({ "n", "x" }, "j", "e", { desc = "Next word end" })
map({ "n", "x" }, "J", "E", { desc = "Next WORD end" })

map({ "n", "x" }, "k", "n", { desc = "Next search result" })
map({ "n", "x" }, "K", "N", { desc = "Previous search result" })

map("n", "E", vim.lsp.buf.hover, {
  desc = "Hover",
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    map("n", "<D-a>", "ggVG", {
      desc = "Select entire buffer",
    })
  end,
})

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

map({ "n", "x" }, "+", function()
  vim.treesitter.select("parent")
end, {
  desc = "Expand selection",
})

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

map("n", "mm", "<Plug>(MatchitNormalForward)", {
  desc = "Matching bracket",
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

  vim.cmd("normal! \27")

  vim.fn.setreg("/", pattern)
  vim.o.hlsearch = true

  vim.cmd("normal! n")
end

map("x", "/", visual_search, {
  desc = "Search selection",
})

map({ "n", "x" }, "c", '"_c')
map("n", "C", '"_C')
map("n", "cc", '"_cc')

map("x", "p", '"_dP', {
  desc = "Paste without yanking replaced text",
})

map("n", "d", "x", {
  desc = "Delete character",
})

map("n", "U", "<C-r>", { desc = "Redo" })

map("i", "<M-BS>", "<C-w>", {
  desc = "Delete previous word",
})

map("c", "<M-BS>", "<C-w>", {
  desc = "Delete previous word",
})

map({ "n", "i", "x" }, "<D-s>", "<cmd>write<CR>", {
  desc = "Save",
})

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

map("n", "<leader>x", "<cmd>bdelete<CR>", {
  desc = "Close buffer",
})


map("n", "<leader>Q", "<cmd>qa<CR>", {
  desc = "Quit all",
})

map("n", "<leader>wv", "<cmd>vsplit<CR>", {
  desc = "Vertical split",
})

map("n", "<leader>wh", "<cmd>split<CR>", {
  desc = "Horizontal split",
})

map("n", "<C-w>h", "<C-w>h", {
  desc = "Window left",
})

map("n", "<C-w>n", "<C-w>j", {
  desc = "Window down",
})

map("n", "<C-w>e", "<C-w>k", {
  desc = "Window up",
})

map("n", "<C-w>i", "<C-w>l", {
  desc = "Window right",
})

map("n", "<leader>wr", "<C-w>r", {
  desc = "Rotate windows",
})

local function toggle_maximize()
  if vim.t.maximize_restore then
    vim.cmd(vim.t.maximize_restore)
    vim.t.maximize_restore = nil
    return
  end

  vim.t.maximize_restore = vim.fn.winrestcmd()

  vim.cmd("wincmd _")
  vim.cmd("wincmd |")
end

map("n", "<leader>wf", toggle_maximize, {
  desc = "Toggle window maximize",
})

local function select_word()
  vim.cmd("normal! viw")
end

local function jump_word()
  local char = vim.fn.getcharstr()

  if char == "\27" then
    return
  end

  require("lz.n").trigger_load("mini.jump2d")
  MiniJump2d.start({
    spotter = MiniJump2d.gen_spotter.vimpattern(
      "\\c\\<" .. vim.pesc(char)
    ),
  })
  select_word()
end

local function jump_char()
  local char = vim.fn.getcharstr()

  if char == "\27" then
    return
  end

  require("lz.n").trigger_load("mini.jump2d")
  MiniJump2d.start({
    spotter = MiniJump2d.gen_spotter.vimpattern(
      "\\V" .. vim.fn.escape(char, "\\")
    ),
  })

  select_word()
end

map({ "n", "x" }, "f", jump_word, {
  desc = "Jump to word",
})

map({ "n", "x" }, "F", jump_char, {
  desc = "Jump to character",
})

local function pick_window()
  require("lz.n").trigger_load("nvim-window-picker")
  local win = require("window-picker").pick_window()

  if win then
    vim.api.nvim_set_current_win(win)
  end
end

map({ "n", "i" }, "<D-.>", pick_window, {
  desc = "Pick window",
})

map("n", "<C-n>", function()
  vim.diagnostic.jump({ count = 1 })
end, {
  desc = "Next diagnostic",
})

map("n", "<C-e>", function()
  vim.diagnostic.jump({ count = -1 })
end, {
  desc = "Previous diagnostic",
})

vim.opt.langmap = table.concat({
  "й;q",
  "ц;w",
  "у;f",
  "к;p",
  "е;g",
  "н;j",
  "г;l",
  "ш;u",
  "щ;y",
  "з;\\;",

  "ф;a",
  "ы;r",
  "в;s",
  "а;t",
  "п;d",
  "р;h",
  "о;n",
  "л;e",
  "д;i",
  "ж;o",

  "я;z",
  "ч;x",
  "с;c",
  "м;v",
  "и;b",
  "т;k",
  "ь;m",
}, ",")
