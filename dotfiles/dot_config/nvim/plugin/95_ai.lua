local map = require("helpers").map

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
        local virtualtext_config = require("minuet").config.virtualtext
        local auto_trigger_ft = virtualtext_config.auto_trigger_ft or {}
        local ignored_filetypes = virtualtext_config.auto_trigger_ignore_ft or {}
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) then
            local filetype = vim.bo[buf].filetype
            if filetype ~= "" then
              vim.b[buf].minuet_virtual_text_auto_trigger = (
                vim.tbl_contains(auto_trigger_ft, "*") or vim.tbl_contains(auto_trigger_ft, filetype)
              ) and not vim.tbl_contains(ignored_filetypes, filetype)
            end
          end
        end
        local minuet_action = require("minuet.virtualtext").action
        vim.keymap.set("i", "<C-y>", minuet_action.accept, { desc = "Accept Minuet suggestion" })
        vim.keymap.set("i", "<C-]>", minuet_action.next, { desc = "Next Minuet suggestion" })
        vim.keymap.set("i", "<C-/>", minuet_action.accept_line, { desc = "Accept Minuet line" })
      end,
    },
  },
}, { load = require("lz.n").load })


map({ "x", "n" }, { "<leader>rs", "<leader>ыв" }, function()
  require("lz.n").trigger_load("postilla.nvim")
  vim.cmd.PostillaStart()
end, { desc = "Start AI review session" })

map({ "x", "n" }, { "<leader>rc", "<leader>ыс" }, function()
  require("lz.n").trigger_load("postilla.nvim")
  vim.cmd.PostillaComment()
end, { desc = "Comment to AI" })

map({ "x", "n" }, { "<leader>rd", "<leader>ып" }, function()
  require("lz.n").trigger_load("postilla.nvim")
  vim.cmd.PostillaDone()
end, { desc = "Finish AI review" })


