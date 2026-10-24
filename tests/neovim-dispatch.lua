local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site/pack/core/opt/vim-dispatch")
vim.o.lines = 40
vim.o.columns = 120
vim.o.shell = vim.fn.exepath("sh")
local installed = false
vim.pack.add = function(specs)
  for _, spec in ipairs(specs) do
    if spec.src == "https://github.com/tpope/vim-dispatch" then
      installed = true
      assert(vim.list_contains(spec.data.cmd, "Dispatch"))
      assert(vim.list_contains(spec.data.cmd, "Copen"))
      vim.cmd("runtime plugin/dispatch.vim")
    end
  end
end
package.loaded["lz.n"] = { load = function() end }
dofile(root .. "/dotfiles/dot_config/nvim/plugin/70_lsp.lua")
assert(installed, "Dispatch is not configured")
assert(vim.fn.maparg("m<CR>", "n") == "", "Dispatch installed unaliased default mappings")
assert(vim.fn["dispatch#compiler_for_program"]("npm run build") == "npm", "npm compiler was not detected")

local directory = vim.fn.tempname() .. " build project"
vim.fn.mkdir(directory .. "/src", "p")
vim.fn.writefile({ "line1", "line2", "line3", "line4", "line5" }, directory .. "/src/source.ts")
vim.fn.writefile({ "<unknown></unknown>", "<another></another>" }, directory .. "/src/template.html")
vim.fn.writefile({ 'const answer: number = "wrong";' }, directory .. "/src/real.ts")
local tsc = vim.fn.exepath("tsc")
assert(tsc ~= "", "Install TypeScript before running this test")
vim.fn.writefile({ vim.json.encode({
  scripts = {
    build = "node build.cjs",
    success = "node -e \"console.log('Build complete')\"",
    typecheck = vim.fn.shellescape(tsc) .. " --noEmit --pretty false src/real.ts",
  },
}) }, directory .. "/package.json")
local output = {
  "src/source.ts(2,7): error TS2322: Type 'string' is not assignable to type 'number'.",
  "Error: src/source.ts:3:4 - error TS2345: Legacy Angular error.",
  "✘ [ERROR] TS2339: Property 'missing' does not exist. [plugin angular-compiler]",
  "",
  "    src/source.ts:4:5:",
  "      4 │ value.missing",
  "        ╵       ~~~~~~~",
  "",
  "▲ [WARNING] NG8113: Unused import. [plugin angular-compiler]",
  "",
  "    src/template.html:1:2:",
  "      1 │ <unknown></unknown>",
  "        ╵  ~~~~~~~",
  "",
  "✘ [ERROR] NG8001: 'another' is not a known element. [plugin angular-compiler]",
  "",
  "    src/template.html:2:3:",
  "      2 │ <another></another>",
  "        ╵   ~~~~~~~",
  "",
  "  Error occurs in the template of component App.",
  "",
  "    src/source.ts:5:1:",
  "      5 │ templateUrl: './template.html'",
  "        ╵ ~~~~~~~~~~~",
}
vim.fn.writefile({ "setTimeout(() => { console.log(" .. vim.json.encode(table.concat(output, "\n")) .. "); process.exitCode = 1; }, 300);" }, directory .. "/build.cjs")

local ok, err = xpcall(function()
  vim.cmd.cd(vim.fn.fnameescape(directory))
  local makeprg, errorformat = vim.o.makeprg, vim.o.errorformat
  vim.cmd("Dispatch npm run build")
  local request = vim.fn["dispatch#request"]()
  assert(request.handler == "job", "Build did not use Neovim's asynchronous job handler")
  assert(vim.fn["dispatch#completed"](request.id) == 0, "Dispatch blocked until the build completed")
  local scheduled = false
  vim.schedule(function() scheduled = true end)
  assert(vim.wait(10000, function() return vim.fn["dispatch#completed"](request.id) == 1 end, 10), "Build did not finish")
  assert(scheduled, "Build blocked Neovim's event loop")
  assert(vim.o.makeprg == makeprg and vim.o.errorformat == errorformat, "Dispatch changed editor defaults")
  local errors = vim.tbl_filter(function(item) return item.valid == 1 end, vim.fn.getqflist())
  assert(#errors == 5, "Expected five diagnostics, got " .. vim.inspect(errors))
  for index, expected in ipairs({
    { "source.ts", 2, 7, "E", "TS2322" },
    { "source.ts", 3, 4, "E", "TS2345" },
    { "source.ts", 4, 5, "E", "TS2339" },
    { "template.html", 1, 2, "W", "NG8113" },
    { "template.html", 2, 3, "E", "NG8001" },
  }) do
    local item = errors[index]
    assert(vim.endswith(vim.api.nvim_buf_get_name(item.bufnr), "/src/" .. expected[1]), vim.inspect({ item = item, file = vim.api.nvim_buf_get_name(item.bufnr) }))
    assert(item.lnum == expected[2] and item.col == expected[3], vim.inspect(item))
    assert(item.type == expected[4] and item.text:find(expected[5], 1, true), vim.inspect(item))
  end
  vim.cmd("Copen")
  assert(vim.bo.buftype == "quickfix", "Build error list did not open")
  for index, item in ipairs(vim.fn.getqflist()) do
    if item.bufnr == errors[4].bufnr and item.lnum == 1 then
      vim.cmd("cc " .. index)
      break
    end
  end
  assert(vim.endswith(vim.api.nvim_buf_get_name(0), "/src/template.html"), vim.inspect({ file = vim.api.nvim_buf_get_name(0), items = vim.fn.getqflist() }))
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 1 }), "Quickfix did not jump to the diagnostic")
  vim.cmd.cnext()
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 2 }), "Next error did not jump to the next location")
  vim.cmd("Copen!")
  assert(vim.iter(vim.fn.getqflist()):any(function(item) return item.text:find("Error occurs in the template", 1, true) ~= nil end), "Raw output is unavailable")
  vim.cmd("Dispatch npm run success")
  local success = vim.fn["dispatch#request"]()
  assert(vim.wait(10000, function() return vim.fn["dispatch#completed"](success.id) == 1 end, 10))
  assert(#vim.tbl_filter(function(item) return item.valid == 1 end, vim.fn.getqflist()) == 0, "Successful build retained old errors")
  vim.cmd("Dispatch npm run typecheck")
  local typecheck = vim.fn["dispatch#request"]()
  assert(vim.wait(10000, function() return vim.fn["dispatch#completed"](typecheck.id) == 1 end, 10))
  local type_errors = vim.tbl_filter(function(item) return item.valid == 1 end, vim.fn.getqflist())
  assert(#type_errors == 1 and type_errors[1].text:find("TS2322", 1, true), vim.inspect(type_errors))
  assert(vim.endswith(vim.api.nvim_buf_get_name(type_errors[1].bufnr), "/src/real.ts"))
  assert(type_errors[1].lnum == 1 and type_errors[1].col == 7)
  print("PASS: asynchronous npm build, real TypeScript compiler, Angular locations, warnings, related-location exclusion, quickfix jumps, full logs and successful rebuild")
end, debug.traceback)
vim.cmd.cd(vim.fn.fnameescape(root))
vim.fn.delete(directory, "rf")
if not ok then error(err) end
vim.cmd("qa!")
