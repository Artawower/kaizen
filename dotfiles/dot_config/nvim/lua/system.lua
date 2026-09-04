vim.pack.add({ "https://github.com/adriankarlen/plugin-view.nvim" })
require("plugin-view").setup()


vim.keymap.set("n", "<leader>op", function() require("plugin-view").open() end)
