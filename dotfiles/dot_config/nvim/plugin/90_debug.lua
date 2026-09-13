local map = vim.keymap.set

vim.pack.add({
  {
    src = "https://github.com/mfussenegger/nvim-dap",
    data = {
      cmd = {
        "DapContinue",
        "DapToggleBreakpoint",
        "DapSetLogLevel",
        "DapShowLog",
        "DapStepInto",
        "DapStepOut",
        "DapStepOver",
        "DapTerminate",
        "DapToggleRepl",
        "DapRestartFrame",
        "DapViewToggle",
        "DapViewOpen",
        "DapViewClose",
      },
      after = function()
        require("lz.n").trigger_load("nvim-dap-view")
        require("lz.n").trigger_load("nvim-dap-python")
        require("lz.n").trigger_load("nvim-dap-go")
        require("dap-view").setup({
          auto_toggle = true,
        })
        require("dap-python").setup("debugpy-adapter")
        require("dap-go").setup()
      end,
    },
  },
  {
    src = "https://github.com/igorlfs/nvim-dap-view",
    version = vim.version.range("1.*"),
    data = { lazy = true },
  },
  {
    src = "https://github.com/mfussenegger/nvim-dap-python",
    data = { lazy = true },
  },
  {
    src = "https://github.com/leoluz/nvim-dap-go",
    data = { lazy = true },
  },
}, { load = require("lz.n").load })

local function dap()
  require("lz.n").trigger_load("nvim-dap")
  return require("dap")
end

map({ "n", "x" }, "<leader>dc", function()
  dap().continue()
end, {
  desc = "Debug continue",
})

map({ "n", "x" }, "<leader>db", function()
  dap().toggle_breakpoint()
end, {
  desc = "Toggle breakpoint",
})

map("n", "<leader>dB", function()
  dap().set_breakpoint(vim.fn.input("Breakpoint condition: "))
end, {
  desc = "Conditional breakpoint",
})

map({ "n", "x" }, "<leader>dn", function()
  dap().step_over()
end, {
  desc = "Step over",
})

map({ "n", "x" }, "<leader>di", function()
  dap().step_into()
end, {
  desc = "Step into",
})

map({ "n", "x" }, "<leader>do", function()
  dap().step_out()
end, {
  desc = "Step out",
})

map({ "n", "x" }, "<leader>dq", function()
  dap().terminate()
end, {
  desc = "Terminate debug session",
})

map({ "n", "x" }, "<leader>dv", function()
  dap()
  vim.cmd.DapViewToggle()
end, {
  desc = "Toggle debug view",
})

map({ "n", "x" }, "<leader>dr", function()
  dap().repl.toggle()
end, {
  desc = "Toggle debug REPL",
})
