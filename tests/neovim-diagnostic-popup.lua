local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root .. '/dotfiles/dot_config/nvim')
vim.o.lines = 50
vim.o.columns = 140
vim.g.mapleader = ' '
vim.pack.add = function() end
package.loaded['lz.n'] = { load = function() end, trigger_load = function() end }
dofile(root .. '/dotfiles/dot_config/nvim/plugin/20_keymaps.lua')
dofile(root .. '/dotfiles/dot_config/nvim/plugin/70_lsp.lua')
local editor = vim.api.nvim_get_current_win()
local buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { '        catchError((e) => {', '          broken expression' })
local namespace = vim.api.nvim_create_namespace('DiagnosticPopupTest')
vim.diagnostic.set(namespace, buffer, {
  { lnum = 0, col = 19, end_col = 25, severity = vim.diagnostic.severity.ERROR, message = 'Callback must return an observable' },
  { lnum = 0, col = 20, end_col = 24, severity = vim.diagnostic.severity.WARN, message = 'Another issue on this line' },
  { lnum = 1, col = 0, end_col = 20, severity = vim.diagnostic.severity.ERROR, message = 'Different line error' },
})
local function hold()
  vim.api.nvim_exec_autocmds('CursorHold', { buffer = 0 })
end
local function preview()
  local window = vim.b[buffer].lsp_floating_preview
  return window and vim.api.nvim_win_is_valid(window) and window or nil
end
local function contents(window)
  return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false), '\n')
end
local function close_preview()
  vim.api.nvim_set_current_win(editor)
  if preview() then vim.api.nvim_win_close(preview(), true) end
end
local failures = {}
local function check(name, test)
  close_preview()
  local ok, err = pcall(test)
  if not ok then failures[#failures + 1] = name .. ': ' .. err end
end
check('Diagnostics cover the whole current line', function()
  vim.api.nvim_win_set_cursor(editor, { 1, 8 })
  hold()
  assert(preview(), 'No popup outside the exact diagnostic range')
  local text = contents(preview())
  assert(text:find('Callback must return an observable', 1, true))
  assert(text:find('Another issue on this line', 1, true))
  assert(not text:find('Different line error', 1, true))
  assert(vim.api.nvim_get_current_win() == editor, 'Automatic diagnostics stole focus')
end)
check('Unrelated floating UI does not suppress diagnostics', function()
  vim.api.nvim_win_set_cursor(editor, { 1, 20 })
  local scratch = vim.api.nvim_create_buf(false, true)
  local unrelated = vim.api.nvim_open_win(scratch, false, { relative = 'editor', row = 1, col = 100, width = 20, height = 1 })
  hold()
  local diagnostic = preview()
  assert(vim.api.nvim_win_is_valid(unrelated), 'Diagnostics closed unrelated floating UI')
  vim.api.nvim_win_close(unrelated, true)
  assert(diagnostic, 'Unrelated float suppressed diagnostics')
end)
local pending
vim.lsp.buf_request_all = function(_, method, _, callback)
  assert(method == 'textDocument/hover')
  local context = { bufnr = buffer, version = vim.lsp.util.buf_versions[buffer] }
  pending = function()
    callback({ [1] = { result = { contents = { kind = 'plaintext', value = 'Documentation for catchError' } } } }, context)
  end
end
vim.lsp.get_client_by_id = function() return { name = 'PopupTest', offset_encoding = 'utf-16' } end
for _, key in ipairs({ 'K', ' lh', ' гр' }) do
  check('Documentation wins over diagnostics: ' .. key, function()
    vim.api.nvim_win_set_cursor(editor, { 1, 20 })
    hold()
    local diagnostic = assert(preview())
    pending = nil
    vim.fn.maparg(key, 'n', false, true).callback()
    assert(pending, 'Hover shortcut did not request documentation')
    hold()
    pending()
    local documentation = assert(preview())
    assert(not vim.api.nvim_win_is_valid(diagnostic), 'Explicit hover did not replace diagnostics')
    assert(contents(documentation) == 'Documentation for catchError')
    for _ = 1, 3 do hold() end
    assert(preview() == documentation, 'Automatic diagnostics replaced documentation')
    vim.fn.maparg(key, 'n', false, true).callback()
    pending()
    assert(vim.api.nvim_get_current_win() == documentation, 'Repeated hover did not focus documentation')
    hold()
    assert(preview() == documentation, 'Idle while reading documentation closed it')
    close_preview()
    hold()
    assert(contents(assert(preview())):find('Callback must return an observable', 1, true), 'Diagnostics did not resume after closing documentation')
  end)
end
check('Signature help is not replaced by diagnostics', function()
  vim.api.nvim_win_set_cursor(editor, { 1, 20 })
  local _, signature = vim.lsp.util.open_floating_preview({ 'catchError(selector)' }, 'plaintext', { focus_id = 'textDocument/signatureHelp' })
  hold()
  assert(preview() == signature, 'Diagnostics replaced signature help')
end)
close_preview()
assert(#failures == 0, table.concat(failures, '\n'))
print('PASS: line diagnostics, unrelated floats, asynchronous native hover via K and Latin/Russian leader keys, documentation priority/focus, diagnostic resumption and signature help')
vim.cmd('qa!')
