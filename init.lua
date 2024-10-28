--[[
    Create a window where you can compare the progress of tasks vs other dannet connected clients.
]]

local mq = require('mq')
local ImGui = require 'ImGui'
local actors = require 'actors'
local ICONS = require('mq.Icons')

--Default window size on first run
local FIRST_WINDOW_WIDTH = 445
local FIRST_WINDOW_HEIGHT = 490
--Window flags for GUI window, currently none are used but easier this way if any are added later
local window_flags = bit32.bor(ImGuiWindowFlags.None)
local drawGUI = false

--Table with variables that trigger functions to run
local triggers = {
    do_refresh = false,
    timestamp = mq.gettime(),
    need_task_update = false
}

local peer_list = {}
local peer_types = { 'Group', 'Zone', 'All', }

--Table of tasks and objectives
local task_data = {
    tasks = {},
    my_tasks = {},
}
--Table of information about selections
local selected_info = {
    selected_combo = 1,
    selected_peer_type = 1,
    selected_task = 1,
}

--Arguements passed when starting the script (This is important for loading a background version of the script on client machines)
local args = { ... }

local missing = {}

--Header for chat output
local taskheader = "\ay[\agTaskHud\ay]"

local running = true
local debug_mode = false
local my_name = mq.TLO.Me.DisplayName()

local dannet = mq.TLO.Plugin('mq2dannet').IsLoaded()

--End of variable declarations

local function close_script()
    mq.exit()
end

local function get_tasks()
    local tasks = {}
    mq.TLO.Window('TaskWnd').DoOpen()
    while mq.TLO.Window('TaskWnd').Open() == false do
    end
    local count1, count2 = 1, 1
    for i = 1, mq.TLO.Window('TaskWnd/TASK_TaskList').Items() do
        mq.TLO.Window('TaskWnd/TASK_TaskList').Select(i)
        while mq.TLO.Window('TaskWnd/TASK_TaskList').GetCurSel() ~= i do
        end
        --Check that the name of the task is not nil, as is the case with seperator lines
        if mq.TLO.Window('TaskWnd/TASK_TaskList').List(i, 3)() ~= nil then
            tasks[count1] = {
                task_name = mq.TLO.Window('TaskWnd/TASK_TaskList').List(i, 3)(),
                objectives = {},
            }

            --Loop through the objectives of the current task
            for j = 1, mq.TLO.Window('TaskWnd/TASK_TaskElementList').Items() do
                --Check that the name of the objective is not nil, as is the case with seperator lines
                if mq.TLO.Window('TaskWnd/TASK_TaskElementList').List(j, 2)() ~= nil then
                    local tmp_objective = {
                        objective = mq.TLO.Window('TaskWnd/TASK_TaskElementList').List(j, 1)(),
                        status = mq.TLO.Window('TaskWnd/TASK_TaskElementList').List(j, 2)(),
                    }
                    table.insert(tasks[count1]['objectives'], count2, tmp_objective)
                    count2 = count2 + 1
                end
            end
            count2 = 1
            count1 = count1 + 1
        end
    end
    mq.TLO.Window('TaskWnd').DoClose()
    return tasks
end

local function get_missing_tasks()
    local miss_task = {}

    -- Create a list of all tasks across all characters
    for name, task_table in pairs(task_data.tasks) do
        for _, task in ipairs(task_table) do
            local task_name = task.task_name
            -- If the task is not already present in the table, add it
            if not miss_task[task_name] then
                miss_task[task_name] = { missing_characters = {}, objectives = {}, }
            end
        end
    end

    -- Loop over each task and see if each character has it
    for task_name, task_info in pairs(miss_task) do
        for name, task_table in pairs(task_data.tasks) do
            local has_task = false
            for _, task in ipairs(task_table) do
                -- If the character has the task, make note
                if task.task_name == task_name then
                    has_task = true
                    for i, objective in ipairs(task.objectives) do
                        if objective.objective ~= "? ? ?" then -- Skip if objective is unknown
                            local objective_name = objective.objective

                            -- Create an entry for the objective if it does not already exist
                            if not miss_task[task_name].objectives[i] then
                                miss_task[task_name].objectives[i] = { objective_name = objective_name, characters = {}, }
                            end

                            -- Add character's name and status to the objectives table
                            table.insert(miss_task[task_name].objectives[i].characters, {
                                character = name,
                                status = objective.status,
                            })
                        end
                    end
                    break
                end
            end
            -- If has_task is false, add the character to the missing list for that task
            if not has_task then
                table.insert(miss_task[task_name].missing_characters, name)
            end
        end
    end

    -- Debugging output
    if debug_mode then
        for task_name, task_info in pairs(miss_task) do
            print("Task:", task_name)
            print("  Missing characters:", table.concat(task_info.missing_characters, ", "))
            for _, objective_info in ipairs(task_info.objectives) do
                print(string.format("  Objective: %s", objective_info.objective_name))
                for _, entry in ipairs(objective_info.characters) do
                    print(string.format("    Character: %s Status: %s", entry.character, entry.status))
                end
            end
        end
    end
    return miss_task
