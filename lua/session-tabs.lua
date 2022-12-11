local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local conf = require("telescope.config").values

M = {}

local defaultConfig = {
    sessionsPath = "~/.local/share/nvim/session-tabs",
    bufFilter = { "component://", "nvim-ide-log://" }
}

local config = {
    sessionsPath = nil,
    bufFilter = nil,
}

local function scandir(directory)
    local pfile = io.popen('ls -a "' .. directory .. '"')

    if pfile == nil then
        return {}
    end

    local t = {}
    local i = 0
    for filename in pfile:lines() do
        if filename == "." or filename == ".." then
            goto continue
        end
        i = i + 1
        t[i] = filename
        ::continue::
    end

    pfile:close()

    return t
end

local function nameSession()
    return vim.fn.input("Session name: ", "")
end

local function filterBuffers(name)
    -- ignore no-names
    if name == "" then
        return false
    end

    -- filter based on config.bufFilter
    for _, f in ipairs(config.bufFilter) do
        if string.find(name, f, 0, true) ~= nil then
            return false
        end
    end

    return true
end

local function readFile(file)
    local ret = {}

    for line in io.lines(file) do
        table.insert(ret, line)
    end

    return ret
end

local function getSessionData(file)
    local name
    local time
    for line in io.lines(file) do
        if string.find(line, '^" name:') then
            name = string.gsub(line, '" name:', "")
        end
        if string.find(line, '^" time:') then
            time = string.gsub(line, '" time:', "")
        end
    end

    return name, time
end

local function getSessions()
    local files = scandir(config.sessionsPath .. "/")

    local ret = {}

    for _, v in ipairs(files) do
        local name, time = getSessionData(config.sessionsPath .. "/" .. v)

        ret[name] = {
            time = time,
            path = config.sessionsPath .. "/" .. v
        }
    end

    return ret
end

-- our picker function: colors
M.selectSession = function()
    local sessions = getSessions()

    local opts = config.telescopeOpts or {}

    local sessionNames = function()
        local ret = {}
        for k, _ in pairs(sessions) do
            table.insert(ret, k)
        end

        return ret
    end

    pickers.new(require('telescope.themes').get_dropdown {}, {
        prompt_title = "Sessions",
        finder = finders.new_table {
            results = sessionNames()
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)

                local selection = action_state.get_selected_entry()

                if selection == nil then
                    return
                end

                vim.cmd("tabnew")
                vim.cmd("source " .. sessions[selection[1]].path)
            end)

            return true
        end
    }):find()
end

local function nameExists(name)
    local sessions = getSessions()

    for k, _ in pairs(sessions) do
        if k == name then
            return true
        end
    end

    return false
end

M.saveSession = function()
    local oldSessOpts = vim.o.sessionoptions
    vim.o.sessionoptions = "buffers,curdir,winpos,winsize"

    local name = nameSession()

    if name == "" then
        return
    end

    if nameExists(name) then
        vim.notify("Name '" .. name .. "' already exists.", vim.log.levels.ERROR)
        return
    end

    local sessionPath = config.sessionsPath .. "/" .. name .. ".vim"

    vim.cmd("mksession " .. sessionPath .. ".tmp")

    vim.o.sessionoptions = oldSessOpts

    local fileLines = readFile(sessionPath .. ".tmp")

    local finalFile = {}
    for _, line in ipairs(fileLines) do
        if filterBuffers(line) then
            table.insert(finalFile, line)
        end
    end

    local handle = io.open(sessionPath, "w")
    if handle == nil then
        return
    end

    -- save a little meta data so we can present a nice list later
    handle:write('" name:' .. name .. "\n")
    handle:write('" time:' .. os.time() .. "\n")

    for _, line in ipairs(finalFile) do
        if not string.find(line, "$argadd") then
            handle:write(line .. "\n")
        end
    end

    -- cleanup
    os.remove(sessionPath .. ".tmp")
    handle:flush()
    handle:close()
end

M.setup = function(setupConfig)
    config = vim.deepcopy(defaultConfig)
    if setupConfig ~= nil then
        config = vim.deepcopy(setupConfig)
    end

    config.sessionsPath = vim.fn.expand(config.sessionsPath)
end

return M
