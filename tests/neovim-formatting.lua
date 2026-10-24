local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
for _, path in ipairs(vim.fn.globpath(vim.fn.stdpath("data") .. "/site/pack/*/opt", "*", false, true)) do
  vim.opt.runtimepath:append(path)
end

local configure
vim.pack.add = function(specs)
  for _, spec in ipairs(specs) do
    if type(spec) == "table" and spec.src == "https://github.com/stevearc/conform.nvim" then
      configure = spec.data.after
    end
  end
end
for _, name in ipairs({ "nvim-ts-autotag", "mini.surround", "bento", "blink.cmp" }) do
  package.loaded[name] = { setup = function() end, get_lsp_capabilities = function(caps) return caps end }
end
package.loaded["bento.api"] = setmetatable({ actions = {} }, {
  __index = function() return function() end end,
})
dofile(root .. "/dotfiles/dot_config/nvim/plugin/40_editing.lua")
configure()
local conform = require("conform")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
vim.fn.writefile({ '{"overrides":[{"files":"*.html","options":{"tabWidth":4}}]}' }, directory .. "/.prettierrc.json")

local ok, err = xpcall(function()
  local source = {
    '<div class="container">',
    "  @if (title()) {",
    "    <h3 appTitle>{{title()}}</h3>",
    "  }",
    "  <ng-content />",
    "</div>",
  }
  for _, filetype in ipairs({ "htmlangular", "html" }) do
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
    vim.api.nvim_buf_set_name(0, directory .. "/" .. filetype .. ".html")
    vim.bo.filetype = filetype
    vim.api.nvim_buf_set_lines(0, 0, -1, false, source)
    local formatters = conform.list_formatters(0)
    assert(#formatters > 0, "No formatter configured for " .. filetype)
    local failure
    conform.format({ timeout_ms = 10000, lsp_format = "fallback" }, function(problem) failure = problem end)
    assert(not failure, failure)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if filetype == "htmlangular" then
      assert(lines[3] == "        <h3 appTitle>{{ title() }}</h3>", vim.inspect(lines))
    else
      assert(lines[2]:match("^    @if"), "HTML formatter ignored the project configuration")
    end
  end
  print("PASS: HTML and Angular formatters; Angular control-flow indentation; project Prettier configuration")
end, debug.traceback)
vim.fn.delete(directory, "rf")
assert(ok, err)
vim.cmd("qa!")
