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

        local config = require("minuet").config
        local ignore = config.virtualtext.auto_trigger_ignore_ft or {}

        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          local ft = vim.bo[buf].filetype
          if vim.api.nvim_buf_is_loaded(buf) and ft ~= "" and not vim.tbl_contains(ignore, ft) then
            vim.b[buf].minuet_virtual_text_auto_trigger = true
          end
        end

        if vim.fn.mode():match("^[iR]") then
          pcall(vim.api.nvim_exec_autocmds, "InsertEnter", {
            group = "MinuetVirtualText",
            buffer = vim.api.nvim_get_current_buf(),
            modeline = false,
          })
        end
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
