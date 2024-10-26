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
local openGUI, drawGUI = false, true


--Table with information about peers
local peer_info = {
    peer_groups = { "Group", "Zone", "All" },
    peer_selected = 1,
    peers_count = 1,
    peer_group = '',
    peer_list = '',
    connected_list = {}
}

--Table with variables that trigger functions to run
local triggers = {
    changed = false,
    do_refresh = false,
    do_update_tasks = false,
    update_done = false,
    character_message_received = false,
    requester = ''
}

--Table of tasks and objectives
local task_data = {
    tasks = {},
    objectives = {},
    task_selected = 1,
    data_received_from = {}
}

--Table of information about selections
local selected_info = {
    selected_task_name = '',
    selected_character = '',
    selected_combo = 1
}

--Arguements passed when starting the script (This is important for loading a background version of the script on client machines)
local arg = { ... }

--Header for chat output
local taskheader = "\ay[\agTaskHud\ay]"

local list_item = 0
local running = true
local debug_mode = false
local my_name = string.lower(mq.TLO.Me.DisplayName())


--End of variable declareations

--Exit if dannet is not loaded
if mq.TLO.Plugin('mq2dannet').IsLoaded() == false then
    printf("%s \aoDanNet is required for this plugin.  \arExiting", taskheader)
    mq.exit()
end

--[[
    Populate list of connected peers based on what peer group is selected
    1 = Group
    2 = Zone
    3 = All
]]
local function dannet_connected()
    peer_info.connected_list = {}
    if peer_info.peer_selected == 1 then
        if mq.TLO.EverQuest.Server() ~= nil and mq.TLO.Group.Leader() ~= nil then
            peer_info.peer_group = string.format("group_%s_%s", mq.TLO.EverQuest.Server(), string.lower(mq.TLO.Group.Leader()))
        end
    elseif peer_info.peer_selected == 2 then
        if mq.TLO.EverQuest.Server() ~= nil and mq.TLO.Zone.ShortName() ~= nil then
            peer_info.peer_group = string.format("zone_%s_%s", mq.TLO.EverQuest.Server(), mq.TLO.Zone.ShortName())
        end
    elseif peer_info.peer_selected == 3 then
        peer_info.peer_group = 'all'
    end
    peer_info.peer_list = mq.TLO.DanNet.Peers(peer_info.peer_group)()
    for word in string.gmatch(peer_info.peer_list, '([^|]+)') do
        table.insert(peer_info.connected_list, word)
    end
    peer_info.peers_count = mq.TLO.DanNet.PeerCount(peer_info.peer_group)()
end

--Return true if task window is open, false if not
local function task_window_open()
    return mq.TLO.Window('TaskWnd').Open()
end

--Check which item is selected in the Task List, if it matches list_item return true to end Delay() early
local function get_selection_num()
    if mq.TLO.Window('TaskWnd').Child('TASK_TaskList').GetCurSel() == list_item then
        return true
    end
    return false
end


--[[
    Send a request to connected clients to update task/objective information
    This is done by sending a REQUEST_TASKS message with the recepient field set to a list of
    all characters in the selected peer group
]]
local function request_task_update()
    --Store the name of the currently selected task
    if task_data.tasks[selected_info.selected_character] ~= nil then
        selected_info.selected_task_name = task_data.tasks[selected_info.selected_character][task_data.task_selected]
    end
    selected_info.selected_character = peer_info.connected_list[selected_info.selected_combo]
    --Clear currently stored tasks and objectives
    task_data.tasks = {}
    task_data.objectives = {}
    task_data.data_received_from = {}
    actors:send(
        {
            script = 'taskhud',
            id = 'REQUEST_TASKS',
            recepient = mq.TLO.DanNet.Peers(peer_info.peer_group)(),
            sender = my_name
        })
    selected_info.selected_character = peer_info.connected_list[selected_info.selected_combo]
    --Reset variables that start update process to false
    triggers.do_refresh, triggers.changed = false, false
end

