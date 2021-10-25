require("scripts/constants")
require("scripts/core")
require("scripts/gui")

---Create playerdata table
function on_init() global.playerdata = {} end
script.on_init(on_init)

---Re-registers event handlers if appropriate for joining player
---@param event table Event table
function on_player_joined_game(event)
    local playerdata = get_make_playerdata(event.player_index)

    if playerdata.is_active then register_inventory_monitoring(true) end
    if playerdata.is_active or table_size(playerdata.logistic_requests) > 0 then
        register_logistic_slot_monitoring(true)
    end
end
script.on_event(defines.events.on_player_joined_game, on_player_joined_game)

---Re-evaluates whether event handlers should continue to be bound
---@param event table Event able
function on_player_left_game(event)
    if not is_any_player_active() then
        register_inventory_monitoring(false)
    end
    if not is_any_player_waiting() then
        register_logistic_slot_monitoring(false)
    end
end
script.on_event(defines.events.on_player_left_game, on_player_left_game)

---Deletes playerdata table associated with removed player
---@param event table Event table
function on_player_removed(event) global.playerdata[event.player_index] = nil end
script.on_event(defines.events.on_player_removed, on_player_removed)

---Event handler for selection using GC tool
---@param event table Event table
function on_player_selected_area(event)
    if not event.item == NAME.tool.ghost_counter then return end

    local ghosts, requests, requests_sorted = get_required_counts(event.entities)

    -- Open window only if there are non-zero ghost entities
    if table_size(requests_sorted) > 0 then
        local playerdata = get_make_playerdata(event.player_index)
        if playerdata.is_active then Gui.toggle(event.player_index, false) end

        playerdata.job = {
            area=event.area,
            entities=ghosts,
            requests=requests,
            requests_sorted=requests_sorted
        }
        update_inventory_info(event.player_index)
        update_logistics_info(event.player_index)

        Gui.toggle(event.player_index, true)

        playerdata.luaplayer.clear_cursor()
    end
end
script.on_event(defines.events.on_player_selected_area, on_player_selected_area)
script.on_event(defines.events.on_player_alt_selected_area, on_player_selected_area)

---Updates playerdata.job.requests table as well as one-time requests to see if any can be
---considered fulfilled
---@param event table
function on_player_main_inventory_changed(event)
    local playerdata = get_make_playerdata(event.player_index)
    if not playerdata.is_active then return end

    update_inventory_info(event.player_index)
    update_one_time_logistic_requests(event.player_index)
    Gui.make_list(event.player_index)
end

---Updates one-time logistic requests table as well as job.requests
---@param event table Event table
function on_entity_logistic_slot_changed(event)
    -- Exit if event does not involve a player character
    if event.entity.type ~= "character" then return end

    local player_index = event.entity.player.index
    local playerdata = get_make_playerdata(player_index)

    -- Iterate over known one-time logistic requests to see if the event concerns any of them
    for name, request in pairs(playerdata.logistic_requests) do
        if request.slot_index == event.slot_index then
            if request.is_new then
                request.is_new = false
            else
                playerdata.logistic_requests[name] = nil
            end
            break
        end
    end

    if playerdata.is_active then
        local slot = playerdata.luaplayer.get_personal_logistic_slot(event.slot_index)

        -- If slot contents are relevant to one of the requests, update the logistic request values
        if playerdata.job.requests[slot.name] then
            playerdata.job.requests[slot.name].logistic_request.slot_index = event.slot_index
            playerdata.job.requests[slot.name].logistic_request.min = slot.min
            playerdata.job.requests[slot.name].logistic_request.slot_index = slot.max
        else
            update_logistics_info(player_index)
        end

        -- Refresh list of requests so that request buttons can be updated
        Gui.make_list(player_index)
    end

    -- Check if event handler can be unbound
    if not is_any_player_active() and not is_any_player_waiting() then
        register_logistic_slot_monitoring(false)
    end
end

---Registers/unregisters event handlers for inventory or player cursor stack changes
---@param state boolean Determines whether to register or unregister event handlers
function register_inventory_monitoring(state)
    if state then
        script.on_event(defines.events.on_player_main_inventory_changed,
            on_player_main_inventory_changed)
        script.on_event(defines.events.on_player_cursor_stack_changed,
            on_player_main_inventory_changed)
    else
        script.on_event(defines.events.on_player_main_inventory_changed, nil)
        script.on_event(defines.events.on_player_cursor_stack_changed, nil)
    end
end

---Registers/unregisters event handlers for player logistic slot changes
---@param state boolean Determines whether to register or unregister event handlers
function register_logistic_slot_monitoring(state)
    if state then
        script.on_event(defines.events.on_entity_logistic_slot_changed,
            on_entity_logistic_slot_changed)
    else
        script.on_event(defines.events.on_entity_logistic_slot_changed, nil)
    end
end
