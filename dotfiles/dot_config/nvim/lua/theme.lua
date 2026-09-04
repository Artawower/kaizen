vim.pack.add({
  "https://github.com/folke/tokyonight.nvim",
  "https://github.com/catppuccin/nvim",
  "https://github.com/f-person/auto-dark-mode.nvim",
  "https://github.com/tiagovla/tokyodark.nvim",
  "https://github.com/olimorris/onedarkpro.nvim"
})

require("tokyodark").setup({
  transparent_background = true
})

require("onedarkpro").setup({
  options = {
    transparency = true,
    lualine_transparency = true
  }
})

require("tokyonight").setup({
  style = "moon",
  light_style = "day",

  transparent = true,

  styles = {
    sidebars = "transparent",
    floats = "transparent",
  },

  on_highlights = function(hl, c)
    -- Subtle float borders
    hl.FloatBorder = {
      fg = c.comment,
      bg = "NONE",
    }

    -- Transparent mini.pick
    hl.MiniPickNormal = {
      bg = "NONE",
    }

    hl.MiniPickBorder = {
      fg = c.comment,
      bg = "NONE",
    }

    -- Blink completion/docs borders
    hl.BlinkCmpDocBorder = {
      fg = c.comment,
      bg = "NONE",
    }

    hl.BlinkCmpMenuBorder = {
      fg = c.comment,
      bg = "NONE",
    }
  end,
})

-- vim.cmd.colorscheme("tokyonight")
vim.cmd.colorscheme("catppuccin-mocha")


require("catppuccin").setup({
  flavour = "auto", -- latte, frappe, macchiato, mocha
  background = {    -- :h background
    light = "latte",
    dark = "mocha",
  },
  transparent_background = true,
  float = {
    transparent = true, -- enable transparent floating windows
    solid = false,      -- use solid styling for floating windows, see |winborder|
  },
})

vim.o.winborder = "rounded"

require("auto-dark-mode").setup({
  update_interval = 1000,

  set_dark_mode = function()
    vim.o.background = "dark"
    vim.cmd.colorscheme("catppuccin-mocha")

    require("lualine").refresh({
      force = true,
    })
  end,

  set_light_mode = function()
    vim.o.background = "light"
    -- vim.cmd.colorscheme("tokyonight")
    vim.cmd.colorscheme("catppuccin-nvim")

    require("lualine").refresh({
      force = true,
    })
  end,
})


-- Better UI
-- Better progress

vim.pack.add({ "https://github.com/j-hui/fidget.nvim" })

require("fidget").setup({})

-- vim.pack.add({
-- 	"https://github.com/MunifTanjim/nui.nvim",
-- 	"https://github.com/rcarriga/nvim-notify",
-- 	"https://github.com/folke/noice.nvim"
-- })
--
-- require("noice").setup({
-- 	lsp = {
-- 		-- override markdown rendering so that **cmp** and other plugins use **Treesitter**
-- 		override = {
-- 			["vim.lsp.util.convert_input_to_markdown_lines"] = true,
-- 			["vim.lsp.util.stylize_markdown"] = true,
-- 			["cmp.entry.get_documentation"] = true, -- requires hrsh7th/nvim-cmp
-- 		},
-- 	},
-- 	-- you can enable a preset for easier configuration
-- 	presets = {
-- 		bottom_search = true, -- use a classic bottom cmdline for search
-- 		command_palette = true, -- position the cmdline and popupmenu together
-- 		long_message_to_split = true, -- long messages will be sent to a split
-- 		inc_rename = false, -- enables an input dialog for inc-rename.nvim
-- 		lsp_doc_border = false, -- add a border to hover docs and signature help
-- 	},
-- })
--