--[[
    Send character information to the character who requested the update
    This sends a NEW_CHARACTER message via actors to indicate that they are a character which should be tracked
]]
local function send_character()
    actors:send(
        {
            script = 'taskhud',
            id = 'NEW_CHARACTER',
            recepient = triggers.requester,
            sender = my_name
        })
    triggers.do_update_tasks = false
end

--[[
    Send task and objective information to the client that made the request
]]
local function update_tasks()
    mq.TLO.Window('TaskWnd').DoOpen()
    --Delay for up to 2s, terminated early if task window is open
    mq.delay("2s", task_window_open)
    --Create two counters to allow skipping over seperator lines in the task log
    local count1, count2 = 1, 1
    for i = 1, mq.TLO.Window('TaskWnd/TASK_TaskList').Items() do
        mq.TLO.Window('TaskWnd/TASK_TaskList').Select(i)
        list_item = i
        --Delay for 200ms or until the selected list item matches i
        mq.delay(200, get_selection_num)
        --Check that the name of the task is not nil, as is the case with seperator lines
        if mq.TLO.Window('TaskWnd/TASK_TaskList').List(i, 3)() ~= nil then
            --Send a NEW_TASK message to the requester, containing task name, and number in list.
            actors:send(
                {
                    script = 'taskhud',
                    id = 'NEW_TASK',
                    recepient = triggers.requester,
                    sender = my_name,
                    taskID = count1,
                    name = mq.TLO.Window('TaskWnd/TASK_TaskList').List(i, 3)()
                })
            --Loop through the objectives of the current task
            for j = 1, mq.TLO.Window('TaskWnd/TASK_TaskElementList').Items() do
                --Check that the name of the objective is not nil, as is the case with seperator lines
                if mq.TLO.Window('TaskWnd/TASK_TaskElementList').List(j, 2)() ~= nil then
                    --Send a TASK_OBJECTIVE message to the requester information on task #, objective # and completion status
                    actors:send(
                        {
                            script = 'taskhud',
                            id = 'TASK_OBJECTIVE',
                            recepient = triggers.requester,
                            sender = my_name,
                            taskID = count1,
                            name = mq.TLO.Window('TaskWnd/TASK_TaskList').List(i, 3)(),
                            objective = mq.TLO.Window('TaskWnd/TASK_TaskElementList').List(j, 1)(),
                            status = mq.TLO.Window('TaskWnd/TASK_TaskElementList').List(j, 2)(),
                            objectiveID = count2
                        })
                    count2 = count2 + 1
                end
            end
            count2 = 1
            count1 = count1 + 1
        end
    end
    --Send END_TASKS message indicating that all task and objective information has been sent
    actors:send(
        {
            script = 'taskhud',
            id = 'END_TASKS',
            recepient = triggers.requester,
            sender = my_name
        })
    --Reset variables and close the task window
    triggers.character_message_received = false
    triggers.requester = ''
    mq.TLO.Window('TaskWnd').DoClose()
end

--[[
    Process incoming messages. Perform appropriate actions for each request type
    request type is stored in message.content.id
    Valid request types are: REQUEST_TASKS, NEW_CHARACTER, CHARACTER_RECEIVED, NEW_TASK, TASK_OBJECTIVE, END_TASKS
]]

