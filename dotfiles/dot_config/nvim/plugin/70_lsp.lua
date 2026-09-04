-- Packages
vim.pack.add({
  { src = "https://github.com/neovim/nvim-lspconfig" },
  { src = "https://github.com/nvim-treesitter/nvim-treesitter-context" },
  { src = "https://github.com/mfussenegger/nvim-lint" },
  { src = "https://github.com/stevearc/quicker.nvim" },
})

local map = vim.keymap.set

-- Server configs

-- Lua
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      runtime = {
        version = "LuaJIT",
      },
      diagnostics = {
        globals = { "vim" },
      },
      workspace = {
        checkThirdParty = false,
        library = {
          vim.env.VIMRUNTIME,
        },
      },
    },
  },
})

-- Python
vim.lsp.config("ty", {
  root_markers = {
    "ty.toml",
    "pyproject.toml",
    "uv.lock",
    "requirements.txt",
    "setup.py",
    "setup.cfg",
    ".git",
  },
})

vim.lsp.config("ruff", {
  root_markers = {
    "pyproject.toml",
    "ruff.toml",
    ".ruff.toml",
    "uv.lock",
    "requirements.txt",
    "setup.py",
    "setup.cfg",
    ".git",
  },
})

-- Go
vim.lsp.config("gopls", {
  settings = {
    gopls = {
      usePlaceholders = true,
    },
  },
})

-- ESLint
vim.lsp.config("eslint", {
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "vue",
  },
  settings = {
    validate = "on",
    run = "onType",
    format = false,
  },
})

-- Vue
local function get_vue_language_server_path()
  local executable = vim.fn.exepath("vue-language-server")

  if executable == "" then
    return nil
  end

  local realpath = vim.uv.fs_realpath(executable) or executable

  return vim.fs.dirname(vim.fs.dirname(realpath))
end

local vue_language_server_path = get_vue_language_server_path()

if vue_language_server_path then
  vim.lsp.config("ts_ls", {
    filetypes = {
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
      "vue",
    },
    init_options = {
      plugins = {
        {
          name = "@vue/typescript-plugin",
          location = vue_language_server_path,
          languages = { "vue" },
          configNamespace = "typescript",
        },
      },
    },
  })
end

-- YAML
vim.lsp.config("yamlls", {
  settings = {
    yaml = {
      schemas = {
        ["https://json.schemastore.org/github-workflow"] = ".github/workflows/*",
        ["https://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
        ["https://raw.githubusercontent.com/kubernetes/kubernetes/master/api/openapi-spec/swagger.json"] =
        "*.k8s.{yml,yaml}",
      },
    },
  },
})

-- Codebook
vim.lsp.config("codebook", {
  filetypes = {
    "python",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "vue",
    "html",
    "htmlangular",
    "lua",
    "css",
    "scss",
    "cs",
    "toml",
  },
})

-- Copilot
vim.lsp.config("copilot", {
  filetypes = {
    "python",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "vue",
    "toml",
  },
})

-- LSP attach

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    if not client then
      return
    end

    -- Prefer ty hover over Ruff
    if client.name == "ruff" then
      client.server_capabilities.hoverProvider = false
    end

    -- Copilot inline completion
    if
        client.name == "copilot"
        and client:supports_method(
          vim.lsp.protocol.Methods.textDocument_inlineCompletion,
          args.buf
        )
    then
      vim.lsp.inline_completion.enable(true, {
        bufnr = args.buf,
      })

      map("i", "<C-f>", vim.lsp.inline_completion.get, {
        buffer = args.buf,
        desc = "Accept Copilot completion",
      })
    end
  end,
})

-- Enable servers

vim.lsp.enable({
  "ty",
  "ruff",

  "ts_ls",
  "angularls",
  "vue_ls",
  "eslint",

  "html",
  "cssls",
  "jsonls",
  "yamlls",

  "gopls",
  "rust_analyzer",
  "lua_ls",
  "csharp_ls",
  "marksman",

  "codebook",
  "copilot",
})

