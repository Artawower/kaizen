vim.pack.add({
	"https://github.com/stevearc/oil.nvim",
})

require("oil").setup()



vim.keymap.set("n", "<leader>.", "<cmd>Oil<CR>", {
	desc = "Open parent directory",
})