local actor = actors.register(function(message)
    if debug_mode == true then
        printf("%s %s - %s -%s", taskheader, message.content.sender, message.content.recepient, message.content.id)
    end
    --[[
        Handle the REQUEST_TASKS message
        This is the first message sent out in the update request process
        We will determine if our name is in the list of recepients
        if so we will store who made the request in triggers.requester and trigger sending updates
    ]]
    if message.content.id == 'REQUEST_TASKS' then
        for word in string.gmatch(message.content.recepient, '([^|]+)') do
            if word == my_name then
                triggers.requester = message.content.sender
                triggers.do_update_tasks = true
            end
        end
        --[[
        Handle the NEW_CHARACTER message
        This message is sent out after the requester sends a REQUEST_TASKS message
        We create a table under tasks and objectives for each character we receive this message from
        Then we send out a CHARACTER_RECEIVED message to indicate
        we received the character and are ready for task/objectives
    ]]
    elseif message.content.id == 'NEW_CHARACTER' then
        if message.content.recepient == my_name then
            task_data.tasks[message.content.sender] = {}
            task_data.objectives[message.content.sender] = {}
            actors:send(
                {
                    script = 'taskhud',
                    id = 'CHARACTER_RECEIVED',
                    recepient = message.content.sender

                })
        end
        --[[
        Handle the CHARACTER_RECEIVED message
        This message is sent out by the requester to each recepient as the requester receives their NEW_CHARACTER messages
        We check if the message is intended for us, and if so set a variable to trigger the next step
    ]]
    elseif message.content.id == 'CHARACTER_RECEIVED' then
        if message.content.recepient == my_name then
            triggers.character_message_received = true
        end

        --[[
        Handle the NEW_TASK message
        This message is sent by each client after they receive the CHARACTER_RECEIVED message
        It is also sent when all objectives for a task have been sent and we are moving to the next task
        We check if the message is intended for us and if so we add the task to the tasks table for the character
        who sent the message. We then check if the received task matches the task that was selected before
        requesting the update and store the new ID if so. Then we create an entry for this task ID in
        the objectives table
    ]]
    elseif message.content.id == 'NEW_TASK' then
        if message.content.recepient == my_name then
            table.insert(task_data.tasks[message.content.sender], message.content.taskID, message.content.name)
            if selected_info.selected_task_name == message.content.name and peer_info.connected_list[selected_info.selected_combo] == message.content.sender then
                task_data.task_selected = message.content.taskID
            end
            task_data.objectives[message.content.sender][message.content.taskID] = {}
        end
        --[[
        Handle the TASK_OBJECTIVE message
        This message is sent after the NEW_TASK message one for each objective of the current task
        We check if the message is intended for us and then add the objective to the objectives
        table for the caracter who send the message
    ]]
    elseif message.content.id == 'TASK_OBJECTIVE' then
        if message.content.recepient == my_name then
            task_data.objectives[message.content.sender][message.content.taskID][message.content.objectiveID] = {
                objective = message.content.objective,
                status = message.content.status
            }
        end
        --[[
        Handle the END_TASKS message
        This is the final message sent by each client in the update exchange
        We check if the message is intended for us and if so we add the sending character to the list
        of characters we have received a full update from.
    ]]
    elseif message.content.id == 'END_TASKS' then
        if message.content.recepient == my_name then
            table.insert(task_data.data_received_from, message.content.sender)
            if debug_mode == true then
                printf("%s Finished receiving from - %s", taskheader, message.content.sender)
            end
        end
    end
end)

local function get_missing_tasks()
    local missing_list = {}
    if task_data.tasks[selected_info.selected_character] and #task_data.tasks[selected_info.selected_character] > 0 then
        for i, name in pairs(task_data.tasks) do
            local matched = false
            for _, task in pairs(name) do
                if task == task_data.tasks[selected_info.selected_character][task_data.task_selected] then
                    matched = true
                    break
                end
            end
            if not matched then
                table.insert(missing_list, i)
            end
        end
    end
    return missing_list
end

