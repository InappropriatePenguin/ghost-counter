---Gets or makes playerdata table
---@param player_index number LuaPlayer index
---@return table playerdata playerdata table
function get_make_playerdata(player_index)
    local playerdata = global.playerdata[player_index]

    if not playerdata then
        playerdata = {
            luaplayer=game.players[player_index],
            index=player_index,
            is_active=false,
            job={},
            logistic_requests={},
            gui={},
            options={}
        }
        global.playerdata[player_index] = playerdata
    end

    return playerdata
end

---Returns an empty request table with the given item/tile name and type
---@param name string Item or tile name
---@param type string "item"|"tile"
---@return table request
function make_empty_request(name, type)
    return {name=name, type=type, count=0, inventory=0, logistic_request={}}
end

---Sorts a `requests` table by count, in descending order
---@param requests table `requests` table
---@return table requests_sorted
function sort_requests(requests)
    local requests_sorted = {}
    for _, request in pairs(requests) do table.insert(requests_sorted, request) end

    table.sort(requests_sorted, function(a, b)
        if a.count > b.count then
            return true
        elseif a.count < b.count then
            return false
        elseif a.name < b.name then
            return true
        else
            return false
        end
    end)

    return requests_sorted
end

---Iterates over passed entities and counts ghost entities and tiles
---@param entities table table of entities
---@param ignore_tiles boolean Determines whether ghost tiles are counted
---@return table ghosts table of actual ghost entities/tiles
---@return table requests table of requests, indexed by request name
function get_required_counts(entities, ignore_tiles)
    local ghosts, requests = {}, {}
    local cache = {}

    -- Iterate over entities and filter out anything that's not a ghost
    for _, entity in pairs(entities) do
        if entity.type == "entity-ghost" then
            -- Get item to place entity, from prototype if necessary
            if not cache[entity.ghost_name] then
                local prototype = game.entity_prototypes[entity.ghost_name]
                cache[entity.ghost_name] = {
                    item=prototype.items_to_place_this and prototype.items_to_place_this[1] or nil
                }
            end

            ghosts[entity.unit_number] = {}

            -- If entity is associated with item, increment request for that item by `item.count`
            local item = cache[entity.ghost_name].item
            if item then
                requests[item.name] = requests[item.name] or make_empty_request(item.name, "item")
                requests[item.name].count = requests[item.name].count + item.count
                table.insert(ghosts[entity.unit_number], item)
            end

            -- If entity has module requests, increment request for each module type
            if entity.item_requests and table_size(entity.item_requests) > 0 then
                for name, val in pairs(entity.item_requests) do
                    requests[name] = requests[name] or make_empty_request(name, "item")
                    requests[name].count = requests[name].count + val
                    table.insert(ghosts[entity.unit_number], {name=name, count=val})
                end
            end
            script.register_on_entity_destroyed(entity)
        elseif entity.type == "tile-ghost" and not ignore_tiles then
            requests[entity.ghost_name] = requests[entity.ghost_name] or
                                              make_empty_request(entity.ghost_name, "tile")
            requests[entity.ghost_name].count = requests[entity.ghost_name].count + 1
            ghosts[entity.unit_number] = {{name=entity.ghost_name, count=1}}
            script.register_on_entity_destroyed(entity)
        end
    end

    return ghosts, requests
end

---Deletes requests with zero ghosts from the `job.requests` table
---@param player_index number Player index
function remove_empty_requests(player_index)
    local playerdata = get_make_playerdata(player_index)
    for name, request in pairs(playerdata.job.requests) do
        if request.count <= 0 then playerdata.job.requests[name] = nil end
    end
end

---Updates `job.requests` with inventory and cursor stack contents
---@param player_index number Player index
function update_inventory_info(player_index)
    local playerdata = get_make_playerdata(player_index)
    local inventory = playerdata.luaplayer.get_main_inventory()
    local cursor_stack = playerdata.luaplayer.cursor_stack

    -- Iterate over each request and get the count in inventory and cursor stack
    for name, request in pairs(playerdata.job.requests) do
        request.inventory = inventory.get_item_count(name)
        if cursor_stack and cursor_stack.valid_for_read and cursor_stack.name == name then
            request.inventory = request.inventory + cursor_stack.count
        end
    end
end