-- LSP keymaps

local function without_selection(fn)
  return function(...)
    if vim.fn.mode():match("[vV\22]") then
      vim.cmd("normal! \27")
    end

    return fn(...)
  end
end

map({ "n", "x" }, "gd", without_selection(vim.lsp.buf.definition), {
  desc = "Go to definition",
})

map({ "n", "x" }, "<leader>la", without_selection(vim.lsp.buf.code_action), {
  desc = "Code action",
})

map({ "n", "x" }, "<leader>lr", without_selection(vim.lsp.buf.rename), {
  desc = "Rename symbol",
})

map({ "n", "x" }, "<leader>lh", without_selection(vim.lsp.buf.hover), {
  desc = "Hover",
})

-- Breadcrumbs

require("treesitter-context").setup({
  enable = true,
  multiwindow = false,
  max_lines = 0,
  min_window_height = 0,
  line_numbers = true,
  multiline_threshold = 20,
  trim_scope = "outer",
  mode = "cursor",
  separator = nil,
  zindex = 20,
  on_attach = nil,
})

-- Document highlight

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    if not client
        or not client:supports_method(
          "textDocument/documentHighlight",
          args.buf
        )
    then
      return
    end

    local group = vim.api.nvim_create_augroup(
      "LspDocumentHighlight_" .. args.buf,
      { clear = true }
    )

    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = group,
      buffer = args.buf,
      callback = function()
        for _, c in ipairs(vim.lsp.get_clients({ bufnr = args.buf })) do
          if c:supports_method(
                "textDocument/documentHighlight",
                args.buf
              ) then
            vim.lsp.buf.document_highlight()
            return
          end
        end
      end,
    })

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      buffer = args.buf,
      callback = vim.lsp.buf.clear_references,
    })
  end,
})

-- Diagnostics

vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "●",
      [vim.diagnostic.severity.WARN] = "●",
      [vim.diagnostic.severity.INFO] = "●",
      [vim.diagnostic.severity.HINT] = "●",
    },
  },

  underline = true,
  virtual_text = false,
  virtual_lines = false,
  float = {
    border = "rounded",
    source = true,
  },
  severity_sort = true,
})

vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    vim.diagnostic.open_float(nil, {
      scope = "cursor",
      focus = false,
    })
  end,
})

-- Copy current diagnostic
local function copy_current_diagnostic()
  local bufnr = 0
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local col = cursor[2]

  local diagnostics = vim.diagnostic.get(bufnr, {
    lnum = line,
  })

  if #diagnostics == 0 then
    vim.notify("No diagnostic under cursor", vim.log.levels.INFO)
    return
  end

  local diagnostic = nil

  for _, d in ipairs(diagnostics) do
    local end_col = d.end_col or d.col

    if col >= d.col and col <= end_col then
      diagnostic = d
      break
    end
  end

  diagnostic = diagnostic or diagnostics[1]

  vim.fn.setreg("+", diagnostic.message)

  vim.notify("Diagnostic copied")
end

