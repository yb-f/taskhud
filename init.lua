local mq = require('mq')
local ImGui = require 'ImGui'
local actors = require 'actors'
local ICONS = require('mq.Icons')

local openGUI, drawGUI = true, true
local connected_list = {}
local combo_selected = 1
local window_flags = bit32.bor(ImGuiWindowFlags.AlwaysAutoResize)
local myName = mq.TLO.Me.DisplayName()
local running = true
local tasks = {}
local objectives = {}
local do_refresh = false
local task_selected = 1
local do_update_tasks = false
local requester = ''
local arg = { ... }
local changed = false
local list_item = 0

if mq.TLO.Plugin('mq2dannet').IsLoaded() == false then
    printf("%s \aoDanNet is required for this plugin.  \arExiting", cchheader)
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

local function update_tasks()
    actors:send(
        {
            script = 'taskhud',
            id = 'CLEAR_TASKS',
            recepient = requester,
            sender = mq.TLO.Me.DisplayName()
        })
    mq.cmd("/windowstate TaskWnd open")
    mq.delay("2s", task_window_open)
    local count = 1
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
                    sender = mq.TLO.Me.DisplayName(),
                    taskID = count,
                    name = mq.TLO.Window('TaskWnd').Child('TASK_TaskList').List(i, 3)()
                })
            for j = 1, mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').Items() do
                actors:send(
                    {
                        script = 'taskhud',
                        id = 'TASK_OBJECTIVE',
                        recepient = requester,
                        sender = mq.TLO.Me.DisplayName(),
                        taskID = count,
                        objective = mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').List(j, 1)(),
                        status = mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').List(j, 2)(),
                        objectiveID = j
                    })
            end
            count = count + 1
        end
    end
    do_update_tasks = false
    requester = ''
    mq.cmd("/windowstate TaskWnd close")
end

local actor = actors.register(function(message)
    if message.content.id == 'NEW_TASK' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            tasks[message.content.taskID] = message.content.name
            table.insert(objectives, message.content.taskID, {})
        end
    elseif message.content.id == 'TASK_OBJECTIVE' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            table.insert(objectives[message.content.taskID], message.content.objectiveID,
                { ['objective'] = message.content.objective, ['status'] = message.content.status })
        end
    elseif message.content.id == 'REQUEST_TASKS' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            requester = message.content.sender
            do_update_tasks = true
        end
    elseif message.content.id == 'CLEAR_TASKS' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            tasks = {}
            objectives = {}
        end
    end
end)

local function request_task_update()
    actor:send({ script = 'taskhud' },
        {
            script = 'taskhud',
            id = 'REQUEST_TASKS',
            recepient = connected_list[combo_selected],
            sender = mq.TLO.Me.DisplayName()
        })
    do_refresh = false
end

local function displayGUI()
    if not openGUI then running = false end
    openGUI, drawGUI = ImGui.Begin("Task HUD##" .. myName, openGUI, window_flags)
    if drawGUI then
        dannet_connected()
        combo_selected, changed = ImGui.Combo('##CharacterCombo', combo_selected, connected_list, #connected_list,
            #connected_list)
        if changed then do_refresh = true end
        ImGui.SameLine()
        if ImGui.SmallButton(ICONS.MD_REFRESH) then
            do_refresh = true
        end
        if #tasks > 0 then
            task_selected = ImGui.Combo('##TaskCombo', task_selected, tasks)
        end
        if ImGui.BeginTable('##ObjectivesTable', 2, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)) then
            if objectives[task_selected] ~= nil then
                for i = 1, #objectives[task_selected] do
                    ImGui.TableNextColumn()
                    ImGui.Text(objectives[task_selected][i].objective)
                    ImGui.TableNextColumn()
                    if objectives[task_selected][i].status == 'Done' then
                        ImGui.TextColored(IM_COL32(0, 255, 0, 255), objectives[task_selected][i].status)
                    else
                        ImGui.Text(objectives[task_selected][i].status)
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
            request_task_update()
        end
        if do_update_tasks == true then
            update_tasks()
        end
    end
    mq.cmd("/dage /lua stop taskhud")
end

local function init()
    mq.cmd('/dge /lua run taskhud nohud')
    mq.delay(200)
    request_task_update()
end

if #arg == 0 then
    mq.imgui.init('displayGUI', displayGUI)
    init()
    main()
elseif arg[1]:lower() == 'nohud' then
    main()
end

mq.imgui.init('displayGUI', displayGUI)
