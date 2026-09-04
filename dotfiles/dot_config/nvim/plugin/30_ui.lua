-- Packages
vim.pack.add({
  "https://github.com/folke/tokyonight.nvim",
  "https://github.com/catppuccin/nvim",
  "https://github.com/f-person/auto-dark-mode.nvim",
  "https://github.com/tiagovla/tokyodark.nvim",
  "https://github.com/olimorris/onedarkpro.nvim",
  "https://github.com/j-hui/fidget.nvim",
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/nvim-lualine/lualine.nvim",
})

-- Colorscheme

require("tokyodark").setup({
  transparent_background = true,
})

require("onedarkpro").setup({
  options = {
    transparency = true,
    lualine_transparency = true,
  },
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
    hl.FloatBorder = {
      fg = c.comment,
      bg = "NONE",
    }

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

require("catppuccin").setup({
  flavour = "auto",
  background = {
    light = "latte",
    dark = "mocha",
  },
  transparent_background = true,
  float = {
    transparent = true,
    solid = false,
  },
})

vim.cmd.colorscheme("catppuccin-mocha")
vim.o.winborder = "rounded"

-- Dark mode

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
    vim.cmd.colorscheme("catppuccin-nvim")

    require("lualine").refresh({
      force = true,
    })
  end,
})

-- Statusline

require("lualine").setup({
  options = {
    icons_enabled = true,
    theme = "auto",

    component_separators = {
      left = "",
      right = "",
    },

    globalstatus = true,
    disabled_filetypes = {
      statusline = {
        "dashboard",
        "alpha",
        "starter",
      },
    },
  },

  sections = {
    lualine_a = {
      {
        "mode",
        fmt = function(mode)
          return mode:sub(1, 1)
        end,
      },
    },

    lualine_b = {
      "branch",
    },

    lualine_c = {
      {
        "filename",
        path = 1,
        symbols = {
          modified = " ●",
          readonly = " ",
          unnamed = "[No Name]",
          newfile = " [New]",
        },
      },
    },

    lualine_x = {
      {
        "diagnostics",
        sources = { "nvim_diagnostic" },
        symbols = {
          error = " ",
          warn = " ",
          info = " ",
          hint = "󰌵 ",
        },
      },
    },

    lualine_y = {
      "filetype",
    },

    lualine_z = {
      "location",
    },
  },

  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {
      {
        "filename",
        path = 1,
      },
    },

    lualine_x = {},
    lualine_y = {},
    lualine_z = {
      "location",
    },
  },

  tabline = {},
  winbar = {},
  inactive_winbar = {},
  extensions = {},
})

-- Progress

require("fidget").setup({})


-- Markdown
vim.pack.add({ "https://github.com/MeanderingProgrammer/render-markdown.nvim" })
require('render-markdown').setup({})

-- Smooth scroll
-- vim.pack.add({ "https://github.com/nvim-mini/mini.animate" })
-- require('mini.animate').setup()
