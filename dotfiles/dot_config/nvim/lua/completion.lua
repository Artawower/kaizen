vim.pack.add({
  {
    src = "https://github.com/saghen/blink.cmp",
    version = vim.version.range("1.*"),
  },
})

require("blink.cmp").setup({
  keymap = {
    preset = "enter",

    ["<C-n>"] = { "select_next", "fallback" },
    ["<C-e>"] = { "select_prev", "fallback" },

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
-- Ai

vim.pack.add({
  { src = "https://github.com/milanglacier/minuet-ai.nvim" },
})

require("minuet").setup({
  provider = "openai_fim_compatible",

  virtualtext = {
    auto_trigger_ft = { "*" },

    keymap = {
      accept = "<D-i>",
      accept_line = "<D-/>",
      next = "<D-]>",
      prev = "<D-[>",
      -- dismiss = "<C-c>",
    },
  },

  provider_options = {
    openai_fim_compatible = {
      api_key = "TERM",
      name = "Ollama",
      end_point = "http://localhost:11434/v1/completions",
      model = "qwen2.5-coder:1.5b",

      optional = {
        max_tokens = 256,
        top_p = 0.9,
      },
    },
  },
})
