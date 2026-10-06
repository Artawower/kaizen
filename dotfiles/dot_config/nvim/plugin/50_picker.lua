vim.pack.add({
  { src = "https://github.com/folke/snacks.nvim" },
  {
    src = "https://github.com/cbochs/grapple.nvim",
    data = {
      cmd = "Grapple",
      after = function()
        require("grapple").setup({
          scope = "global",
          command = function(path)
            if vim.fn.isdirectory(path) == 1 then
              vim.cmd.Oil(vim.fn.fnameescape(path))
              return
            end

            vim.cmd.edit(vim.fn.fnameescape(path))
          end,
        })
      end,
    },
  },
}, { load = require("lz.n").load })

local Snacks = require("snacks")
local map = vim.keymap.set
local kaizen = require("helpers").kaizen

local function split_grep_query(str)
  local function find_unescaped(s, start)
    local i = start or 1
    while i <= #s do
      local c = s:sub(i, i)
      if c == "\\" then
        i = i + 2
      elseif c == "#" then
        return i
      else
        i = i + 1
      end
    end
    return nil
  end

  local s, f
  if str:sub(1, 1) == "#" then
    local second = find_unescaped(str, 2)
    if second then
      s = str:sub(2, second - 1)
      f = str:sub(second + 1)
    else
      s = str
    end
  else
    local pos = find_unescaped(str, 1)
    if pos then
      s = str:sub(1, pos - 1)
      f = str:sub(pos + 1)
    else
      s = str
    end
  end

  s = s:gsub("\\#", "#")

  if f then
    local filter_base, flags = f:match("^(.-)%s+%-%-%s*(.*)$")
    if filter_base and flags then
      f = filter_base
      s = s .. " -- " .. flags
    end
  end

  return s, f
end

Snacks.setup({
  statuscolumn = {
    enabled = false,
  },
  scratch = {
    enabled = false,
    ft = "markdown",
    win = {
      width = 0.95,
      height = 0.95,
      border = "rounded",
    },
  },
  winbar = {
    enabled = false,
  },
  picker = {
    enabled = true,
    limit = 2000,
    limit_live = 2000,
    sources = {
      grep = {
        filter = {
          transform = function(_, filter)
            local s, f = split_grep_query(filter.search)
            if s and f then
              filter.search = vim.trim(s)
              filter.pattern = vim.trim(f)
            end
          end,
        },
        exclude = {
          "node_modules",
          "dist",
          "build",
          "coverage",
          ".next",
          ".nuxt",
          ".cache",
          ".turbo",
          "target",
        },
      },
    },
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
          ["<C-f>"] = { "toggle_live", mode = { "i", "n" } },
          ["<M-l>"] = { "toggle_live", mode = { "i", "n" } },
          ["<Tab>"] = { "toggle_preview", mode = { "i", "n" } },
        },
      },
      list = {
        keys = {
          ["<C-n>"] = "list_down",
          ["<C-e>"] = "list_up",
          ["<C-g>"] = "list_top",
          ["<C-f>"] = "toggle_live",
          ["<M-l>"] = "toggle_live",
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
local file_find_key = "<leader>" .. kaizen.key("file.find", "ff")
map("n", file_find_key, function()
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

if file_find_key ~= "<leader>ff" then
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
end

-- Grep
map({ "n", "x" }, "<leader>/", function()
  Snacks.picker.grep({
    cwd = project_root(),
    search = function(picker)
      return (picker.visual and picker.visual.text) or ""
    end,
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
map({ "n", "x" }, "<leader>*", function()
  Snacks.picker.grep_word({
    cwd = project_root(),
  })
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

local lsp_symbols_key = "<leader>" .. kaizen.key("lsp.symbols", "ls")
map("n", lsp_symbols_key, function()
  Snacks.picker.lsp_symbols()
end, {
  desc = "Document symbols",
})

map("n", "<leader>lS", function()
  Snacks.picker.lsp_workspace_symbols()
end, {
  desc = "Workspace symbols",
})

local lsp_diag_key = "<leader>" .. kaizen.key("lsp.diagnostics", "ld")
map("n", lsp_diag_key, function()
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


local function toggle_bookmark()
  require("lz.n").trigger_load("grapple.nvim")
  local grapple = require("grapple")
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

local bm_toggle_key = "<leader>" .. kaizen.key("bookmark.toggle", "bm")
map({ "n", "x" }, bm_toggle_key, toggle_bookmark, {
  desc = "Toggle bookmark",
})
if bm_toggle_key ~= "<leader>ma" then
  map({ "n", "x" }, "<leader>ma", toggle_bookmark, {
    desc = "Toggle bookmark",
  })
end

local function toggle_bookmarks_panel()
  require("lz.n").trigger_load("grapple.nvim")
  require("grapple").toggle_tags()
end

local bm_list_key = "<leader>" .. kaizen.key("bookmark.list", "bl")
map({ "n", "x" }, bm_list_key, toggle_bookmarks_panel, {
  desc = "Bookmarks",
})
if bm_list_key ~= "<leader>mm" then
  map({ "n", "x" }, "<leader>mm", toggle_bookmarks_panel, {
    desc = "Bookmarks",
  })
end

map("n", "]m", function()
  require("lz.n").trigger_load("grapple.nvim")
  require("grapple").cycle_tags({ direction = "next" })
end, {
  desc = "Next bookmark",
})

map("n", "[m", function()
  require("lz.n").trigger_load("grapple.nvim")
  require("grapple").cycle_tags({ direction = "prev" })
end, {
  desc = "Previous bookmark",
})

local projects_key = "<leader>" .. kaizen.key("projects.pick", "pp")
map("n", projects_key, function()
  Snacks.picker.projects()
end, {
  desc = "Projects",
})

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