end

--Message handler
local actor = actors.register(function(message)
    --Handle REQUEST_TASKS message, this will set a variable to trigger the task update function from the main loop
    if message.content.id == 'REQUEST_TASKS' then
        triggers.need_task_update = true
        peer_list = {}
        task_data.tasks = {}
        missing.missing_task_status = {}
        missing.missing_objective_status = {}
        -- local task_table = get_tasks()
        -- message:send({ id = 'INCOMING_TASKS', tasks = task_table, })
    elseif message.content.id == 'INCOMING_TASKS' then
        --Handle INCOMING_TASKS message, this contains all task/objective data for the character who sent it
        if drawGUI == true then
            task_data.tasks[message.sender.character] = message.content.tasks
            table.insert(peer_list, message.sender.character)
            table.sort(peer_list)
        end
        missing = get_missing_tasks()
        triggers.timestamp = mq.gettime()
    elseif message.content.id == 'TASKS_UPDATED' then
        --Handle TASKS_UPDATED message, this is sent when a task update event occurs
        --and will lead to a REQUEST_TASKS request from the most recent requester
        if mq.gettime() > triggers.timestamp + 1500 then
            triggers.do_refresh = true
        end
    elseif message.content.id == 'END_SCRIPT' then
        --Handle END_SCRIPT message, this will gracefully shutdown the taskhud script on all clients
        close_script()
    end
end)

local function request_task_update()
    actor:send({ id = 'REQUEST_TASKS', })
end

local function compare_status(sel_status, cur_status)
    if sel_status == 'Done' and cur_status ~= 'Done' then
        return 1
    elseif cur_status == 'Done' and sel_status ~= 'Done' then
        return -1
    end
    local sel_completed, sel_total = sel_status:match("(%d+)/(%d+)")
    local cur_completed, cur_total = cur_status:match("(%d+)/(%d+)")
    if sel_completed > cur_completed then
        return 1
    elseif cur_completed > sel_completed then
        return -1
    end
    return 0
end

