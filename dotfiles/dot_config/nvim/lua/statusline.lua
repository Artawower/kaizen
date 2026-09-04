vim.pack.add({
	'https://github.com/nvim-tree/nvim-web-devicons',
	'https://github.com/nvim-lualine/lualine.nvim'
})

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
		-- LEFT
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
					readonly = " ",
					unnamed = "[No Name]",
					newfile = " [New]",
				},
			},
		},

		-- EMPTY MIDDLE

		lualine_x = {
			{
				"diagnostics",
				sources = { "nvim_diagnostic" },
				symbols = {
					error = " ",
					warn = " ",
					info = " ",
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
