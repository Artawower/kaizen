vim.pack.add({
  { src = "https://github.com/neovim/nvim-lspconfig" },
})

local map = vim.keymap.set

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
    "toml"
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


local function without_selection(fn)
  return function(...)
    if vim.fn.mode():match("[vV\22]") then
      vim.cmd("normal! \27")
    end

    return fn(...)
  end
end

-- LSP navigation
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
vim.pack.add({ "https://github.com/nvim-treesitter/nvim-treesitter-context" })

require 'treesitter-context'.setup {
  enable = true,            -- Enable this plugin (Can be enabled/disabled later via commands)
  multiwindow = false,      -- Enable multiwindow support.
  max_lines = 0,            -- How many lines the window should span. Values <= 0 mean no limit.
  min_window_height = 0,    -- Minimum editor window height to enable context. Values <= 0 mean no limit.
  line_numbers = true,
  multiline_threshold = 20, -- Maximum number of lines to show for a single context
  trim_scope = 'outer',     -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
  mode = 'cursor',          -- Line used to calculate context. Choices: 'cursor', 'topline'
  -- Separator between context and content. Should be a single character string, like '-'.
  -- When separator is set, the context will only show up when there are at least 2 lines above cursorline.
  separator = nil,
  zindex = 20,     -- The Z-index of the context window
  on_attach = nil, -- (fun(buf: integer): boolean) return false to disable attaching
}


-- Highlight the symbol
-- Highlight references under cursor
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    if not client
        or not client:supports_method("textDocument/documentHighlight")
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
      callback = vim.lsp.buf.document_highlight,
    })

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = group,
      buffer = args.buf,
      callback = vim.lsp.buf.clear_references,
    })
  end,
})


-- Linters
vim.pack.add({
  "https://github.com/mfussenegger/nvim-lint",
})

local lint = require("lint")

lint.linters_by_ft = {
  go = { "golangcilint" },

  css = { "stylelint" },
  scss = { "stylelint" },
  vue = { "stylelint" },

  sh = { "shellcheck" },
}

-- Lint when filetype becomes available
vim.api.nvim_create_autocmd("FileType", {
  callback = function()
    require("lint").try_lint()
  end,
})

-- Lint after changes
vim.api.nvim_create_autocmd({
  "BufWritePost",
  "InsertLeave",
}, {
  callback = function()
    require("lint").try_lint()
  end,
})
