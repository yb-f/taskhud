local mq = require('mq')
local ImGui = require 'ImGui'
local actors = require 'actors'
local ICONS = require('mq.Icons')

local openGUI, drawGUI = true, true
local connected_list = {}
local combo_selected = 1
local window_flags = bit32.bor(ImGuiWindowFlags.None)
--local window_flags = bit32.bor(ImGuiWindowFlags.AlwaysAutoResize)
local myName = mq.TLO.Me.DisplayName()
local running = true
local tasks = {}
local objectives = {}
local do_refresh = false
local task_selected = 1
local do_update_tasks = true
local requester = ''
local arg = { ... }
local changed = false
local list_item = 0
local task_selected_name = ''
local selected_character = ''
local num_updates_finished = 0
local update_done = false
local character_message_received = false
local taskheader = "\ay[\agTaskHud\ay]"

if mq.TLO.Plugin('mq2dannet').IsLoaded() == false then
    printf("%s \aoDanNet is required for this plugin.  \arExiting", taskheader)
    mq.exit()
end

local function dannet_connected()
    connected_list = {}
    local peers_list = mq.TLO.DanNet.Peers()
    for word in string.gmatch(peers_list, '([^|]+)') do
        table.insert(connected_list, word)
    end
end

local function task_window_open()
    return mq.TLO.Window('TaskWnd').Open()
end

local function get_selection_num()
    if mq.TLO.Window('TaskWnd').Child('TASK_TaskList').GetCurSel() == list_item then
        return true
    end
    return false
end

local function send_character()
    actors:send(
        {
            script = 'taskhud',
            id = 'NEW_CHARACTER',
            recepient = requester,
            sender = string.lower(mq.TLO.Me.DisplayName())
        })
    do_update_tasks = false
end



local function update_tasks()
    mq.cmd("/windowstate TaskWnd open")
    mq.delay("2s", task_window_open)
    local count = 1
    local count_two = 1
    for i = 1, mq.TLO.Window('TaskWnd').Child('TASK_TaskList').Items() do
        mq.cmdf('/notify TaskWnd TASK_TaskList listselect %s', i)
        list_item = i
        mq.delay(200, get_selection_num)
        if mq.TLO.Window('TaskWnd').Child('TASK_TaskList').List(i, 3)() ~= nil then
            actors:send(
                {
                    script = 'taskhud',
                    id = 'NEW_TASK',
                    recepient = requester,
                    sender = string.lower(mq.TLO.Me.DisplayName()),
                    taskID = count,
                    name = mq.TLO.Window('TaskWnd').Child('TASK_TaskList').List(i, 3)()
                })
            for j = 1, mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').Items() do
                if mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').List(j, 2)() ~= nil then
                    actors:send(
                        {
                            script = 'taskhud',
                            id = 'TASK_OBJECTIVE',
                            recepient = requester,
                            sender = string.lower(mq.TLO.Me.DisplayName()),
                            taskID = count,
                            name = mq.TLO.Window('TaskWnd').Child('TASK_TaskList').List(i, 3)(),
                            objective = mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').List(j, 1)(),
                            status = mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').List(j, 2)(),
                            objectiveID = count_two
                        })
                    count_two = count_two + 1
                end
            end
            count_two = 1
            count = count + 1
        end
    end
    actors:send(
        {
            script = 'taskhud',
            id = 'END_TASKS',
            recepient = requester,
            sender = string.lower(mq.TLO.Me.DisplayName())
        })
    character_message_received = false
    requester = ''
    mq.cmd("/windowstate TaskWnd close")
end

local actor = actors.register(function(message)
    if message.content.id == 'NEW_CHARACTER' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            tasks[message.content.sender] = {}
            objectives[message.content.sender] = {}
            actors:send(
                {
                    script = 'taskhud',
                    id = 'CHARACTER_RECEIVED',
                    recepient = message.content.sender
                })
        end
    end
    if message.content.id == 'CHARACTER_RECEIVED' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            character_message_received = true
        end
    end
    if message.content.id == 'NEW_TASK' then
        if message.content.recepient == string.lower(mq.TLO.Me.DisplayName()) then
            table.insert(tasks[message.content.sender], message.content.taskID, message.content.name)
            if task_selected_name == message.content.name and message.content.sender == connected_list[combo_selected] then
                task_selected = message.content.taskID
            end
            objectives[message.content.sender][message.content.taskID] = {}
        end
    elseif message.content.id == 'TASK_OBJECTIVE' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            objectives[message.content.sender][message.content.taskID][message.content.objectiveID] = {
                ['objective'] = message.content.objective,
                ['status'] = message.content.status
            }
        end
    elseif message.content.id == 'END_TASKS' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            num_updates_finished = num_updates_finished + 1
        end
    elseif message.content.id == 'REQUEST_TASKS' then
        requester = message.content.sender
        do_update_tasks = true
    end
end)

local function request_task_update()
    if tasks[selected_character] ~= nil then
        task_selected_name = tasks[selected_character][task_selected]
    end
    tasks = {}
    objectives = {}
    actor:send({ script = 'taskhud' },
        {
            script = 'taskhud',
            id = 'REQUEST_TASKS',
            recepient = connected_list[combo_selected],
            sender = string.lower(mq.TLO.Me.DisplayName())
        })
    selected_character = connected_list[combo_selected]
    do_refresh = false
end

