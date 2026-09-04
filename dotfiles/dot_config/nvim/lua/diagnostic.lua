vim.opt.signcolumn = "yes"

vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "●",
      [vim.diagnostic.severity.WARN]  = "●",
      [vim.diagnostic.severity.INFO]  = "●",
      [vim.diagnostic.severity.HINT]  = "●",
    },
  },

  underline = true,
  virtual_text = false,
  virtual_lines = false,
  -- virtual_lines = {
  -- 	current_line = true,
  -- },
  float = {
    border = "rounded",
    source = true,
  },
  severity_sort = true,
})

vim.opt.updatetime = 300
vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    vim.diagnostic.open_float(nil, {
      scope = "cursor",
      focus = false,
    })
  end,
})

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

  -- Prefer diagnostic which actually covers cursor position
  local diagnostic = nil

  for _, d in ipairs(diagnostics) do
    local end_col = d.end_col or d.col

    if col >= d.col and col <= end_col then
      diagnostic = d
      break
    end
  end

  -- Otherwise take the first diagnostic on the current line
  diagnostic = diagnostic or diagnostics[1]

  vim.fn.setreg("+", diagnostic.message)

  vim.notify("Diagnostic copied")
end


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
    local severity =
        vim.diagnostic.severity[d.severity] or "UNKNOWN"

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


vim.keymap.set("n", "<leader>ec", copy_current_diagnostic, {
  desc = "Copy diagnostic",
})

vim.keymap.set("n", "<leader>eC", copy_all_diagnostics, {
  desc = "Copy all diagnostics",
})

vim.keymap.set("n", "<C-n>", function()
  vim.diagnostic.jump({ count = 1 })
end, {
  desc = "Next diagnostic",
})

vim.keymap.set("n", "<C-e>", function()
  vim.diagnostic.jump({ count = -1 })
end, {
  desc = "Previous diagnostic",
})


vim.pack.add({ "https://github.com/stevearc/quicker.nvim" })
-- Quick fix
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

vim.keymap.set("n", "<leader>qq", function()
  require("quicker").toggle()
end, {
  desc = "Quickfix",
})
