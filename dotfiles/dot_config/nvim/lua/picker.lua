vim.pack.add({
  { src = "https://github.com/folke/snacks.nvim" },
})

local Snacks = require("snacks")
local map = vim.keymap.set

Snacks.setup({
  statuscolumn = {
    enabled = false,
  },
  picker = {
    enabled = true,

    layout = {
      preset = "ivy",
      hidden = { "preview" },
      preview = "main",

      layout = {
        height = 0.35,
      },
    },

    win = {
      input = {
        keys = {
          ["<C-n>"] = { "list_down", mode = { "i", "n" } },
          ["<C-e>"] = { "list_up", mode = { "i", "n" } },
          ["<C-g>"] = { "list_top", mode = { "i", "n" } },
          ["<Tab>"] = { "toggle_preview", mode = { "i", "n" } },
        },
      },

      list = {
        keys = {
          ["<C-n>"] = "list_down",
          ["<C-e>"] = "list_up",
          ["<C-g>"] = "list_top",
          ["<Tab>"] = "toggle_preview",
        },
      },
    },
  },
  image = {
    enabled = true,
  }
})

local function project_root()
  return require("project").get_project_root() or vim.fn.getcwd()
end

-- Files
map("n", "<leader>ff", function()
  local root = project_root()

  Snacks.picker.smart({
    cwd = root,

    filter = {
      cwd = root,
    },
  })
end, {
  desc = "Find project files",
})

-- Grep
map("n", "<leader>/", function()
  Snacks.picker.grep({
    cwd = project_root(),
  })
end, {
  desc = "Search project",
})

-- Buffers
map({ "n", "x" }, "<leader>bb", function()
  Snacks.picker.buffers()
end, {
  desc = "Switch buffer",
})

-- Recent project files
map("n", "<leader>fr", function()
  Snacks.picker.recent({
    filter = {
      cwd = project_root(),
    },
  })
end, {
  desc = "Recent project files",
})

-- Recent files
map("n", "<leader>fR", function()
  Snacks.picker.recent()
end, {
  desc = "Recent files",
})

-- Resume
map("n", "<leader>''", function()
  Snacks.picker.resume()
end, {
  desc = "Resume latest search",
})

-- Find in buffer
map("n", "<D-f>", function()
  Snacks.picker.lines()
end, {
  desc = "Find in buffer",
})

-- LSP definitions
map("n", "gd", function()
  Snacks.picker.lsp_definitions()
end, {
  desc = "Go to definition",
})

-- LSP references
map("n", "gr", function()
  Snacks.picker.lsp_references()
end, {
  desc = "Go to references",
})

-- LSP implementations
map("n", "gi", function()
  Snacks.picker.lsp_implementations()
end, {
  desc = "Go to implementation",
})

-- LSP type definitions
map("n", "gt", function()
  Snacks.picker.lsp_type_definitions()
end, {
  desc = "Go to type definition",
})

-- Document symbols
map("n", "<leader>ls", function()
  Snacks.picker.lsp_symbols()
end, {
  desc = "Document symbols",
})

-- Workspace symbols
map("n", "<leader>lS", function()
  Snacks.picker.lsp_workspace_symbols()
end, {
  desc = "Workspace symbols",
})

-- Diagnostics
map("n", "<leader>ld", function()
  Snacks.picker.diagnostics_buffer()
end, {
  desc = "Diagnostics",
})

-- Get or create right split
local function right_split()
  local current = vim.api.nvim_get_current_win()

  vim.cmd("wincmd l")

  local right = vim.api.nvim_get_current_win()

  if right == current then
    vim.cmd("rightbelow vsplit")
    right = vim.api.nvim_get_current_win()
  end

  vim.api.nvim_set_current_win(current)

  return right
end

-- Open location in window
local function open_location(win, item)
  vim.api.nvim_win_call(win, function()
    if item.bufnr and item.bufnr > 0 then
      vim.api.nvim_win_set_buf(win, item.bufnr)
    elseif item.filename then
      vim.cmd.edit(vim.fn.fnameescape(item.filename))
    end

    vim.api.nvim_win_set_cursor(win, {
      item.lnum or 1,
      math.max((item.col or 1) - 1, 0),
    })
  end)
end

-- Definition in right split
local function definition_right()
  vim.lsp.buf.definition({
    on_list = function(result)
      if #result.items == 0 then
        vim.notify("Definition not found", vim.log.levels.INFO)
        return
      end

      local target = right_split()

      if #result.items == 1 then
        open_location(target, result.items[1])
        vim.api.nvim_set_current_win(target)
        return
      end

      vim.fn.setqflist({}, " ", result)

      vim.api.nvim_set_current_win(target)
      Snacks.picker.qflist()
    end,
  })
end

map("n", "gD", definition_right, {
  desc = "Go to definition in right split",
})

-- Global search
map("n", "<leader>*", function()
  vim.cmd("normal! viw")

  vim.schedule(function()
    Snacks.picker.grep_word({
      cwd = project_root(),
    })
  end)
end, {
  desc = "Grep word in project",
})