local function get_objective_progress(missing_list)
    local progress_info = {}
    if task_data.objectives[selected_info.selected_character] and task_data.objectives[selected_info.selected_character][task_data.task_selected] then
        for i = 1, #task_data.objectives[selected_info.selected_character][task_data.task_selected] do
            local obj_info = {}
            obj_info.objective = task_data.objectives[selected_info.selected_character][task_data.task_selected][i].objective
            obj_info.status = task_data.objectives[selected_info.selected_character][task_data.task_selected][i].status
            obj_info.comparisons = {}
            for _, name in pairs(peer_info.connected_list) do
                local im_missing = false
                for _, missing_name in pairs(missing_list) do
                    if name == missing_name then
                        im_missing = true
                        break
                    end
                end
                if not im_missing then
                    local second_task_selected = task_data.tasks[selected_info.selected_character][task_data.task_selected] == task_data.tasks[name][task_data.task_selected] and
                        task_data.task_selected or nil
                    if task_data.tasks[selected_info.selected_character][task_data.task_selected] ~= task_data.tasks[name][task_data.task_selected] then
                        for k, task_name in pairs(task_data.tasks[name]) do
                            if task_data.tasks[selected_info.selected_character][task_data.task_selected] == task_name then
                                second_task_selected = k
                                break
                            end
                        end
                    end
                    if task_data.objectives[selected_info.selected_character][task_data.task_selected][i] and task_data.objectives[name][second_task_selected][i] then
                        local first_status = task_data.objectives[selected_info.selected_character][task_data.task_selected][i].status
                        local second_status = task_data.objectives[name][second_task_selected][i].status
                        table.insert(obj_info.comparisons, { name = name, first_status = first_status, second_status = second_status })
                    end
                end
            end
            table.insert(progress_info, obj_info)
        end
    end
    return progress_info
end


