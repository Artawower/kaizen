return {
    {
        "MunifTanjim/nui.nvim"
    },
    {"folke/which-key.nvim", lazy = true},
    {
        "francoiscabrol/ranger.vim",
        config = function()
            require("ranger_config")
        end
    },
    {
        "mikavilpas/yazi.nvim",
        event = "VeryLazy",
        keys = {
            {
                "<leader>-",
                "<cmd>Yazi<cr>",
                desc = "Open yazi at the current file"
            },
            {
                "<leader>cw",
                "<cmd>Yazi cwd<cr>",
                desc = "Open the file manager in nvim's working directory"
            },
            {
                "<c-up>",
                "<cmd>Yazi toggle<cr>",
                desc = "Resume the last yazi session"
            }
        },
        opts = {
            open_for_directories = false,
            keymaps = {
                show_help = "<f1>"
            }
        }
    },
    {
        "nvim-tree/nvim-tree.lua",
        config = function()
            require("nvimtree_config")
        end
    },
    "folke/neodev.nvim",
    {
        "catppuccin/nvim",
        name = "catppuccin",
        config = function()
            require("catppuccin").setup(
                {
                    flavour = "frappe",
                    transparent_background = true,
                    background = {
                        light = "latte",
                        dark = "mocha"
                    },
                    integrations = {
                        cmp = true,
                        gitsigns = true,
                        nvimtree = true,
                        telescope = {
                            enabled = false,
                            theme = "dropdown",
                            style = "nvchad"
                        },
                        notify = false,
                        mini = false
                    }
                }
            )
        end
    },
    "folke/tokyonight.nvim",
    {
        "f-person/auto-dark-mode.nvim",
        config = function()
            local auto_dark_mode = require("auto-dark-mode")
            auto_dark_mode.setup(
                {
                    update_interval = 1000,
                    set_dark_mode = function()
                        vim.o.background = "dark"
                        vim.cmd("colorscheme catppuccin")
                    end,
                    set_light_mode = function()
                        vim.o.background = "light"
                        vim.cmd("colorscheme catppuccin-latte")
                    end
                }
            )
            auto_dark_mode.init()
        end
    },
    {
        "karb94/neoscroll.nvim",
        config = function()
            require("neoscroll").setup()
        end
    },
    {
        "nvim-lualine/lualine.nvim",
        config = function()
            require("lualine_config")
        end
    },
    {
        "romgrk/barbar.nvim",
        dependencies = {
            "lewis6991/gitsigns.nvim",
            "nvim-tree/nvim-web-devicons"
        },
        init = function()
            vim.g.barbar_auto_setup = false
            require("tabbar_config")
        end,
        opts = {},
        version = "^1.0.0"
    },
    "norcalli/nvim-colorizer.lua",
    "sakshamgupta05/vim-todo-highlight",
    "VonHeikemen/searchbox.nvim",
    {
        "s1n7ax/nvim-window-picker",
        name = "window-picker",
        event = "VeryLazy",
        version = "2.*",
        config = function()
            require("choosewin_config")
        end
    },
    {
        "borber/hop.nvim",
        keys = {
            {"f", ":HopChar1<CR>", desc = "Jump to char", mode = "n"},
            {"<leader>j", ":HopChar1<CR>", desc = "Jump to char", mode = "n"}
        },
        config = function()
            require "hop".setup {keys = "etovxqpdygfblzhckisuran"}
        end
    },
    {
        "MattesGroeger/vim-bookmarks",
        config = function()
            require("bookmarks_config")
        end
    },
    {
        "L3MON4D3/LuaSnip"
    },
    {
        "kylechui/nvim-surround",
        version = "*",
        event = "VeryLazy",
        config = function()
            require("nvim-surround").setup({})
        end
    },
    {
        "numToStr/Comment.nvim",
        config = function()
            require("Comment").setup()
        end
    },
    {
        "sbdchd/neoformat",
        config = function()
            require("neoformat_config")
        end
    },
    {
        "windwp/nvim-autopairs",
        config = function()
            require("nvim-autopairs").setup(
                {
                    disable_filetype = {"TelescopePrompt", "vim"}
                }
            )
        end
    },
    {
        "windwp/nvim-ts-autotag",
        opts = {}
    },
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    {
        "neovim/nvim-lspconfig",
        config = function()
            require("lsp")
        end
    },
    "joeveiga/ng.nvim",
    "nvimdev/lspsaga.nvim",
    {
        "zbirenbaum/copilot.lua",
        config = function()
            require("copilot_config")
        end
    },
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "hrsh7th/cmp-cmdline",
    {
        "hrsh7th/nvim-cmp",
        config = function()
            require("cmp_config")
        end
    },
    {
        "nvim-telescope/telescope.nvim",
        config = function()
            require("telescope_config")
        end,
        dependencies = {{"nvim-lua/plenary.nvim"}}
    },
    "onsails/lspkind-nvim",
    "mfussenegger/nvim-dap",
    "rcarriga/nvim-dap-ui",
    {
        "voldikss/vim-translator",
        config = function()
            require("translate_config")
        end
    },
    "wakatime/vim-wakatime",
    "airblade/vim-rooter",
    {
        "akinsho/toggleterm.nvim",
        config = function()
            require("toggleterm_config")
        end
    },
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require("gitsigns_config")
        end
    },
    {
        "fredehoey/tardis.nvim",
        dependencies = {"nvim-lua/plenary.nvim"},
        config = true
    },
    {
        "APZelos/blamer.nvim",
        init = function()
            vim.g.blamer_enabled = 1
        end
    },
    {
        "TimUntersberger/neogit",
        config = function()
            require("neogit-config")
        end
    },
    "dunstontc/projectile.nvim",
    "nvim-telescope/telescope-project.nvim",
    {
        "ahmedkhalf/project.nvim",
        config = function()
            require("project_nvim").setup(require("project_config"))
        end
    },
    "tom-anders/telescope-vim-bookmarks.nvim",
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        build = ":TSUpdate",
        lazy = false,
        config = function()
            require("treesitter_config")
        end
    },
    {
        "romgrk/nvim-treesitter-context",
        config = function()
            require "treesitter-context".setup {
                enable = true,
                throttle = true,
                max_lines = 0,
                patterns = {
                    default = {
                        "class",
                        "function",
                        "method"
                    }
                }
            }
        end
    },
    "kamykn/popup-menu.nvim",
    "kamykn/spelunker.vim",
    "mattn/emmet-vim",
    {
        "mikesmithgh/kitty-scrollback.nvim",
        enabled = true,
        lazy = true,
        cmd = {"KittyScrollbackGenerateKittens", "KittyScrollbackCheckHealth"},
        event = {"User KittyScrollbackLaunch"},
        config = function()
            require("kitty-scrollback").setup()
        end
    },
    {
        "greggh/claude-code.nvim",
        dependencies = {"nvim-lua/plenary.nvim"},
        config = function()
            require("claude-code").setup(
                {
                    window = {
                        split_ratio = 0.5,
                        position = "vertical",
                        enter_insert = true,
                        hide_numbers = true,
                        hide_signcolumn = true
                    },
                    refresh = {
                        enable = true,
                        updatetime = 100,
                        timer_interval = 1000,
                        show_notifications = true
                    },
                    git = {
                        use_git_root = true
                    },
                    shell = {
                        separator = "&&",
                        pushd_cmd = "pushd",
                        popd_cmd = "popd"
                    },
                    command = "claude",
                    command_variants = {
                        continue = "--continue",
                        resume = "--resume",
                        verbose = "--verbose"
                    },
                    keymaps = {
                        toggle = {
                            normal = "<C-,>",
                            terminal = "<C-,>",
                            variants = {
                                continue = "<leader>cC",
                                verbose = "<leader>cV"
                            }
                        },
                        window_navigation = true,
                        scrolling = true
                    }
                }
            )
        end,
        keys = {
            {"<leader>cc", desc = "Toggle Claude Code"},
            {"<leader>cn", desc = "New Claude Code conversation"},
            {"<leader>co", desc = "Continue Claude Code conversation"}
        }
    },
    {
        "tpope/vim-dadbod",
        dependencies = {
            "kristijanhusak/vim-dadbod-ui",
            "kristijanhusak/vim-dadbod-completion"
        },
        config = function()
            vim.g.db_ui_use_nerd_fonts = 1
            vim.g.db_ui_winwidth = 30
            vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
            vim.g.dbs = {
                {name = "local_sqlite", url = "sqlite:./data.db"}
            }
        end,
        keys = {
            {"<leader>db", "<cmd>DBUI<cr>", desc = "Database UI"},
            {"<leader>dbt", "<cmd>DBUIToggle<cr>", desc = "Toggle Database UI"},
            {"<leader>dbf", "<cmd>DBUIFindBuffer<cr>", desc = "Find Database Buffer"},
            {"<leader>dbr", "<cmd>DBUIRenameBuffer<cr>", desc = "Rename Database Buffer"},
            {"<leader>dbl", "<cmd>DBUILastQueryInfo<cr>", desc = "Last Query Info"}
        }
    },
    {
        "alex-popov-tech/store.nvim",
        dependencies = {
            "OXY2DEV/markview.nvim"
        },
        cmd = "Store",
        keys = {
            {"<leader>s", "<cmd>Store<cr>", desc = "Open Plugin Store"}
        },
        opts = {}
    },
    {
        "nvzone/typr",
        dependencies = "nvzone/volt",
        opts = {},
        cmd = {"Typr", "TyprStats"}
    },
    {
        "nvzone/volt",
        lazy = true
    },
    {
        "nvzone/menu",
        lazy = true,
        config = function()
            require("menu_config").setup()
        end
    },
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        config = function()
            require("snacks_config").setup()
        end
    },
    {
        "nvzone/floaterm",
        dependencies = "nvzone/volt",
        config = function()
            require("floaterm_config").setup()
        end
    },
    {
        "editor-code-assistant/eca-nvim",
        dependencies = {
            "MunifTanjim/nui.nvim",
            "nvim-lua/plenary.nvim"
        },
        opts = {}
    }
}
