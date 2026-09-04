local treesitter = require("nvim-treesitter")
local treesitter_config = require("nvim-treesitter.config")
local prompted = {}

local function start(bufnr, lang)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    vim.api.nvim_buf_call(bufnr, function()
        pcall(vim.treesitter.start, bufnr, lang)
    end)
end

vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("TreesitterConfig", {clear = true}),
    callback = function(event)
        local lang = vim.treesitter.language.get_lang(event.match)
        if not lang or not vim.tbl_contains(treesitter_config.get_available(), lang) then
            return
        end

        local ok, loaded = pcall(vim.treesitter.language.add, lang)
        if ok and loaded then
            start(event.buf, lang)
            return
        end

        if prompted[lang] then
            return
        end
        prompted[lang] = true

        vim.schedule(function()
            vim.ui.select({"Install", "Skip"}, {
                prompt = "Install tree-sitter parser for " .. lang .. "?"
            }, function(choice)
                if choice ~= "Install" then
                    return
                end

                treesitter.install({lang}):await(function()
                    vim.schedule(function()
                        start(event.buf, lang)
                    end)
                end)
            end)
        end)
    end
})
