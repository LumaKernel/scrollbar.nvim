local vim = vim
local api = vim.api

local modules = {}

local default = {
    max_size = 10,
    min_size = 3,
    width = 1,
    right_offset = 1,
    excluded_filetypes = {},
    max_hl_lines = 1000,
    shape = {
        head = "+",
        body = "|",
        tail = "+",
    },
    highlight = {
        head = "Normal",
        body = "Normal",
        tail = "Normal",
    },
    boundaries = [
        {
            shape: "-",
            highlight: "IncSearch",
            from: 1,
        },
        {
            shape: "=",
            highlight: "Search",
            from: 2,
        },
    ],
}

local option = {
    _mt = {
        __index = function(_table, key)
            local val = vim.g["chrombar_" .. key]
            if not val then return default[key] end

            if type(val) == "table" then
                val = vim.tbl_extend("keep", val, default[key])
            end
            return val
        end
    }
}

setmetatable(option, option._mt)

local ns_id = api.nvim_create_namespace("chrombar")

local next_buf_index = (function()
    local next_index = 0

    return function()
        local index = next_index
        next_index = next_index + 1
        return index
    end
end)()

local function get_hl_lines()
    local number_save = vim.wo.number
    local lines = {}
    for s in string.gmatch(api.nvim_command('g//'), "[^\r\n]+") do
        local n = tonumber(string.match(s, "%s*(%d+)"))
        table.insert(lines, n)
    end
    vim.wo.number = number_save
end

local function gen_lines_appearance(size)
    local lines_text = {}
    local lines_hl = {}
    local shape = option.shape
    local lines = { shape.head }
    for _ = 2, size-1 do
        table.insert(lines, shape.body)
    end
    table.insert(lines, shape.tail)
    return lines_text, lines_hl
end

local function add_highlight(bufnr, lines_hl)
    local highlight = option.highlight
    api.nvim_buf_add_highlight(bufnr, ns_id, highlight.head, 0, 0, -1)
    for i = 1, size - 2 do
        api.nvim_buf_add_highlight(bufnr, ns_id, highlight.body, i, 0, -1)
    end
    api.nvim_buf_add_highlight(bufnr, ns_id, highlight.tail, size - 1, 0, -1)
end

local function create_buf(size, lines)
    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(bufnr, "filetype", "chrombar")
    api.nvim_buf_set_name(bufnr, "chrombar_" .. next_buf_index())
    api.nvim_buf_set_lines(bufnr, 0, size, false, lines)

    add_highlight(bufnr, size)

    return bufnr
end

local function clamp_size(size)
    return math.max(option.min_size, math.min(option.max_size, size))
end

local function buf_get_var(bufnr, name)
    local ok, val = pcall(api.nvim_buf_get_var, bufnr, name)
    if ok then return val end
end

function modules.show(winnr, bufnr)
    winnr = winnr or 0
    bufnr = bufnr or 0

    local win_config = api.nvim_win_get_config(winnr)
    -- ignore other floating windows
    if win_config.relative ~= "" then
        return
    end

    local excluded_filetypes = option.excluded_filetypes
    local filetype = api.nvim_buf_get_option(bufnr, "filetype")
    if filetype == "" or vim.tbl_contains(excluded_filetypes, filetype) then
        return
    end

    local total = vim.fn.line("$")
    local height = api.nvim_win_get_height(winnr)

    local show_bar = total > height
    local show_hl = false

    local cursor = api.nvim_win_get_cursor(winnr)
    local curr_line = cursor[1]

    local bar_size = math.ceil(height * height / total)
    bar_size = clamp_size(bar_size)

    local width = api.nvim_win_get_width(winnr)
    local col = width - option.width - option.right_offset
    local row = math.floor((height - bar_size) * (curr_line/total))

    local opts = {
        style = "minimal",
        relative = "win",
        win = winnr,
        width = option.width,
        height = height,
        row = row,
        col = col,
        focusable = false,
    }

    local hl_lines = {}

    if show_hl_lines then
        hl_lines = get_hl_lines()
    end

    local bar_winnr, bar_bufnr
    local state = buf_get_var(bufnr, "chrombar_state")

    if state then -- reuse window
        bar_bufnr = state.bufnr
        bar_winnr = state.winnr or api.nvim_open_win(bar_bufnr, false, opts)

        api.nvim_buf_set_lines(bar_bufnr, 0, -1, false, {})
        local lines_text, lines_hl = gen_lines_appearance(total, bar_lines, hl_lines)
        api.nvim_buf_set_lines(bar_bufnr, 0, bar_size, false, lines_text)
        add_highlight(bar_bufnr, lines_hl)

        if not pcall(api.nvim_win_set_config, bar_winnr, opts) then
            bar_winnr = api.nvim_open_win(bar_bufnr, false, opts)
        end
    else
        local lines_text, lines_hl = gen_lines_appearance(bar_lines, hl_lines)
        bar_bufnr = create_buf(bar_size, lines_text)
        bar_winnr = api.nvim_open_win(bar_bufnr, false, opts)
        api.nvim_win_set_option(bar_winnr, "winhl", "Normal:ChrombarWinHighlight")
        add_highlight(bar_bufnr, lines_hl)
    end

    api.nvim_buf_set_var(bufnr, "chrombar_state", {
        winnr = bar_winnr,
        bufnr = bar_bufnr,
        size  = bar_size,
    })
    return bar_winnr, bar_bufnr
end

function modules.clear(_winnr, bufnr)
    bufnr = bufnr or 0
    local state = buf_get_var(bufnr, "chrombar_state")
    if state and state.winnr then
        api.nvim_win_close(state.winnr, true)
        api.nvim_buf_set_var(bufnr, "chrombar_state", {
            size  = state.size,
            bufnr = state.bufnr,
        })
    end
end

return modules