local function displayGUI()
    if not openGUI then return end
    if not triggers.update_done then
        ImGui.SetNextWindowSize(ImVec2(FIRST_WINDOW_WIDTH, FIRST_WINDOW_HEIGHT), ImGuiCond.FirstUseEver)
        openGUI = ImGui.Begin("Task HUD##" .. my_name, openGUI, window_flags)
        ImGui.Text("Collecting quest data.")
        ImGui.SameLine()
        if ImGui.SmallButton(ICONS.MD_REFRESH) then
            triggers.do_refresh = true
        end
        ImGui.Separator()
        for _, name in pairs(task_data.data_received_from) do
            ImGui.Text("Data received from - %s", name)
        end
        ImGui.End()
    else
        if triggers.do_refresh then
            dannet_connected()
            return
        end
        ImGui.SetNextWindowSize(ImVec2(FIRST_WINDOW_WIDTH, FIRST_WINDOW_HEIGHT), ImGuiCond.FirstUseEver)
        openGUI = ImGui.Begin("Task HUD##" .. my_name, openGUI, window_flags)
        if drawGUI then
            dannet_connected()
            ImGui.PushItemWidth(100)
            selected_info.selected_combo, triggers.changed = ImGui.Combo('##CharacterCombo', selected_info.selected_combo, peer_info.connected_list, #peer_info.connected_list,
                #peer_info.connected_list)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Selected character for tasks')
            end
            ImGui.SameLine()
            peer_info.peer_selected, triggers.do_refresh = ImGui.Combo('##PeerGroupCombo', peer_info.peer_selected, peer_info.peer_groups, #peer_info.peer_groups,
                #peer_info.peer_groups)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Peer group')
            end
            ImGui.PopItemWidth()
            ImGui.SameLine()
            if ImGui.SmallButton(ICONS.MD_REFRESH) then
                triggers.do_refresh = true
            end
            if task_data.tasks[peer_info.connected_list[selected_info.selected_combo]] then
                ImGui.PushItemWidth(220)
                task_data.task_selected = ImGui.Combo('##TaskCombo', task_data.task_selected, task_data.tasks[peer_info.connected_list[selected_info.selected_combo]])
                ImGui.PopItemWidth()
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip('Selected task')
                end
            end
            local missing_list = get_missing_tasks()
            if #missing_list > 0 then
                ImGui.SeparatorText("Mising this task")
                for i, missing in pairs(missing_list) do
                    ImGui.TextColored(IM_COL32(180, 50, 50), string.upper(string.sub(missing, 1, 1)) .. string.sub(missing, 2, -1))
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip('Bring %s to foreground', string.upper(string.sub(missing, 1, 1)) .. string.sub(missing, 2, -1))
                        if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                            mq.cmdf('/dex %s /foreground', missing)
                        end
                    end
                    if i < #missing_list then
                        ImGui.SameLine()
                        ImGui.Text(ICONS.MD_REMOVE)
                        ImGui.SameLine()
                    end
                end
                ImGui.Separator()
            end
            local progress_info = get_objective_progress(missing_list)
            if ImGui.BeginTable('##ObjectivesTable', 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)) then
                for _, obj_info in pairs(progress_info) do
                    ImGui.TableNextColumn()
                    ImGui.Text(obj_info.objective)
                    ImGui.TableNextColumn()
                    if obj_info.status == 'Done' then
                        ImGui.TextColored(IM_COL32(0, 255, 0, 255), obj_info.status)
                    else
                        ImGui.Text(obj_info.status)
                    end
                    ImGui.TableNextColumn()
                    for _, comparison in pairs(obj_info.comparisons) do
                        local name = comparison.name
                        local first_status = comparison.first_status
                        local second_status = comparison.second_status
                        if first_status ~= second_status then
                            local color = first_status == 'Done' and IM_COL32(50, 180, 50) or IM_COL32(180, 50, 50)
                            ImGui.TextColored(color, string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip('Bring %s to foreground', string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                    mq.cmdf('/dex %s /foreground', name)
                                end
                            end
                            ImGui.SameLine()
                        end
                    end
                    ImGui.TableNextRow()
                end
                ImGui.EndTable()
            end
        end
        ImGui.End()
    end
end

--Initialization function. Gets list of connected peers and triggers a refresh
local function init()
    dannet_connected()
    for i, name in pairs(peer_info.connected_list) do
        if name == my_name then selected_info.selected_combo = i end
    end
    mq.delay(500)
    triggers.do_refresh = true
    openGUI = true
end

--Handling for the /th command
local cmd_th = function(cmd)
    if cmd == nil or cmd == 'help' then
        printf("%s \ar/th exit \ao--- Exit script (Also \ar/th stop \aoand \ar/th quit)", taskheader)
        printf("%s \ar/th show \ao--- Show UI", taskheader)
        printf("%s \ar/th hide \ao--- Hide UI", taskheader)
        printf("%s \ar/th debug \ao--- Toggle debug mode", taskheader)
    end
    if cmd == 'exit' or cmd == 'quit' or cmd == 'stop' then
        mq.cmd('/dgae /lua stop taskhud')
        running = false
    end
    if cmd == 'show' then
        printf("%s \aoShowing UI.", taskheader)
        init()
        openGUI = true
    end
    if cmd == 'hide' then
        printf("%s \aoHiding UI.", taskheader)
        openGUI = false
    end
    if cmd == 'debug' then
        printf("%s \aoToggling debug mode %s.", taskheader, debug_mode and "off" or "on")
        debug_mode = not debug_mode
    end
end


--[[
    The main function loop
    Loops while running is true
    Checks trigger variables to see if an action is required
]]
local function main()
    mq.delay(500)
    while running == true do
        mq.delay(200)
        --Request a refresh of task and objective data
        if triggers.do_refresh == true then
            triggers.update_done = false
            request_task_update()
        end
        --A refresh was requested, send character data
        if triggers.do_update_tasks == true then
            send_character()
        end
        --Character info received send task/objectie info
        if triggers.character_message_received == true then
            update_tasks()
        end
        if #peer_info.connected_list == #task_data.data_received_from then
            triggers.update_done = true
        end
        --TODO Add something to check if all peer updates have been received and set triggers.update_done to true if so
    end
    --TODO Should we shut down the clients with a message via actors instead? It would be a cleaner way to do it
    mq.cmd("/dgae /lua stop taskhud")
end

mq.bind('/th', cmd_th)
printf("%s \agstarting. use \ar/th help \agfor a list of commands.", taskheader)
mq.imgui.init('displayGUI', displayGUI)

if #arg == 0 then
    mq.cmd('/dge /lua run taskhud nohud')
    init()
    mq.delay(200)
    main()
    --if runtime arguement of 'nohud' do not initialize or draw gui, start main() loop
elseif arg[1]:lower() == 'nohud' then
    main()
elseif arg[1]:lower() == 'debug' then
    debug_mode = true
end
