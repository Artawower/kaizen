-- Packages
vim.pack.add({
  { src = "https://github.com/folke/snacks.nvim" },
})

-- Snacks setup

local Snacks = require("snacks")
local map = vim.keymap.set

Snacks.setup({
  statuscolumn = {
    enabled = false,
  },
  scratch = {
    enabled = false,
    ft = "markdown",
    win = {
      -- position = "current",

      width = 0.95,
      height = 0.95,
      border = "rounded",
    }

  },
  winbar = {
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
  },
})

-- Find

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
map({ "n", "x" }, "<leader>/", function()
  Snacks.picker.grep({
    cwd = project_root(),

    need_search = false,
    live = false,

    matcher = {
      fuzzy = true,
    }
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

-- Global word grep
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

-- LSP pickers

-- Definitions
map("n", "gd", function()
  Snacks.picker.lsp_definitions()
end, {
  desc = "Go to definition",
})

-- References
map("n", "gr", function()
  Snacks.picker.lsp_references()
end, {
  desc = "Go to references",
})

-- Implementations
map("n", "gi", function()
  Snacks.picker.lsp_implementations()
end, {
  desc = "Go to implementation",
})

-- Type definitions
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

-- Definition split

local helpers = require("helpers")
local function right_split()
  return helpers.right_split()
end

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



-- Pick info about currenf file
local function system(cmd)
  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return vim.trim(result)
end

local function file_info()
  local file = vim.api.nvim_buf_get_name(0)

  if file == "" then
    vim.notify("Buffer has no file")
    return
  end

  local absolute = vim.fn.fnamemodify(file, ":p")
  local name = vim.fn.fnamemodify(file, ":t")
  local dir = vim.fn.fnamemodify(file, ":p:h")
  local relative = vim.fn.fnamemodify(file, ":.")

  local root = system({ "git", "rev-parse", "--show-toplevel" })

  local project_relative = relative

  if root then
    project_relative =
        vim.fs.relpath(root, absolute) or relative
  end

  local remote = system({
    "git",
    "-C",
    dir,
    "remote",
    "get-url",
    "origin",
  })

  local commit = system({
    "git",
    "-C",
    dir,
    "rev-parse",
    "--short",
    "HEAD",
  })

  local stat = vim.uv.fs_stat(absolute)

  local items = {
    {
      label = "File name",
      value = name,
    },
    {
      label = "Project path",
      value = project_relative,
    },
    {
      label = "Relative path",
      value = relative,
    },
    {
      label = "Absolute path",
      value = absolute,
    },
    {
      label = "Directory",
      value = dir,
    },
    {
      label = "Filetype",
      value = vim.bo.filetype,
    },
    {
      label = "File size",
      value = stat and tostring(stat.size) or "?",
    },
    {
      label = "Line count",
      value = tostring(vim.api.nvim_buf_line_count(0)),
    },
  }

  if remote then
    table.insert(items, {
      label = "Git remote",
      value = remote,
    })
  end

  if commit then
    table.insert(items, {
      label = "Commit",
      value = commit,
    })
  end

  vim.ui.select(items, {
    prompt = "File info",
    format_item = function(item)
      return string.format(
        "%-16s %s",
        item.label .. ":",
        item.value
      )
    end,
  }, function(item)
    if not item then
      return
    end

    vim.fn.setreg("+", item.value)

    vim.notify(item.label .. " copied")
  end)
end

map("n", "<leader>fi", file_info, {
  desc = "File info",
})


-- Bookmarks
vim.pack.add({ "https://github.com/cbochs/grapple.nvim" })

local grapple = require("grapple")

grapple.setup({
  scope = "global",

  command = function(path)
    if vim.fn.isdirectory(path) == 1 then
      require("oil").open(path)
      return
    end

    vim.cmd.edit(vim.fn.fnameescape(path))
  end,
})

local function toggle_bookmark()
  local path

  if vim.bo.filetype == "oil" then
    path = require("oil").get_current_dir()
  else
    path = vim.api.nvim_buf_get_name(0)
  end

  if not path or path == "" then
    return
  end

  if grapple.exists({ path = path }) then
    grapple.untag({ path = path })
    return
  end

  vim.ui.input({
    prompt = "Bookmark name: ",
  }, function(name)
    if name == nil then
      return
    end

    grapple.tag({
      path = path,
      name = name ~= "" and name or nil,
    })
  end)
end

map({ "n", "x" }, "<leader>ma", toggle_bookmark, {
  desc = "Toggle bookmark",
})

map({ "n", "x" }, "<leader>mm", function()
  grapple.toggle_tags()
end, {
  desc = "Bookmarks",
}) -- File manager
map("n", "<leader>of", function()
  Snacks.explorer()
end, {
  desc = "Explorer",
})

-- Scratch note
-- vim.keymap.set({ "n", "x" }, "<leader>L", function()
--   Snacks.scratch({
--     name = "quicknotes",
--   })
-- end, { desc = "Scratch note" })

map("n", "<leader>n", function()
  vim.ui.input({ prompt = "Note name: " }, function(name)
    if not name or name == "" then
      return
    end

    Snacks.scratch({
      name = name,
      ft = "markdown",
    })
  end)
end, { desc = "New note" })

vim.keymap.set({ "n", "x" }, "<leader>N", function()
  Snacks.scratch.select()
end, { desc = "Scratch notes" })

-- Help
map("n", "<leader>hc", function()
  Snacks.picker.commands()
end, {
  desc = "Commands",
})

map("n", "<leader>hh", function()
  Snacks.picker.help()
end, {
  desc = "Commands",
})
