-- Packages
vim.pack.add({
  "https://github.com/eltonsst/postilla.nvim",
  { src = "https://github.com/milanglacier/minuet-ai.nvim" },
})

local map = vim.keymap.set

-- Postilla

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


-- Keymaps

map({ "x", "n" }, "<leader>as", "<cmd>PostillaStart<CR>", { desc = "Start AI review session" })
map({ "x", "n" }, "<leader>ac", "<cmd>PostillaComment<CR>", { desc = "Comment to AI" })
map({ "x", "n" }, "<leader>af", "<cmd>PostillaDone<CR>", { desc = "Finish AI review" })

-- Minuet

require("minuet").setup({
  provider = "openai_fim_compatible",

  virtualtext = {
    auto_trigger_ft = { "*" },
    -- auto_trigger_ft = {},

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
