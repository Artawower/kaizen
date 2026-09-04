vim.pack.add({
  "https://github.com/nvim-mini/mini.pick",
  "https://github.com/nvim-mini/mini.extra",
  "https://github.com/nvim-mini/mini.visits"
})

local map = vim.keymap.set;



require("mini.pick").setup({
  -- Delays (in ms; should be at least 1)
  delay = {
    -- Delay between forcing asynchronous behavior
    async = 10,

    -- Delay between computation start and visual feedback about it
    busy = 50,
  },

  -- Keys for performing actions. See `:h require("mini.pick")-actions`.
  mappings = {
    caret_left        = '<Left>',
    caret_right       = '<Right>',

    choose            = '<CR>',
    choose_in_split   = '<C-s>',
    choose_in_tabpage = '<C-t>',
    choose_in_vsplit  = '<C-v>',
    choose_marked     = '<M-CR>',

    delete_char       = '<BS>',
    delete_char_right = '<Del>',
    delete_left       = '<C-u>',
    delete_word       = '<C-w>',

    mark              = '<C-x>',
    mark_all          = '<C-a>',

    move_down         = '<C-n>',
    move_start        = '<C-g>',
    move_up           = '<C-p>',

    paste             = '<C-r>',

    refine            = '<C-Space>',
    refine_marked     = '<M-Space>',

    scroll_down       = '<C-f>',
    scroll_left       = '<C-h>',
    scroll_right      = '<C-l>',
    scroll_up         = '<C-b>',

    stop              = '<Esc>',

    toggle_info       = '<S-Tab>',
    toggle_preview    = '<Tab>',
  },

  -- General options
  options = {
    -- Whether to show content from bottom to top
    content_from_bottom = false,

    -- Whether to cache matches (more speed and memory on repeated prompts)
    use_cache = false,
  },

  -- Source definition. See `:h require("mini.pick")-source`.
  source = {
    items         = nil,
    name          = nil,
    cwd           = nil,

    match         = nil,
    show          = nil,
    preview       = nil,

    choose        = nil,
    choose_marked = nil,
  },

  -- Window related options
  window = {
    config = function()
      local height = math.floor(vim.o.lines * 0.35)

      return {
        relative = "editor",
        anchor = "SW",

        width = vim.o.columns - 2,
        height = height,

        row = vim.o.lines - 2,
        col = 1,

        border = "single",
      }
    end,

    prompt_caret = "▏",
    prompt_prefix = " ",
  },
})

local function project_root()
  return require("project").get_project_root() or vim.fn.getcwd()
end

require("mini.extra").setup()

map("n", "<leader>ff", function()
  require("mini.pick").builtin.files(nil, {
    source = {
      cwd = project_root(),
    },
  })
end, {
  desc = "Find project files",
})

map("n", "<leader>/", function()
  require("mini.pick").builtin.grep_live(nil, {
    source = {
      cwd = project_root(),
    },
  })
end, {
  desc = "Search project",
})

map({ "x", "n" }, "<leader>bb", function()
  require("mini.pick").builtin.buffers()
end, { desc = "Switch buffer" })


map("n", "<leader>fr", function()
  require("mini.extra").pickers.visit_paths({
    cwd = project_root(),
    recency_weight = 1,
  })
end, {
  desc = "Recent project files",
})

map("n", "<leader>fR", function()
  require("mini.extra").pickers.visit_paths({
    cwd = "",
    recency_weight = 1,
  })
end)

map("n", "<leader>''", function()
  require("mini.pick").pickers.resume()
end, {
  desc = "Resume the latest search",
})


map("n", "<D-f>", function()
  require("mini.extra").pickers.buf_lines({
    scope = "current",
  })
end, {
  desc = "Find in buffer",
})

-- LSP picker
local function lsp_picker(scope)
  return function()
    require("mini.extra").pickers.lsp({
      scope = scope,
    })
  end
end


map("n", "gr", lsp_picker("references"), {
  desc = "Go to references",
})

map("n", "gi", lsp_picker("implementation"), {
  desc = "Go to implementation",
})

map("n", "gt", lsp_picker("type_definition"), {
  desc = "Go to type definition",
})


map("n", "<leader>ls", lsp_picker("document_symbol"), {
  desc = "Document symbols",
})

map("n", "<leader>lS", lsp_picker("workspace_symbol_live"), {
  desc = "Workspace symbols",
})

map("n", "<leader>ld", function()
  require("mini.extra").pickers.diagnostic({
    scope = "current",
  })
end, {
  desc = "Diagnostics",
})


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

      require("mini.extra").pickers.list({
        scope = "quickfix",
      })
    end,
  })
end

map("n", "gD", definition_right, {
  desc = "Go to definition in right split",
})



-- Visits
require("mini.visits").setup()


-- Current project root
local function project_root()
  return require("project").get_project_root() or vim.fn.getcwd()
end

-- Normalize project.nvim history entries
local function normalize_project(project)
  if type(project) == "string" then
    return {
      path = project,
      name = vim.fs.basename(project),
    }
  end

  return {
    path = project.path,
    name = project.name or vim.fs.basename(project.path),
  }
end

-- Project picker
local function pick_project()
  local recent = require("project").get_recent_projects()
  local projects = {}

  for _, project in ipairs(recent) do
    local item = normalize_project(project)

    table.insert(projects, {
      text = item.name,
      path = item.path,
    })
  end

  require("mini.pick").start({
    source = {
      name = "Projects",
      items = projects,

      choose = function(item)
        if not item then
          return
        end

        vim.cmd("cd " .. vim.fn.fnameescape(item.path))
      end,
    },
  })
end

-- Switch project
map("n", "<leader>pp", pick_project, {
  desc = "Projects",
})

-- Find project files
map("n", "<leader>ff", function()
  require("mini.pick").builtin.files(nil, {
    source = {
      cwd = project_root(),
    },
  })
end, {
  desc = "Find project files",
})

-- Search project
map("n", "<leader>/", function()
  require("mini.pick").builtin.grep_live(nil, {
    source = {
      cwd = project_root(),
    },
  })
end, {
  desc = "Search project",
})

-- Recent project files
map("n", "<leader>fr", function()
  require("mini.extra").pickers.visit_paths({
    cwd = project_root(),
    recency_weight = 1,
  })
end, {
  desc = "Recent project files",
})
