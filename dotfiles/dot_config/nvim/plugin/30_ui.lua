vim.pack.add({
  "https://github.com/catppuccin/nvim",
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/nvim-lualine/lualine.nvim",
})

local function detect_initial_mode()
  if vim.fn.has("mac") == 1 then
    local result = vim.system({ "/usr/bin/defaults", "read", "-g", "AppleInterfaceStyle" }):wait(200)
    if result.code == 0 then
      return result.stdout == "Dark\n" and "dark" or "light"
    end
    if result.code == 1 then
      return "light"
    end
  end
  return vim.o.background
end

local function set_appearance(mode)
  if vim.o.background == mode and vim.g.colors_name then
    return
  end
  local changed = vim.o.background ~= mode
  vim.o.background = mode
  vim.cmd.colorscheme("catppuccin")
  if changed and package.loaded["lualine"] then
    require("lualine").refresh({ force = true })
  end
end

vim.pack.add({
  {
    src = "https://github.com/tiagovla/tokyodark.nvim",
    data = {
      colorscheme = "tokyodark",
      after = function()
        require("tokyodark").setup({
          transparent_background = true,
        })
      end,
    },
  },
  {
    src = "https://github.com/olimorris/onedarkpro.nvim",
    data = {
      colorscheme = { "onedark", "onelight", "vaporwave" },
      cmd = "OneDarkPro",
      after = function()
        require("onedarkpro").setup({
          options = {
            transparency = true,
            lualine_transparency = true,
          },
        })
      end,
    },
  },
  {
    src = "https://github.com/folke/tokyonight.nvim",
    data = {
      colorscheme = { "tokyonight", "tokyonight-night", "tokyonight-storm", "tokyonight-day", "tokyonight-moon" },
      after = function()
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
      end,
    },
  },
  {
    src = "https://github.com/f-person/auto-dark-mode.nvim",
    data = {
      event = "DeferredUIEnter",
      after = function()
        require("auto-dark-mode").setup({
          update_interval = 1000,
          set_dark_mode = function()
            set_appearance("dark")
          end,
          set_light_mode = function()
            set_appearance("light")
          end,
        })
      end,
    },
  },
  {
    src = "https://github.com/MeanderingProgrammer/render-markdown.nvim",
    data = {
      ft = "markdown",
      cmd = "RenderMarkdown",
      after = function()
        require("render-markdown").setup({})
      end,
    },
  },
}, { load = require("lz.n").load })

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

set_appearance(detect_initial_mode())
vim.o.winborder = "rounded"

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


