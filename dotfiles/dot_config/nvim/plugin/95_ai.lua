local map = vim.keymap.set

vim.pack.add({
  {
    src = "https://github.com/eltonsst/postilla.nvim",
    data = {
      cmd = { "PostillaStart", "PostillaComment", "PostillaDone" },
      after = function()
        require("postilla").setup({
          context_lines = 5,
          keymap = nil,
          next_keymap = nil,
          previous_keymap = nil,
          marker = {
            style = "virtual_line",
          },
          comment_window = {
            layout = "bottom",
            height = 10,
            width = 80,
          },
        })
      end,
    },
  },
  {
    src = "https://github.com/milanglacier/minuet-ai.nvim",
    data = {
      event = { "DeferredUIEnter", "InsertEnter" },
      cmd = { "MinuetVirtualTextToggle" },
      after = function()
        require("minuet").setup({
          provider = "openai_fim_compatible",
          notify = false,
          virtualtext = {
            auto_trigger_ft = { "*" },
            keymap = {
              accept = "<D-i>",
              accept_line = "<D-/>",
              next = "<D-]>",
              prev = "<D-[>",
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
        require("kaizen.minuet_ollama_guard").setup()
      end,
    },
  },
}, { load = require("lz.n").load })

map({ "x", "n" }, "<leader>as", function()
  require("lz.n").trigger_load("postilla.nvim")
  vim.cmd.PostillaStart()
end, { desc = "Start AI review session" })

map({ "x", "n" }, "<leader>ac", function()
  require("lz.n").trigger_load("postilla.nvim")
  vim.cmd.PostillaComment()
end, { desc = "Comment to AI" })

map({ "x", "n" }, "<leader>af", function()
  require("lz.n").trigger_load("postilla.nvim")
  vim.cmd.PostillaDone()
end, { desc = "Finish AI review" })
