--[[
    Create a window where you can compare the progress of tasks vs other dannet connected clients

]]

local mq = require('mq')
local ImGui = require 'ImGui'
local actors = require 'actors'
local ICONS = require('mq.Icons')

--Variables for drawing of the GUI
local openGUI, drawGUI = true, true

--Variable for main loop, run until false
local running = true

--List of collected characters and selection from that list
local connected_list = {}
local combo_selected = 1

--Window flags for GUI window, currently useless but easier this way if I
local window_flags = bit32.bor(ImGuiWindowFlags.None)

--Name variable because it's shorter
local myName = mq.TLO.Me.DisplayName()

--Table of peer groups and which is selected, and how many peers are in selected group
local peer_groups = { "Group", "Zone", "All" }
local peer_selected = 1
local peers_count = 1
local peer_group = ''

--Tables for tasks and objectives and variable for which task is selected in the task dropdown
local tasks = {}
local objectives = {}
local task_selected = 1

--Variables that will trigger functions to run if true
local changed = false
local do_refresh = false
local do_update_tasks = false

--Variable for who is requesting the updates.  No need to process updates on characters that are not displaying the gui.
local requester = ''

--Arguements received running the script.
local arg = { ... }

--variable to determine if game UI has been updated yet while scraping task data.
local list_item = 0

--Name of selected task and character to maintain same task name when switching characters
local task_selected_name = ''
local selected_character = ''

--Variables to determine if update process has completed various steps and to determine if GUI should be drawn
local num_updates_finished = 0
local update_done = false
local character_message_received = false

--Header for chat output
local taskheader = "\ay[\agTaskHud\ay]"

--Insure DanNet is loaded.  Exit if it is not.
if mq.TLO.Plugin('mq2dannet').IsLoaded() == false then
    printf("%s \aoDanNet is required for this plugin.  \arExiting", taskheader)
    mq.exit()
end

--Obtain list of connected dannet peers
local function dannet_connected()
    connected_list = {}
    --If peer group "Group"
    if peer_selected == 1 then
        if mq.TLO.EverQuest.Server() ~= nil and mq.TLO.Group.Leader() ~= nil then
            peer_group = "group_" .. mq.TLO.EverQuest.Server() .. "_" .. string.lower(mq.TLO.Group.Leader())
        end
        --if peer group "Zone"
    elseif peer_selected == 2 then
        if mq.TLO.EverQuest.Server() ~= nil and mq.TLO.Zone.ShortName() ~= nil then
            peer_group = "zone_" .. mq.TLO.EverQuest.Server() .. "_" .. mq.TLO.Zone.ShortName()
        end
        --If peer group "All"
    elseif peer_selected == 3 then
        peer_group = 'all'
    end
    local peers_list = mq.TLO.DanNet.Peers(peer_group)()
    for word in string.gmatch(peers_list, '([^|]+)') do
        table.insert(connected_list, word)
    end
    peers_count = mq.TLO.DanNet.PeerCount(peer_group)()
end

--Returns true if Task Window is open to end Delay() early
local function task_window_open()
    return mq.TLO.Window('TaskWnd').Open()
end

--Check which item is selected in the Task List, return true to end Delay() early
local function get_selection_num()
    if mq.TLO.Window('TaskWnd').Child('TASK_TaskList').GetCurSel() == list_item then
        return true
    end
    return false
end

--Send character information, first thing triggered in the refresh process.
--Sends information to the character requesting updates to populate list of characters in the task and objectives tables.
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

--Send task and objective information to requsting client
local function update_tasks()
    --Open the task window, wait 2s for it to open, end Delay() early if window is open
    mq.cmd("/windowstate TaskWnd open")
    mq.delay("2s", task_window_open)
    --Counter variables to allow skipping over seperator lines
    local count = 1
    local count_two = 1
    --Loop through all items in the Task Window's Task List, select each item and send it to requesting client as a new task
    for i = 1, mq.TLO.Window('TaskWnd').Child('TASK_TaskList').Items() do
        mq.cmdf('/notify TaskWnd TASK_TaskList listselect %s', i)
        list_item = i
        mq.delay(200, get_selection_num)
        --If the name of the task is not nil (as is the case in seperator lines)
        if mq.TLO.Window('TaskWnd').Child('TASK_TaskList').List(i, 3)() ~= nil then
            --send NEW_TASK message to requester.  information on # in list as well as name
            actors:send(
                {
                    script = 'taskhud',
                    id = 'NEW_TASK',
                    recepient = requester,
                    sender = string.lower(mq.TLO.Me.DisplayName()),
                    taskID = count,
                    name = mq.TLO.Window('TaskWnd').Child('TASK_TaskList').List(i, 3)()
                })
            --Loop through all items in the Task Window's Task Objectives.
            for j = 1, mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').Items() do
                --If the status of the objective is not nil (as is the case in seperator lines)
                if mq.TLO.Window('TaskWnd').Child('TASK_TaskElementList').List(j, 2)() ~= nil then
                    --send TASK_OBJECTIVE message to requester.  information on task #, objective text, objective #, and status
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
                    --increment the count of objective list items that were not seperators
                    count_two = count_two + 1
                end
            end
            --reset objective counter, increment count of tasks that were not seperators
            count_two = 1
            count = count + 1
        end
    end
    --Send message indicating that all task and objective information has been sent
    actors:send(
        {
            script = 'taskhud',
            id = 'END_TASKS',
            recepient = requester,
            sender = string.lower(mq.TLO.Me.DisplayName())
        })
    --reset variables used for tracking and close the task window
    character_message_received = false
    requester = ''
    mq.cmd("/windowstate TaskWnd close")
