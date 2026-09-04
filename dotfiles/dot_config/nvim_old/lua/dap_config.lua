require("dapui").setup({
  icons = { expanded = "▾", collapsed = "▸" },
  mappings = {

    expand = { "<CR>", "<2-LeftMouse>" },
    open = "o",
    remove = "d",
    edit = "e",
    repl = "r",
    toggle = "t",
  },

  
  expand_lines = vim.fn.has("nvim-0.7"),

  

  

  

  layouts = {
    {
      elements = {

        { id = "scopes", size = 0.25 },
        "breakpoints",
        "stacks",
        "watches",
      },
      size = 40, 
      position = "left",
    },
    {
      elements = {
        "repl",
        "console",
      },
      size = 0.25, 
      position = "bottom",
    },
  },
  floating = {
    max_height = nil, 
    max_width = nil, 
    border = "single", 
    mappings = {
      close = { "q", "<Esc>" },
    },
  },
  windows = { indent = 1 },
  render = {
    max_type_length = nil, 
  }
})

vim.api.nvim_exec(
    [[
    nnoremap <silent> <F5> :lua require'dap'.continue()<CR>
    nnoremap <silent> <F10> :lua require'dap'.step_over()<CR>
    nnoremap <silent> <F11> :lua require'dap'.step_into()<CR>
    nnoremap <silent> <F12> :lua require'dap'.step_out()<CR>
    nnoremap <silent> <leader>b :lua require'dap'.toggle_breakpoint()<CR>
    nnoremap <silent> <leader>B :lua require'dap'.set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>
    nnoremap <silent> <leader>lp :lua require'dap'.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))<CR>
    nnoremap <silent> <leader>dr :lua require'dap'.repl.open()<CR>
    nnoremap <silent> <leader>dl :lua require'dap'.run_last()<CR>
]],
    false
)

local dap = require("dap")

dap.adapters.go = {
    type = "executable",
    command = "node",
    args = {os.getenv("HOME") .. "/dev/golang/vscode-go/dist/debugAdapter.js"}
}
dap.configurations.go = {
    {
        type = "go",
        name = "Debug",
        request = "launch",
        showLog = false,
        program = "${file}",
        dlvToolPath = vim.fn.exepath("dlv") 
    }
}