---Updates the `job.requests` table with the player's current logistic requests
---@param player_index number Player index
function update_logistics_info(player_index)
    local playerdata = get_make_playerdata(player_index)
    local requests = playerdata.job.requests

    -- Get player character
    local character = playerdata.luaplayer.character
    if not character then return end

    -- Iterate over each logistic slot and update request table with logistic request details
    local logistic_requests = {}
    local slot_count = character.request_slot_count
    for i = 1, slot_count do
        local slot = playerdata.luaplayer.get_personal_logistic_slot(i)
        if requests[slot.name] then
            requests[slot.name].logistic_request = {slot_index=i, min=slot.min, max=slot.max}
            logistic_requests[slot.name] = true
        end
    end

    -- Clear the `logistic_request` table of the request if one was not found
    for _, request in pairs(playerdata.job.requests) do
        if not logistic_requests[request.name] then request.logistic_request = {} end
    end
end

---Iterates over one-time requests table and restores old requests if they have been fulfilled
---@param player_index number Player index
function update_one_time_logistic_requests(player_index)
    local playerdata = get_make_playerdata(player_index)
    local inventory = playerdata.luaplayer.get_main_inventory()
    if not inventory then return end

    -- Iterate over one-time requests table and restore old requests if they have been fulfilled
    for name, logi_req in pairs(playerdata.logistic_requests) do
        local request = playerdata.job.requests[name]
        local slot = playerdata.luaplayer.get_personal_logistic_slot(logi_req.slot_index)

        -- If no matching request exists, restore prior logistic request
        if not request then
            restore_prior_logistic_request(player_index, name)
            return
        end

        -- Update logistic request to reflect new ghost count
        if slot.min > request.count then
            local new_slot = {name=name, min=request.count}
            logi_req.new_min = request.count
            logi_req.is_new = true
            playerdata.luaplayer.set_personal_logistic_slot(logi_req.slot_index, new_slot)
        end

        -- Restore prior request (if any) if one-time request has been fulfilled
        if (inventory.get_item_count(name) >= logi_req.new_min) or
            (logi_req.new_min <= (logi_req.old_min or 0)) then
            restore_prior_logistic_request(player_index, name)
        end
    end
end

---Iterates over player's logistic slots and returns the first empty slot
---@param player_index number Player index
---@return number slot_index First empty slot
function get_first_empty_slot(player_index)
    local playerdata = get_make_playerdata(player_index)
    local character = playerdata.luaplayer.character
    if not character then return end

    for slot_index = 1, character.request_slot_count + 1 do
        local slot = playerdata.luaplayer.get_personal_logistic_slot(slot_index)
        if slot.name == nil then return slot_index end
    end
end

---Gets a table with details of any existing logistic request for a given item or tile
---@param player_index number Player index
---@param name string Item or tile name
---@return table|nil logistic_request
function get_existing_logistic_request(player_index, name)
    local playerdata = get_make_playerdata(player_index)
    local character = playerdata.luaplayer.character
    if not character then return nil end

    for i = 1, character.request_slot_count do
        local slot = playerdata.luaplayer.get_personal_logistic_slot(i)
        if slot and slot.name == name then
            return {slot_index=i, name=slot.name, min=slot.min, max=slot.max}
        end
    end
end

---Generates a logistic request or modifies an existing request to satisfy need. Registers the
---change in a `playerdata.logistic_requests` table so that it can be reverted later on.
---@param player_index number Player index
---@param name string `request` name
function make_one_time_logistic_request(player_index, name)
    -- Abort if no player character
    local playerdata = get_make_playerdata(player_index)
    if not playerdata.luaplayer.character then return end

    --  Abort if player already has more of item/tile in inventory than needed
    local request = playerdata.job.requests[name]
    if not request or request.inventory >= request.count then return end

    -- Get any existing request and abort if it would already meet need
    local existing_request = get_existing_logistic_request(player_index, request.name) or {}
    if (existing_request.min or 0) > request.count then
        register_update(player_index, game.tick)
        return
    end

    -- Prepare new logistic slot and get existing or first empty `slot_index`
    local new_slot = {name=request.name, min=request.count}
    local slot_index = existing_request.slot_index or get_first_empty_slot(player_index)

    -- Save details of change in playerdata so that it can be reverted later
    playerdata.logistic_requests[request.name] = {
        slot_index=slot_index,
        old_min=existing_request.min,
        old_max=existing_request.max,
        new_min=request.count,
        is_new=true
    }

    -- Update request's `logistic_request` table
    request.logistic_request.slot_index = slot_index
    request.logistic_request.min = request.count
    request.logistic_request.max = nil

    -- Actually modify personal logistic slot
    local is_successful = playerdata.luaplayer.set_personal_logistic_slot(slot_index, new_slot)
    playerdata.has_updates = true
    register_update(player_index, game.tick)

    -- Delete one-time logistic request reference if it wasn't successfully set
    if not is_successful then playerdata.logistic_requests[request.name] = nil end