end

local msg_received = false

--Handler for incoming messages
local actor = actors.register(function(message)
    --If the message is for a new character, create the necessary elements for that charcter in the tasks and objectives tables
    if message.content.id == 'NEW_CHARACTER' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            tasks[message.content.sender] = {}
            objectives[message.content.sender] = {}
            --Send confirmation that we received the character
            actors:send(
                {
                    script = 'taskhud',
                    id = 'CHARACTER_RECEIVED',
                    recepient = message.content.sender
                })
        end
        --If the message is confirmation of having received the character, set variable for next processing step to true
    elseif message.content.id == 'CHARACTER_RECEIVED' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            character_message_received = true
        end
        --If the message indicates a new task
    elseif message.content.id == 'NEW_TASK' then
        if message.content.recepient == string.lower(mq.TLO.Me.DisplayName()) then
            --add task information to tasks table.
            table.insert(tasks[message.content.sender], message.content.taskID, message.content.name)
            --if this was the task that was selected before updating, set the task to this again (by name)
            if task_selected_name == message.content.name and message.content.sender == connected_list[combo_selected] then
                task_selected = message.content.taskID
            end
            --create task element in objectives[character] table
            objectives[message.content.sender][message.content.taskID] = {}
        end
        --if the message indicates a new task objective
    elseif message.content.id == 'TASK_OBJECTIVE' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            --add the objective and status elements to the objectives[character][task] table
            objectives[message.content.sender][message.content.taskID][message.content.objectiveID] = {
                ['objective'] = message.content.objective,
                ['status'] = message.content.status
            }
        end
        --If the message indicates no further tasks for this character increment variable of number of completed updates
    elseif message.content.id == 'END_TASKS' then
        if string.lower(message.content.recepient) == string.lower(mq.TLO.Me.DisplayName()) then
            num_updates_finished = num_updates_finished + 1
        end
        --If the message is asking for an update on tasks set variable to begin update process
    elseif message.content.id == 'REQUEST_TASKS' then
        for word in string.gmatch(message.content.recepient, '([^|]+)') do
            if word == string.lower(mq.TLO.Me.DisplayName()) then
                requester = message.content.sender
                do_update_tasks = true
                --mq.cmdf("/dgt received update request from %s", requester)
            end
        end
    end
end)

--Send request to clients to update task/objective information
local function request_task_update()
    --Store the name of the currently selected task then clear the tasks and objectives tables
    if tasks[selected_character] ~= nil then
        task_selected_name = tasks[selected_character][task_selected]
    end
    tasks = {}
    objectives = {}
    --Send a message requesting that all clients resend task/objective information
    actor:send({ script = 'taskhud' },
        {
            script = 'taskhud',
            id = 'REQUEST_TASKS',
            recepient = mq.TLO.DanNet.Peers(peer_group)(),
            sender = string.lower(mq.TLO.Me.DisplayName())
        })
    selected_character = connected_list[combo_selected]
    --reset variable that triggers the calling of the request_task_update() function to false
    do_refresh = false
    changed = false
end

