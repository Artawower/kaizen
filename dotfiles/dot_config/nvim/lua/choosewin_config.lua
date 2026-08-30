require "window-picker".setup(
    {

        

        

        
        hint = "statusline-winbar",

        
        selection_chars = "JDKSLACMRUEIWOQP",

        picker_config = {
            statusline_winbar_picker = {

                

                selection_display = function(char, windowid)
                    return "%=" .. char .. "%="
                end,

                

                
                use_winbar = "never" 
            },
            floating_big_letter = {

                

                

                font = "ansi-shadow" 
            }
        },

        show_prompt = true,

        prompt_message = "Pick window: ",

        

        

        

        

        filter_func = nil,

        

        filter_rules = {

            
            autoselect_one = true,

            
            include_current_win = true,

            bo = {

                filetype = {"NvimTree", "neo-tree", "notify"},

                buftype = {"terminal"}
            },

            wo = {},

            
            file_path_contains = {},

            
            file_name_contains = {}
        },

        
        highlights = {
            statusline = {
                focused = {
                    fg = "#ededed",
                    bg = "#e35e4f",
                    bold = true
                },
                unfocused = {
                    fg = "#ededed",
                    bg = "#44cc41",
                    bold = true
                }
            },
            winbar = {
                focused = {
                    fg = "#ededed",
                    bg = "#e35e4f",
                    bold = true
                },
                unfocused = {
                    fg = "#ededed",
                    bg = "#44cc41",
                    bold = true
                }
            }
        }
    }
)

local g = vim.g

function SwitchWindow()
    local picked_window_id =
        require("window-picker").pick_window(
        {
            hint = "floating-big-letter"
        }
    )
    if picked_window_id then
        vim.api.nvim_set_current_win(picked_window_id)
    end
end

vim.api.nvim_exec([[
command! SwitchWindow execute 'lua SwitchWindow()'
]], false)
