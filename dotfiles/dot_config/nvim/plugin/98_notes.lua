local map = vim.keymap.set

vim.pack.add({
  {
    src = "https://github.com/nvim-orgmode/orgmode",
    data = {
      ft = { "org", "org_archive" },
      cmd = { "Org", "OrgExport" },
      event = {
        {
          event = { "BufReadPre", "BufNewFile" },
          pattern = { "*.org", "*.org_archive" },
        },
      },
      after = function()
        require("orgmode").setup({
          mappings = {
            org = {
              org_open_at_point = "<CR>",
            },
          },
        })

        vim.lsp.enable("org")

        local bufnr = vim.api.nvim_get_current_buf()
        if vim.bo[bufnr].filetype == "org" then
          vim.b[bufnr].did_ftplugin = nil
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd.runtime({ "ftplugin/org.lua", bang = true })
          end)

          local filename = vim.api.nvim_buf_get_name(bufnr)
          if filename ~= "" then
            pcall(function()
              require("orgmode"):reload(filename)
            end)
          end
        end
      end,
    },
  },
  {
    src = "https://github.com/chipsenkbeil/org-roam.nvim",
    data = {
      cmd = { "RoamSave", "RoamSelect", "RoamQuickSwitch" },
      before = function()
        require("lz.n").trigger_load("orgmode")
      end,
      after = function()
        require("org-roam").setup({
          directory = "~/org-roam",
          bindings = {},
        })
      end,
    },
  },
}, { load = require("lz.n").load })

local function roam_picker(on_confirm)
  require("lz.n").trigger_load({ "orgmode", "org-roam.nvim" })
  local roam = require("org-roam")
  local snacks = require("snacks")
  local db = roam.database:internal_sync()
  local items = {}

  for _, id in ipairs(db:ids()) do
    local node = db:get(id)
    items[#items + 1] = {
      text = table.concat({
        node.title,
        table.concat(node.aliases, " "),
        table.concat(node.tags, " "),
      }, " "),
      node = node,
      file = node.file,
      pos = {
        node.range.start.row + 1,
        node.range.start.column,
      },
    }
  end

  snacks.picker.pick({
    title = "Org Roam",
    items = items,
    format = function(item)
      return {
        { item.node.title },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        on_confirm(item.node)
      end
    end,
  })
end

local function roam_find()
  roam_picker(function(node)
    require("org-roam.utils").goto_node({
      node = node,
    })
  end)
end

local function roam_insert()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(win)

  roam_picker(function(node)
    local link = ("[[id:%s][%s]]"):format(node.id, node.title)
    vim.api.nvim_buf_set_text(
      buf,
      cursor[1] - 1,
      cursor[2],
      cursor[1] - 1,
      cursor[2],
      { link }
    )
  end)
end

map("n", "<leader>rf", roam_find, {
  desc = "Find roam node",
})

map("n", "<leader>ri", roam_insert, {
  desc = "Insert roam node",
})
