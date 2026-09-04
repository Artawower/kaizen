vim.pack.add({
	{
		src = "https://github.com/stevearc/conform.nvim",
	},
})


require("conform").setup({
	formatters_by_ft = {
		lua = { "stylua" },

		python = { "ruff_format" },

		javascript = { "prettierd", "prettier", stop_after_first = true },
		typescript = { "prettierd", "prettier", stop_after_first = true },
		javascriptreact = { "prettierd", "prettier", stop_after_first = true },
		typescriptreact = { "prettierd", "prettier", stop_after_first = true },

		go = { "gofmt" },
		rust = { "rustfmt" },
	},

	format_on_save = {
		timeout_ms = 1000,
		lsp_format = "fallback",
	},
})

vim.keymap.set({ "n", "x" }, "\\p", function()
	require("conform").format({
		async = true,
		lsp_format = "fallback",
	})
end, {
	desc = "Format",
})