local function displayGUI()
    if not drawGUI then return end
    ImGui.SetNextWindowSize(ImVec2(FIRST_WINDOW_WIDTH, FIRST_WINDOW_HEIGHT), ImGuiCond.FirstUseEver)
    local open, show = ImGui.Begin("Task HUD##" .. my_name, true, window_flags)
    if not open then
        drawGUI = false
    end
    if show then
        ImGui.PushItemWidth(100)
        selected_info.selected_combo = ImGui.Combo('##CharacterCombo', selected_info.selected_combo, peer_list, #peer_list)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Selected character for tasks')
        end
        ImGui.SameLine()
        selected_info.selected_peer_type = ImGui.Combo('##PeerSetCombo', selected_info.selected_peer_type, peer_types, #peer_types)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Peer set to display')
        end
        ImGui.PopItemWidth()
        ImGui.SameLine()
        if ImGui.SmallButton(ICONS.MD_REFRESH) then
            triggers.do_refresh = true
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Refresh task data')
        end
        if task_data.tasks[peer_list[selected_info.selected_combo]] then
            if #task_data.tasks[peer_list[selected_info.selected_combo]] < selected_info.selected_task then
                selected_info.selected_task = 1
            end
            ImGui.PushItemWidth(220)
            if ImGui.BeginCombo('##TaskCombo', task_data.tasks[peer_list[selected_info.selected_combo]][selected_info.selected_task].task_name) then
                for i, task in ipairs(task_data.tasks[peer_list[selected_info.selected_combo]]) do
                    local is_selected = selected_info.selected_task == i
                    if ImGui.Selectable(task.task_name, is_selected) then
                        selected_info.selected_task = i
                    end
                    if is_selected then
                        ImGui.SetItemDefaultFocus()
                    end
                end
                ImGui.EndCombo()
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Selected task')
            end
            ImGui.PopItemWidth()
            local selected_task_name = task_data.tasks[peer_list[selected_info.selected_combo]][selected_info.selected_task].task_name
            if missing[selected_task_name] then
                local missing_characters = missing[selected_task_name].missing_characters
                if #missing_characters > 0 then
                    ImGui.SeparatorText("Mising this task")
                    for i, missing in ipairs(missing_characters) do
                        ImGui.TextColored(IM_COL32(180, 50, 50), missing)
                        if dannet then
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip('Bring %s to foreground', missing)
                                if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                    mq.cmdf('/dex %s /foreground', missing)
                                end
                            end
                        end
                        if i < #missing_characters then
                            ImGui.SameLine()
                            ImGui.Text(ICONS.MD_REMOVE)
                            ImGui.SameLine()
                        end
                    end
                end
                ImGui.Separator()
            end
            if ImGui.BeginTable('##ObjectivesTable', 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)) then
                local selected_task = task_data.tasks[peer_list[selected_info.selected_combo]][selected_info.selected_task]
                for i, objective in ipairs(selected_task.objectives) do
                    ImGui.TableNextColumn()
                    ImGui.Text(objective.objective)
                    ImGui.TableNextColumn()
                    if objective.status == 'Done' then
                        ImGui.TextColored(IM_COL32(0, 255, 0, 255), objective.status)
                    else
                        ImGui.Text(objective.status)
                    end
                    ImGui.TableNextColumn()
                    if missing[selected_task_name] then
                        local objectives = missing[selected_task_name].objectives
                        for j, objective_info in pairs(objectives) do
                            if objective_info.objective_name == objective.objective then
                                for _, entry in ipairs(objective_info.characters) do
                                    if entry.status ~= objective.status and entry.character ~= peer_list[selected_info.selected_combo] and i == j then
                                        local result = compare_status(objective.status, entry.status)
                                        local color = result == -1 and IM_COL32(50, 180, 50) or IM_COL32(180, 50, 10)
                                        ImGui.TextColored(color, entry.character)
                                        if dannet then
                                            if ImGui.IsItemHovered() then
                                                ImGui.SetTooltip('Bring %s to foreground', entry.character)
                                                if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                                    mq.cmdf('/dex %s /foreground', entry.character)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    ImGui.TableNextRow()
                end
                ImGui.EndTable()
            end
        end
    end
    ImGui.End()
end

local cmd_th = function(cmd)
    if cmd == nil or cmd == 'help' then
        printf("%s \ar/th exit \ao--- Exit script (Also \ar/th stop \aoand \ar/th quit)", taskheader)
        printf("%s \ar/th show \ao--- Show UI", taskheader)
        printf("%s \ar/th hide \ao--- Hide UI", taskheader)
        printf("%s \ar/th debug \ao--- Toggle debug mode", taskheader)
    end
    if cmd == 'exit' or cmd == 'quit' or cmd == 'stop' then
        running = false
    end
    if cmd == 'show' then
        printf("%s \aoShowing UI.", taskheader)
        triggers.do_refresh = true
        drawGUI = true
    end
    if cmd == 'hide' then
        printf("%s \aoHiding UI.", taskheader)
        drawGUI = false
    end
    if cmd == 'debug' then
        printf("%s \aoToggling debug mode %s.", taskheader, debug_mode and "off" or "on")
        debug_mode = not debug_mode
    end
end

local function update_tasks()
    task_data.my_tasks = {}
    task_data.my_tasks = get_tasks()
    mq.delay(3000, function() return not mq.TLO.Window('TaskWnd').Open() end)
    actor:send({ id = 'INCOMING_TASKS', tasks = task_data.my_tasks, })
end

local function main()
    mq.delay(500)
    while running do
        mq.doevents()
        mq.delay(200)
        if triggers.do_refresh then
            request_task_update()
            triggers.do_refresh = false
        end
        if triggers.need_task_update then
            triggers.need_task_update = false
            update_tasks()
        end
    end
    actor:send({ id = 'END_SCRIPT', })
    mq.exit()
end

local function update_event()
    actors:send({ id = 'TASKS_UPDATED', })
end

local function create_events()
    mq.event('update_event', '#*#Your task #*# has been updated#*#', update_event)
    mq.event('new_task_event', '#*#You have been assigned the task#*#', update_event)
    mq.event('shared_task_event', '#*#Your shared task#*# has ended.', update_event)
end

local function check_args()
    if #args == 0 then
        mq.cmd('/dge /lua run taskhud nohud')
        drawGUI = true
        --if runtime arguement of 'nohud' do not initialize or draw gui, start main() loop
    elseif args[1]:lower() == 'nohud' then
        drawGUI = false
    elseif args[1]:lower() == 'debug' then
        debug_mode = true
        mq.cmd('/dge /lua run taskhud nohud')
        drawGUI = true
    end
end

local function init()
    create_events()
    mq.imgui.init('displayGUI', displayGUI)
    mq.bind('/th', cmd_th)
    printf("%s \agstarting. use \ar/th help \agfor a list of commands.", taskheader)
    mq.delay(500)
    triggers.do_refresh = true
end

check_args()
init()
main()