-- Copy all diagnostics
local function copy_all_diagnostics()
  local diagnostics = vim.diagnostic.get(0)

  if #diagnostics == 0 then
    vim.notify("No diagnostics", vim.log.levels.INFO)
    return
  end

  table.sort(diagnostics, function(a, b)
    if a.lnum == b.lnum then
      return a.col < b.col
    end

    return a.lnum < b.lnum
  end)

  local lines = {}

  for _, d in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[d.severity] or "UNKNOWN"

    table.insert(
      lines,
      string.format(
        "%d:%d [%s] %s",
        d.lnum + 1,
        d.col + 1,
        severity,
        d.message
      )
    )
  end

  vim.fn.setreg("+", table.concat(lines, "\n"))

  vim.notify(
    string.format("%d diagnostics copied", #diagnostics)
  )
end

map("n", "<leader>ec", copy_current_diagnostic, {
  desc = "Copy diagnostic",
})

map("n", "<leader>eC", copy_all_diagnostics, {
  desc = "Copy all diagnostics",
})

-- Linting

local lint = require("lint")

lint.linters_by_ft = {
  go = { "golangcilint" },

  css = { "stylelint" },
  scss = { "stylelint" },
  vue = { "stylelint" },

  sh = { "shellcheck" },
}

vim.api.nvim_create_autocmd("FileType", {
  callback = function()
    require("lint").try_lint()
  end,
})

vim.api.nvim_create_autocmd({
  "BufWritePost",
  "InsertLeave",
}, {
  callback = function()
    require("lint").try_lint()
  end,
})

-- Quickfix

require("quicker").setup({
  keys = {
    {
      ">",
      function()
        require("quicker").expand({
          before = 2,
          after = 2,
          add_to_existing = true,
        })
      end,
      desc = "Expand context",
    },
    {
      "<",
      function()
        require("quicker").collapse()
      end,
      desc = "Collapse context",
    },
  },
})

map("n", "<leader>qq", function()
  require("quicker").toggle()
end, {
  desc = "Quickfix",
})

-- Copy context

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

  return lines, start_line, start_col, end_line, end_col
end

local function position_before(line1, col1, line2, col2)
  return line1 < line2 or (line1 == line2 and col1 < col2)
end

local function get_diagnostics_in_range(start_line, start_col, end_line, end_col)
  local diagnostics = vim.diagnostic.get(0)
  local result = {}

  local sel_start_line = start_line - 1
  local sel_start_col = start_col - 1
  local sel_end_line = end_line - 1
  local sel_end_col = end_col

  for _, d in ipairs(diagnostics) do
    local diag_end_line = d.end_lnum or d.lnum
    local diag_end_col = d.end_col or (d.col + 1)

    local starts_before_selection_ends = position_before(
      d.lnum,
      d.col,
      sel_end_line,
      sel_end_col
    )

    local selection_starts_before_diag_ends = position_before(
      sel_start_line,
      sel_start_col,
      diag_end_line,
      diag_end_col
    )

    if starts_before_selection_ends and selection_starts_before_diag_ends then
      table.insert(result, d)
    end
  end

  table.sort(result, function(a, b)
    if a.lnum == b.lnum then
      return a.col < b.col
    end

    return a.lnum < b.lnum
  end)

  return result
end

local function copy_selection_context()
  local lines, start_line, start_col, end_line, end_col =
      get_visual_selection()

  local path = vim.fn.fnamemodify(
    vim.api.nvim_buf_get_name(0),
    ":."
  )

  local result = string.format(
    "%s, line numbers %d:%d\n\n%s",
    path,
    start_line,
    end_line,
    table.concat(lines, "\n")
  )

  local diagnostics = get_diagnostics_in_range(
    start_line,
    start_col,
    end_line,
    end_col
  )

  if #diagnostics > 0 then
    local diagnostic_lines = {}

    for _, d in ipairs(diagnostics) do
      local severity = vim.diagnostic.severity[d.severity] or "UNKNOWN"

      table.insert(
        diagnostic_lines,
        string.format(
          "%d:%d [%s] %s",
          d.lnum + 1,
          d.col + 1,
          severity,
          d.message
        )
      )
    end

    result = result
        .. "\n\nDiagnostics:\n"
        .. table.concat(diagnostic_lines, "\n")
  end

  vim.fn.setreg("+", result)

  vim.notify(
    string.format(
      "Selection copied with %d diagnostics",
      #diagnostics
    )
  )
end

map("x", "N", copy_selection_context, {
  desc = "Copy selection with context",
})


-- Repl
vim.pack.add({ "https://github.com/ii14/neorepl.nvim" })