end

---Restores the prior logistic request (if any) that was in place before the one-time request was
---made
---@param player_index number Player index
---@param name string Item or tile name
function restore_prior_logistic_request(player_index, name)
    local playerdata = get_make_playerdata(player_index)
    if not playerdata.luaplayer.character then return end

    local request = playerdata.logistic_requests[name]
    local slot

    -- Either clear or reset slot using old request values
    if request.old_min or request.old_max then
        slot = {name=name, min=request.old_min, max=request.old_max}
        playerdata.luaplayer.set_personal_logistic_slot(request.slot_index, slot)
    else
        playerdata.luaplayer.clear_personal_logistic_slot(request.slot_index)
    end

    if playerdata.job.requests[name] then
        if slot then
            playerdata.job.requests[name].logistic_request = {
                slot_index=request.slot_index,
                min=slot.min,
                max=slot.max
            }
        else
            playerdata.job.requests[name].logistic_request = {}
        end
    end

    -- Delete one-time request from playerdata table
    playerdata.logistic_requests[name] = nil
end

---Registers that a change in data tables has occured and marks the responsible player as having
---data updates to process
---@param player_index number Player index
---@param tick number Tick during which the data update occurred
function register_update(player_index, tick)
    local playerdata = get_make_playerdata(player_index)

    -- Mark player as having a data update, in order for it to get reprocessed
    playerdata.has_updates = true

    -- Record the tick in which the update was registered
    global.last_event = tick

    -- Register nth_tick handler if needed
    register_nth_tick_handler(true)
end

---Registers/unregisters on_nth tick event handler
---@param state any
function register_nth_tick_handler(state)
    if state and not global.events.nth_tick then
        global.events.nth_tick = true
        script.on_nth_tick(global.settings.min_update_interval, on_nth_tick)
    elseif state == false and global.events.nth_tick then
        global.events.nth_tick = false
        script.on_nth_tick(nil)
    end
end

---Registers/unregisters event handlers for inventory or player cursor stack changes
---@param state boolean Determines whether to register or unregister event handlers
function register_inventory_monitoring(state)
    if state and not global.events.inventory then
        global.events.inventory = true

        script.on_event(defines.events.on_player_main_inventory_changed,
            on_player_main_inventory_changed)
        script.on_event(defines.events.on_player_cursor_stack_changed,
            on_player_main_inventory_changed)
        script.on_event(defines.events.on_entity_destroyed, on_ghost_destroyed)
    elseif state == false and global.events.inventory then
        global.events.inventory = false

        script.on_event(defines.events.on_player_main_inventory_changed, nil)
        script.on_event(defines.events.on_player_cursor_stack_changed, nil)
        script.on_event(defines.events.on_entity_destroyed, nil)
    end
end

---Registers/unregisters event handlers for player logistic slot changes
---@param state boolean Determines whether to register or unregister event handlers
function register_logistics_monitoring(state)
    if state and not global.events.logistics then
        global.events.logistics = true
        script.on_event(defines.events.on_entity_logistic_slot_changed,
            on_entity_logistic_slot_changed)
    elseif state == false and global.events.logistics then
        global.events.logistics = false
        script.on_event(defines.events.on_entity_logistic_slot_changed, nil)
    end
end

---Iterates over global playerdata table and determines whether any connected players have their
---mod GUI open.
---@return boolean
function is_inventory_monitoring_needed()
    for _, playerdata in pairs(global.playerdata) do
        if playerdata.is_active and playerdata.luaplayer.connected then return true end
    end
    return false
end

---Iterates over the global playerdata table and checks to see if any one-time logistic requests
---are still unfulfilled.
---@return boolean
function is_logistics_monitoring_needed()
    for _, playerdata in pairs(global.playerdata) do
        if (playerdata.is_active or table_size(playerdata.logistic_requests) > 0) and
            playerdata.luaplayer.connected then return true end
    end
    return false
end
