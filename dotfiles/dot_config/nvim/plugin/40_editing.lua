-- Packages
vim.pack.add({
  "https://github.com/nvim-mini/mini.surround",
  "https://github.com/nvim-mini/mini.pairs",
  { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
  { src = "https://github.com/stevearc/conform.nvim" },
  {
    src = "https://github.com/serhez/bento.nvim",
    version = "feat/v2",
  },
  "https://github.com/stevearc/oil.nvim",
  "https://github.com/adriankarlen/plugin-view.nvim",
  "https://github.com/envim-lua/plenary.nvim",
  "https://github.com/ej-shafran/compile-mode.nvim",
  {
    src = "https://github.com/saghen/blink.cmp",
    version = vim.version.range("1.*"),
  },
})

-- Surround

require("mini.surround").setup({
  mappings = {
    add = "ms",
    delete = "md",
    replace = "mr",

    find = "mf",
    find_left = "mF",
    highlight = "mh",

    suffix_last = "l",
    suffix_next = "n",
  },
})

-- Autopairs

-- require("mini.pairs").setup()

vim.pack.add({
  "https://github.com/windwp/nvim-autopairs",
})

local autopairs = require("nvim-autopairs")

autopairs.setup({
  check_ts = true,

  ignored_next_char = "[%w%.]",

  enable_check_bracket_line = true,

  enable_moveright = true,
})

-- Treesitter

require("nvim-treesitter").install({
  "lua",
  "python",
  "go",
  "rust",
  "javascript",
  "typescript",
  "tsx",
  "json",
  "html",
  "css",
  "bash",
  "markdown",
  "vue",
})

vim.api.nvim_create_autocmd("FileType", {
  callback = function()
    pcall(vim.treesitter.start)
  end,
})

-- Formatter

require("conform").setup({
  formatters_by_ft = {
    lua = { "stylua" },

    python = { "ruff_format" },

    javascript = { "prettierd", "prettier", stop_after_first = true },
    typescript = { "prettierd", "prettier", stop_after_first = true },
    javascriptreact = { "prettierd", "prettier", stop_after_first = true },
    typescriptreact = { "prettierd", "prettier", stop_after_first = true },

    go = { "gofmt" },
    rust = { "rustfmt" },
  },

  format_on_save = {
    timeout_ms = 1000,
    lsp_format = "fallback",
  },
})

vim.keymap.set({ "n", "x" }, "\\p", function()
  require("conform").format({
    async = true,
    lsp_format = "fallback",
  })
end, {
  desc = "Format",
})

-- Buffer manager

local map = vim.keymap.set

require("bento").setup({
  max_open_buffers = nil,

  buffer_deletion_metric = "frecency_access",
  buffer_notify_on_delete = true,

  ordering_metric = "access",
  locked_first = false,

  ui = {
    mode = "floating",

    floating = {
      position = "middle-right",
      offset_x = 0,
      offset_y = 0,
      dash_char = "─",
      border = "none",
      label_padding = 1,
      minimal_menu = nil,
      max_rendered_buffers = nil,
    },
  },
})

local api = require("bento.api")

api.register_expand_key(";")
api.register_last_buffer_key(";")
api.register_collapse_key("<Esc>")
api.register_prev_page_key("[")
api.register_next_page_key("]")

api.register_action("open", {
  key = "<CR>",
  action = api.actions.open,
  hl = "DiagnosticVirtualTextHint",
})

api.register_action("delete", {
  key = "<BS>",
  action = api.actions.delete,
  hl = "DiagnosticVirtualTextError",
})

api.register_action("vsplit", {
  key = "|",
  action = api.actions.vsplit,
  hl = "DiagnosticVirtualTextInfo",
})

api.register_action("split", {
  key = "_",
  action = api.actions.split,
  hl = "DiagnosticVirtualTextInfo",
})

api.register_action("lock", {
  key = "*",
  action = api.actions.lock,
  hl = "DiagnosticVirtualTextWarn",
})

api.set_default_action("open")

-- File manager

require("oil").setup({
  view_options = {
    show_hidden = true,
  },
})

vim.keymap.set("n", "<leader>.", "<cmd>Oil<CR>", {
  desc = "Open parent directory",
})

vim.keymap.set("n", "<leader>>", function()
  local win = require("helpers").right_split()
  vim.api.nvim_set_current_win(win)
  vim.cmd("Oil")
end, {
  desc = "Oil in right split",
})

-- Plugin viewer

require("plugin-view").setup()

vim.keymap.set("n", "<leader>op", function()
  require("plugin-view").open()
end)

-- Completion

require("blink.cmp").setup({
  sources = {
    default = {
      "lsp",
      "path",
      "snippets",
      "buffer",
      -- "minuet" здесь НЕТ
    },

    providers = {
      minuet = {
        name = "minuet",
        module = "minuet.blink",
        async = true,
        timeout_ms = 3000,
        score_offset = 50,
      },
    },
  },
  keymap = {
    preset = "enter",

    ["<C-n>"] = { "select_next", "fallback" },
    ["<C-e>"] = { "select_prev", "fallback" },
    ["<C-S-Space>"] = {
      function(cmp)
        return require("minuet").make_blink_map()(cmp)
      end,
    },
    ["<CR>"] = {
      function(cmp)
        return cmp.accept({
          callback = function()
            vim.schedule(function()
              cmp.show_signature()
            end)
          end,
        })
      end,
      "fallback",
    },

    ["<Tab>"] = {
      function(cmp)
        return cmp.accept({
          callback = function()
            vim.schedule(function()
              cmp.show_signature()
            end)
          end,
        })
      end,
      "snippet_forward",
      "fallback",
    },

    ["<S-Tab>"] = {
      "snippet_backward",
      "fallback",
    },
  },

  completion = {
    documentation = {
      auto_show = true,
      auto_show_delay_ms = 200,
    },
  },

  signature = {
    enabled = true,

    window = {
      show_documentation = false,
    },
  },
  cmdline = {
    keymap = {
      preset = "inherit",

      ["<Tab>"] = {
        "select_and_accept",
        "fallback",
      },

      ["<S-Tab>"] = {
        "select_prev",
        "fallback",
      },
    },

    completion = {
      list = {
        selection = {
          preselect = false,
          auto_insert = false,
        },
      },

      menu = {
        auto_show = true,
      },
    },
  },
})

vim.lsp.config("*", {
  capabilities = require("blink.cmp").get_lsp_capabilities({
    textDocument = {
      completion = {
        completionItem = {
          snippetSupport = false,
        },
      },
    },
  }),
})


-- Smart log
vim.pack.add({ "https://github.com/chrisgrieser/nvim-chainsaw" })

require("chainsaw").setup()
