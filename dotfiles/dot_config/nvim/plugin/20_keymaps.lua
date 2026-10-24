local map = require("helpers").map

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
          labels = "asdfghjklqwertyuiopzxcvbnm",
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
          },
          filter_func = function(windows, rules)
            local current = vim.api.nvim_get_current_win()
            return vim.tbl_filter(function(win)
              local config = vim.api.nvim_win_get_config(win)
              local buf = vim.api.nvim_win_get_buf(win)
              return (rules.include_current_win or win ~= current)
                and config.relative == ""
                and not config.external
                and config.focusable
                and not vim.wo[win].previewwindow
                and vim.bo[buf].buftype == ""
            end, windows)
          end,
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

map({ "n", "x" }, "j", "gj", { desc = "Down" })
map({ "n", "x" }, "k", "gk", { desc = "Up" })

map("n", "K", vim.lsp.buf.hover, {
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

map("n", { "<leader>[", "<leader>х" }, "<cmd>bprevious<CR>", {
  desc = "Previous buffer",
})

map("n", { "<leader>]", "<leader>ъ" }, "<cmd>bnext<CR>", {
  desc = "Next buffer",
})

map({ "n", "i", "x" }, "<D-w>", "<cmd>close<CR>", { desc = "Close pane" })
map({ "n", "i", "x" }, "<D-ц>", "<cmd>close<CR>", { desc = "Close pane" })

map("n", { "<leader>wq", "<leader>цй" }, "<cmd>close<CR>", {
  desc = "Close pane",
})

map("n", { "<leader>q", "<leader>й" }, "<cmd>bdelete<CR>", {
  desc = "Close buffer",
})

map("n", { "<leader>x", "<leader>ч" }, "<cmd>bdelete<CR>", {
  desc = "Close buffer",
})

map("n", { "<leader>Q", "<leader>Й" }, "<cmd>qa<CR>", {
  desc = "Quit all",
})

map("n", { "<leader>wv", "<leader>цм" }, "<cmd>vsplit<CR>", {
  desc = "Vertical split",
})

map("n", { "<leader>wh", "<leader>цр" }, "<cmd>split<CR>", {
  desc = "Horizontal split",
})

map("n", "<C-w>h", "<C-w>h", {
  desc = "Window left",
})

map("n", "<C-w>j", "<C-w>j", {
  desc = "Window down",
})

map("n", "<C-w>k", "<C-w>k", {
  desc = "Window up",
})

map("n", "<C-w>l", "<C-w>l", {
  desc = "Window right",
})

map("n", { "<leader>wr", "<leader>цы" }, "<C-w>r", {
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

map("n", { "<leader>wf", "<leader>цу" }, toggle_maximize, {
  desc = "Toggle window maximize",
})

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

map({ "n", "i" }, { "<D-.>", "<D-ю>" }, pick_window, {
  desc = "Pick window",
})

map("n", "<C-j>", function()
  vim.diagnostic.jump({ count = 1 })
end, {
  desc = "Next diagnostic",
})

map("n", "<C-k>", function()
  vim.diagnostic.jump({ count = -1 })
end, {
  desc = "Previous diagnostic",
})

map("n", "]d", function()
  vim.diagnostic.jump({ count = 1 })
end, {
  desc = "Next diagnostic",
})

map("n", "[d", function()
  vim.diagnostic.jump({ count = -1 })
end, {
  desc = "Previous diagnostic",
})

vim.opt.langmap = table.concat({
  "ё;`",
  "Ё;~",
  "й;q",
  "Й;Q",
  "ц;w",
  "Ц;W",
  "у;f",
  "У;F",
  "к;p",
  "К;P",
  "е;g",
  "Е;G",
  "н;j",
  "Н;J",
  "г;l",
  "Г;L",
  "ш;u",
  "Ш;U",
  "щ;y",
  "Щ;Y",
  "з;\\;",
  "З;:",
  "х;[",
  "Х;{",
  "ъ;]",
  "Ъ;}",
  "ф;a",
  "Ф;A",
  "ы;r",
  "Ы;R",
  "в;s",
  "В;S",
  "а;t",
  "А;T",
  "п;d",
  "П;D",
  "р;h",
  "Р;H",
  "о;n",
  "О;N",
  "л;e",
  "Л;E",
  "д;i",
  "Д;I",
  "ж;o",
  "Ж;O",
  "э;'",
  "Э;\"",
  "я;z",
  "Я;Z",
  "ч;x",
  "Ч;X",
  "с;c",
  "С;C",
  "м;v",
  "М;V",
  "и;b",
  "И;B",
  "т;k",
  "Т;K",
  "ь;m",
  "Ь;M",
  "б;\\,",
  "Б;<",
  "ю;.",
  "Ю;>",
}, ",")
vim.opt.langremap = false