local function displayGUI()
    if not openGUI then running = false end
    if update_done == false then return end
    openGUI, drawGUI = ImGui.Begin("Task HUD##" .. myName, openGUI, window_flags)
    if drawGUI then
        dannet_connected()
        combo_selected, changed = ImGui.Combo('##CharacterCombo', combo_selected, connected_list, #connected_list,
            #connected_list)
        --if changed then do_refresh = true end
        ImGui.SameLine()
        if ImGui.SmallButton(ICONS.MD_REFRESH) then
            do_refresh = true
        end
        if tasks[connected_list[combo_selected]] ~= nil then
            task_selected = ImGui.Combo('##TaskCombo', task_selected, tasks[connected_list[combo_selected]])
        end
        local missing_list = {}
        if #tasks[connected_list[combo_selected]] > 0 then
            for i, name in pairs(tasks) do
                local matched = false
                for j, task in pairs(name) do
                    if task == tasks[connected_list[combo_selected]][task_selected] then
                        matched = true
                    end
                end
                if matched == false then
                    table.insert(missing_list, i)
                end
            end
            if #missing_list > 0 then
                ImGui.SeparatorText("Missing this task")
                for i, missing in pairs(missing_list) do
                    ImGui.TextColored(IM_COL32(180, 50, 50),
                        string.upper(string.sub(missing, 1, 1)) .. string.sub(missing, 2, -1))
                    if i < #missing_list then
                        ImGui.SameLine()
                        ImGui.Text(ICONS.MD_REMOVE)
                        ImGui.SameLine()
                    end
                end
                ImGui.Separator()
            end
        end
        if ImGui.BeginTable('##ObjectivesTable', 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)) then
            if objectives[connected_list[combo_selected]] ~= nil and objectives[connected_list[combo_selected]][task_selected] ~= nil then
                for i = 1, #objectives[connected_list[combo_selected]][task_selected] do
                    ImGui.TableNextColumn()
                    ImGui.Text(objectives[connected_list[combo_selected]][task_selected][i].objective)
                    ImGui.TableNextColumn()
                    if objectives[connected_list[combo_selected]][task_selected][i].status == 'Done' then
                        ImGui.TextColored(IM_COL32(0, 255, 0, 255),
                            objectives[connected_list[combo_selected]][task_selected][i].status)
                    else
                        ImGui.Text(objectives[connected_list[combo_selected]][task_selected][i].status)
                    end
                    ImGui.TableNextColumn()
                    for index, name in pairs(connected_list) do
                        local second_task_selected = 0
                        local im_missing = false
                        for j, missing_name in pairs(missing_list) do
                            if name == missing_name then
                                im_missing = true
                            end
                        end
                        if not im_missing then
                            if tasks[connected_list[combo_selected]][task_selected] ~= tasks[name][task_selected] then
                                for k, task_name in pairs(tasks[name]) do
                                    if tasks[connected_list[combo_selected]][task_selected] == task_name then
                                        second_task_selected = k
                                    end
                                end
                            else
                                second_task_selected = task_selected
                            end
                            if objectives[connected_list[combo_selected]][task_selected][i].status ~= objectives[name][second_task_selected][i].status then
                                local first_status = objectives[connected_list[combo_selected]][task_selected][i].status
                                local second_status = objectives[name][second_task_selected][i].status
                                local first_status_digit = tonumber(string.sub(first_status, 1, 1))
                                local second_status_digit = tonumber(string.sub(second_status, 1, 1))
                                if first_status ~= 'Done' and second_status == 'Done' then
                                    ImGui.TextColored(IM_COL32(50, 180, 50),
                                        string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                    ImGui.SameLine()
                                elseif first_status == 'Done' and second_status ~= 'Done' then
                                    ImGui.TextColored(IM_COL32(180, 50, 50),
                                        string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                    ImGui.SameLine()
                                elseif first_status_digit ~= nil and second_status_digit ~= nil then
                                    if tonumber(string.sub(first_status, 1, 1)) > tonumber(string.sub(first_status, 1, 1)) then
                                        ImGui.TextColored(IM_COL32(180, 50, 50),
                                            string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                        ImGui.SameLine()
                                    elseif tonumber(string.sub(first_status, 1, 1)) < tonumber(string.sub(first_status, 1, 1)) then
                                        ImGui.TextColored(IM_COL32(50, 180, 50),
                                            string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                        ImGui.SameLine()
                                    end
                                end
                            end
                        end
                    end
                    ImGui.TableNextRow()
                end
            end
        end
        ImGui.EndTable()
    end
    ImGui.End()
end
local function main()
    while running == true do
        mq.delay(200)
        if do_refresh == true then
            num_updates_finished = 0
            update_done = false
            request_task_update()
        end
        if do_update_tasks == true then
            send_character()
        end
        if character_message_received == true then
            update_tasks()
        end
        if num_updates_finished == mq.TLO.DanNet.PeerCount() then
            update_done = true
        end
    end
    mq.cmd("/dgae /lua stop taskhud")
end

local function init()
    mq.cmd('/dge /lua run taskhud nohud')
    dannet_connected()
    for i, name in pairs(connected_list) do
        if name == string.lower(mq.TLO.Me.DisplayName()) then combo_selected = i end
    end
    do_refresh = true
    --mq.delay(200)
    --request_task_update()
end

if #arg == 0 then
    init()
    mq.delay(200)
    mq.imgui.init('displayGUI', displayGUI)
    main()
elseif arg[1]:lower() == 'nohud' then
    main()
end

mq.imgui.init('displayGUI', displayGUI)
