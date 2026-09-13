local map = vim.keymap.set

local treesitter_parsers = {
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
}

local treesitter_filetypes = {
  bash = true,
  css = true,
  go = true,
  html = true,
  javascript = true,
  javascriptreact = true,
  json = true,
  jsonc = true,
  lua = true,
  markdown = true,
  markdown_inline = true,
  python = true,
  rust = true,
  scss = true,
  sh = true,
  typescript = true,
  typescriptreact = true,
  vue = true,
  zsh = true,
}

vim.pack.add({
  "https://github.com/nvim-mini/mini.surround",
  "https://github.com/meatballs/vim-xonsh",
  {
    src = "https://github.com/serhez/bento.nvim",
    version = "feat/v2",
  },
  {
    src = "https://github.com/saghen/blink.cmp",
    version = vim.version.range("1.*"),
  },
  "https://github.com/nvim-lua/plenary.nvim",
})

vim.pack.add({
  {
    src = "https://github.com/windwp/nvim-autopairs",
    data = {
      event = "InsertEnter",
      after = function()
        require("nvim-autopairs").setup({
          check_ts = true,
          ignored_next_char = "[%w%.]",
          enable_check_bracket_line = true,
          enable_moveright = true,
        })
      end,
    },
  },
  {
    src = "https://github.com/nvim-treesitter/nvim-treesitter",
    data = {
      event = "DeferredUIEnter",
      cmd = { "TSInstall", "TSUpdate", "TSUpdateSync", "TSUninstall" },
      after = function()
        require("nvim-treesitter").install(treesitter_parsers)
      end,
    },
  },
  {
    src = "https://github.com/stevearc/conform.nvim",
    data = {
      event = "BufWritePre",
      cmd = "ConformInfo",
      after = function()
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
      end,
    },
  },
  {
    src = "https://github.com/stevearc/oil.nvim",
    data = {
      cmd = "Oil",
      after = function()
        require("oil").setup({
          view_options = {
            show_hidden = true,
          },
          keymaps = {
            ["<leader>sd"] = {
              desc = "Sort by mtime",
              callback = function()
                require("oil").set_sort({ { "mtime", "desc" }, { "name", "asc" } })
              end,
            },
            ["<leader>sn"] = {
              desc = "Sort by name",
              callback = function()
                require("oil").set_sort({ { "type", "asc" }, { "name", "asc" } })
              end,
            },
          },
        })
      end,
    },
  },
  {
    src = "https://github.com/adriankarlen/plugin-view.nvim",
    data = {
      cmd = { "PluginView", "PluginViewOpen" },
      after = function()
        require("plugin-view").setup()
      end,
    },
  },
  {
    src = "https://github.com/ej-shafran/compile-mode.nvim",
    data = {
      cmd = {
        "Compile",
        "Recompile",
        "NextError",
        "PrevError",
        "CurrentError",
        "FirstError",
        "QuickfixErrors",
      },
    },
  },
  {
    src = "https://github.com/chrisgrieser/nvim-chainsaw",
    data = {
      cmd = "Chainsaw",
      after = function()
        require("chainsaw").setup()
      end,
    },
  },
  {
    src = "https://github.com/ii14/neorepl.nvim",
    data = {
      cmd = "Repl",
    },
  },
}, { load = require("lz.n").load })

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

vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    if treesitter_filetypes[args.match] then
      require("lz.n").trigger_load("nvim-treesitter")
      pcall(vim.treesitter.start, args.buf)
      return
    end

    pcall(vim.treesitter.start, args.buf)
  end,
})

map({ "n", "x" }, "\\p", function()
  require("lz.n").trigger_load("conform.nvim")
  require("conform").format({
    async = true,
    lsp_format = "fallback",
  })
end, {
  desc = "Format",
})

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

local bento_api = require("bento.api")
bento_api.register_expand_key(";")
bento_api.register_last_buffer_key(";")
bento_api.register_collapse_key("<Esc>")
bento_api.register_prev_page_key("[")
bento_api.register_next_page_key("]")
bento_api.register_action("open", {
  key = "<CR>",
  action = bento_api.actions.open,
  hl = "DiagnosticVirtualTextHint",
})
bento_api.register_action("delete", {
  key = "<BS>",
  action = bento_api.actions.delete,
  hl = "DiagnosticVirtualTextError",
})
bento_api.register_action("vsplit", {
  key = "|",
  action = bento_api.actions.vsplit,
  hl = "DiagnosticVirtualTextInfo",
})
bento_api.register_action("split", {
  key = "_",
  action = bento_api.actions.split,
  hl = "DiagnosticVirtualTextInfo",
})
bento_api.register_action("lock", {
  key = "*",
  action = bento_api.actions.lock,
  hl = "DiagnosticVirtualTextWarn",
})
bento_api.set_default_action("open")

map("n", "<leader>.", "<cmd>Oil<CR>", {
  desc = "Open parent directory",
})

map("n", "<leader>>", function()
  local win = require("helpers").right_split()
  vim.api.nvim_set_current_win(win)
  vim.cmd.Oil()
end, {
  desc = "Oil in right split",
})

map("n", "<leader>op", function()
  require("lz.n").trigger_load("plugin-view.nvim")
  require("plugin-view").open()
end, {
  desc = "Open plugin viewer",
})

require("blink.cmp").setup({
  sources = {
    default = {
      "lsp",
      "path",
      "snippets",
      "buffer",
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
        require("lz.n").trigger_load("minuet-ai.nvim")
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
