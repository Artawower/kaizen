vim.pack.add({
  "https://github.com/nvim-orgmode/orgmode",
  "https://github.com/chipsenkbeil/org-roam.nvim",
  { src = "https://github.com/folke/snacks.nvim" },

})

local map = vim.keymap.set;

require("orgmode").setup({
  mappings = {
    org = {
      org_open_at_point = "<CR>",
    },
  },
})

vim.lsp.enable('org')

require("org-roam").setup({
  directory = "~/org-roam",

  bindings = {

  }
})


local Snacks = require("snacks")
local roam = require("org-roam")

local function roam_picker(on_confirm)
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

  Snacks.picker.pick({
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
    local link = ("[[id:%s][%s]]"):format(
      node.id,
      node.title
    )

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

vim.api.nvim_create_autocmd("User", {
  pattern = "OrgRoamInitialized",
  once = true,

  callback = function()
    map("n", "<leader>rf", roam_find, {
      desc = "Find roam node",
    })

    map("n", "<leader>ri", roam_insert, {
      desc = "Insert roam node",
    })
  end,
})
