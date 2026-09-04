-- Copy context
-- Get visual selection
local function get_visual_selection()
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")

	local start_line = start_pos[2]
	local start_col = start_pos[3]
	local end_line = end_pos[2]
	local end_col = end_pos[3]

	if start_line > end_line or (start_line == end_line and start_col > end_col) then
		start_line, end_line = end_line, start_line
		start_col, end_col = end_col, start_col
	end

	local lines = vim.api.nvim_buf_get_text(
		0,
		start_line - 1,
		start_col - 1,
		end_line - 1,
		end_col,
		{}
	)

	return lines, start_line, end_line
end

-- Copy selection with file context
local map = vim.keymap.set;

local function copy_selection_context()
	local lines, start_line, end_line = get_visual_selection()

	local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")

	local result = string.format(
		"%s, line numbers %d:%d\n\n%s",
		path,
		start_line,
		end_line,
		table.concat(lines, "\n")
	)

	vim.fn.setreg("+", result)

	vim.notify("Selection copied with context")
end

map("x", "N", copy_selection_context, {
	desc = "Copy selection with context",
})


-- AI review
--


vim.pack.add({
	"https://github.com/eltonsst/postilla.nvim"
})

require("postilla").setup({
	context_lines = 5,
	keymap = nil,
	next_keymap = nil,
	previous_keymap = nil,
	state_dir = nil,
	marker = {
		style = "virtual_line",
	},
	comment_window = {
		layout = "bottom",
		height = 10,
		width = 80,
	},
})

map({ "x", "n" }, '<leader>as', '<cmd>PostillaStart<CR>', { desc = "Start AI review session" })
map({ "x", "n" }, '<leader>ac', '<cmd>PostillaComment<CR>', { desc = "Comment to AI" })
map({ "x", "n" }, '<leader>af', '<cmd>PostillaDone<CR>', { desc = "Finish AI review" })