--Draw the GUI
local function displayGUI()
    --If the GUI is closed, set running to false and end the script (I dont like this, it is temporary, will be changed)
    if not openGUI then return end
    --If the task/objectives tables are currently being drawn, wait to draw GUI to prevent running into nil values
    if update_done == false then
        return
    end
    --Begin imgui window
    if do_refresh then
        dannet_connected()
        return
    end
    openGUI = ImGui.Begin("Task HUD##" .. myName, openGUI, window_flags)
    if drawGUI then
        dannet_connected()
        ImGui.PushItemWidth(100)
        combo_selected, changed = ImGui.Combo('##CharacterCombo', combo_selected, connected_list, #connected_list,
            #connected_list)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Selected Character for tasks')
        end
        ImGui.PopItemWidth()
        ImGui.SameLine()
        ImGui.PushItemWidth(100)
        peer_selected, do_refresh = ImGui.Combo('##PeerGroupCombo', peer_selected, peer_groups, #peer_groups,
            #peer_groups)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Peer group')
        end
        ImGui.PopItemWidth()
        --Uncomment line below to automatically refresh when choosing new characters in the dropdown list
        ImGui.SameLine()
        if ImGui.SmallButton(ICONS.MD_REFRESH) then
            do_refresh = true
        end
        --combo box of tasks the selected character has
        if tasks[connected_list[combo_selected]] ~= nil then
            ImGui.PushItemWidth(220)
            task_selected = ImGui.Combo('##TaskCombo', task_selected, tasks[connected_list[combo_selected]])
            ImGui.PopItemWidth()
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Selected task')
            end
        end
        --list of characters who are missing the selected task
        local missing_list = {}
        --if the # of tasks the selected character has is > 0 then make sure everyone else has it..
        --There have possibly been crashes related to this section
        --Add a nil check first, that should fix it.
        if tasks[connected_list[combo_selected]] ~= nil then
            if #tasks[connected_list[combo_selected]] ~= nil then
                if #tasks[connected_list[combo_selected]] > 0 then
                    --loop over the character tables in the tasks table
                    for i, name in pairs(tasks) do
                        local matched = false
                        --loop over tasks the character in the current loop has
                        for j, task in pairs(name) do
                            --If it is the same task as the selected character, we matched
                            if task == tasks[connected_list[combo_selected]][task_selected] then
                                matched = true
                            end
                        end
                        --If we didnt find a match on this character, add their name to the list of characters missing this task
                        if matched == false then
                            table.insert(missing_list, i)
                        end
                    end
                    --If any characters are missing this task, draw the small section for displaying their names
                    if #missing_list > 0 then
                        ImGui.SeparatorText("Missing this task")
                        for i, missing in pairs(missing_list) do
                            ImGui.TextColored(IM_COL32(180, 50, 50),
                                string.upper(string.sub(missing, 1, 1)) .. string.sub(missing, 2, -1))
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip('Bring %s to foreground',
                                    string.upper(string.sub(missing, 1, 1)) .. string.sub(missing, 2, -1))
                                if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                    mq.cmdf('/dex %s /foreground', missing)
                                end
                            end
                            if i < #missing_list then
                                ImGui.SameLine()
                                --This is just being used as a seperator.  Gives a nice strong -
                                ImGui.Text(ICONS.MD_REMOVE)
                                ImGui.SameLine()
                            end
                        end
                        ImGui.Separator()
                    end
                end
            end
        end
        --Draw the table for listing objectives and their status
        if ImGui.BeginTable('##ObjectivesTable', 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)) then
            --Make sure the objectives tables are actually populated
            if objectives[connected_list[combo_selected]] ~= nil and objectives[connected_list[combo_selected]][task_selected] ~= nil then
                --Loop over all objectives for the selected character's selected task
                for i = 1, #objectives[connected_list[combo_selected]][task_selected] do
                    ImGui.TableNextColumn()
                    ImGui.Text(objectives[connected_list[combo_selected]][task_selected][i].objective)
                    ImGui.TableNextColumn()
                    --If status is 'Done' set text to green, otherwise default to white
                    if objectives[connected_list[combo_selected]][task_selected][i].status == 'Done' then
                        ImGui.TextColored(IM_COL32(0, 255, 0, 255),
                            objectives[connected_list[combo_selected]][task_selected][i].status)
                    else
                        ImGui.Text(objectives[connected_list[combo_selected]][task_selected][i].status)
                    end
                    ImGui.TableNextColumn()
                    --Loop over all connected characters
                    for index, name in pairs(connected_list) do
                        --variables for comparing task completion
                        local second_task_selected = 0
                        local im_missing = false
                        --Loop over the names of characters missing this task, if they are missing, set im_missing true to ignore this character
                        for j, missing_name in pairs(missing_list) do
                            if name == missing_name then
                                im_missing = true
                            end
                        end
                        --If we are not on the missing list compare objective completion
                        if not im_missing then
                            --make sure the tasks match the same task index, if not, find the correct task id
                            if tasks[connected_list[combo_selected]][task_selected] ~= tasks[name][task_selected] then
                                --Loop over tasks to find task id
                                for k, task_name in pairs(tasks[name]) do
                                    if tasks[connected_list[combo_selected]][task_selected] == task_name then
                                        second_task_selected = k
                                    end
                                end
                                --If they do have the same index, just set to what is selected
                            else
                                second_task_selected = task_selected
                            end
                            --Make sure to nil check...
                            if objectives[connected_list[combo_selected]][task_selected][i] ~= nil and objectives[name][second_task_selected][i] ~= nil then
                                --If the status for the two characters does not match
                                if objectives[connected_list[combo_selected]][task_selected][i].status ~= objectives[name][second_task_selected][i].status then
                                    --store the status for the two characters, and convert first digit of each to numbers for later comparisons
                                    local first_status = objectives[connected_list[combo_selected]][task_selected][i]
                                        .status
                                    local second_status = objectives[name][second_task_selected][i].status
                                    local first_status_digit = tonumber(string.sub(first_status, 1, 1))
                                    local second_status_digit = tonumber(string.sub(second_status, 1, 1))
                                    --If one is done, and the other is not, color appropriately (Green for ahead of me, red behind me)
                                    if first_status ~= 'Done' and second_status == 'Done' then
                                        ImGui.TextColored(IM_COL32(50, 180, 50),
                                            string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip('Bring %s to foreground',
                                                string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                            if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                                mq.cmdf('/dex %s /foreground', name)
                                            end
                                        end
                                        ImGui.SameLine()
                                    elseif first_status == 'Done' and second_status ~= 'Done' then
                                        ImGui.TextColored(IM_COL32(180, 50, 50),
                                            string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip('Bring %s to foreground',
                                                string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                            if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                                mq.cmdf('/dex %s /foreground', name)
                                            end
                                        end
                                        ImGui.SameLine()
                                        --Make sure the digits stored earlier are not nil, then compare first digit to determine
                                        --Which character is further ahead on the task, color name as such
                                    elseif first_status_digit ~= nil and second_status_digit ~= nil then
                                        if tonumber(string.sub(first_status, 1, 1)) > tonumber(string.sub(first_status, 1, 1)) then
                                            ImGui.TextColored(IM_COL32(180, 50, 50),
                                                string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                            if ImGui.IsItemHovered() then
                                                ImGui.SetTooltip('Bring %s to foreground',
                                                    string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                                if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                                    mq.cmdf('/dex %s /foreground', name)
                                                end
                                            end
                                            ImGui.SameLine()
                                        elseif tonumber(string.sub(first_status, 1, 1)) < tonumber(string.sub(first_status, 1, 1)) then
                                            ImGui.TextColored(IM_COL32(50, 180, 50),
                                                string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                            if ImGui.IsItemHovered() then
                                                ImGui.SetTooltip('Bring %s to foreground',
                                                    string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2, -1))
                                                if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                                    mq.cmdf('/dex %s /foreground', name)
                                                end
                                            end
                                            ImGui.SameLine()
                                        end
                                    end
                                end
                            end
                        end
                    end
                    ImGui.TableNextRow()
                end
            end
            ImGui.EndTable()
        end
    end
    ImGui.End()
end

local function init()
    dannet_connected()
    for i, name in pairs(connected_list) do
        if name == string.lower(mq.TLO.Me.DisplayName()) then combo_selected = i end
    end
    mq.delay(500)
    do_refresh = true
end

local cmd_th = function(cmd)
    if cmd == nil or cmd == 'help' then
        printf("%s \ar/th exit \ao--- Exit script (Also \ar/th stop \aoand \ar/th quit)", taskheader)
        printf("%s \ar/th show \ao--- Show UI", taskheader)
        printf("%s \ar/th hide \ao--- Hide UI", taskheader)
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
end

--Main function.  Loop while running is true, check variables to see if function needs called.

local function main()
    mq.delay(500)
    while running == true do
        mq.delay(200)
        --request task/objective refresh
        if do_refresh == true then
            num_updates_finished = 0
            update_done = false
            request_task_update()
        end
        --Refresh requested? Send character info
        if do_update_tasks == true then
            send_character()
        end
        --Character info received? Send task/objective info
        if character_message_received == true then
            update_tasks()
        end
        if num_updates_finished == peers_count then
            update_done = true
        end
    end
    --stop background processes on other peers
    mq.cmd("/dgae /lua stop taskhud")
end

mq.bind('/th', cmd_th)
printf("%s \agstarting. Use \ar/th help \ag for a list of commands.", taskheader)



--initialization function ran on main client.  Tells other peers to run in background.  Get a list of peers and populate
--The connected_list, and then request task/objective information


mq.imgui.init('displayGUI', displayGUI)

--If no runtime arguements, initialize other clients and draw gui then start main() loop
if #arg == 0 then
    mq.cmd('/dge /lua run taskhud nohud')
    init()
    mq.delay(200)
    main()
    --if runtime arguement of 'nohud' do not initialize or draw gui, start main() loop
elseif arg[1]:lower() == 'nohud' then
    main()
end
