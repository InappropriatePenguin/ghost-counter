---Gets or makes playerdata table
---@param player_index number LuaPlayer index
---@return table playerdata playerdata table
function get_make_playerdata(player_index)
    local playerdata = global.playerdata[player_index]

    if not playerdata then
        playerdata = {
            luaplayer=game.players[player_index],
            is_active=false,
            job={},
            logistic_requests={},
            gui={}
        }
        global.playerdata[player_index] = playerdata
    end

    return playerdata
end

---Iterates over passed entities and counts ghost entities and tiles
---@param entities table table of entities
---@return table ghosts table of actual ghost entities/tiles
---@return table requests table of requests, indexed by request name
---@return table requests_sorted array of requests, sorted by count in descending order
function get_required_counts(entities)
    local ghosts, requests, requests_sorted = {}, {}, {}

    -- Iterate over entities and filter out anything that's not a ghost
    for _, entity in pairs(entities) do
        if entity.type == "entity-ghost" then
            ghosts[entity.ghost_name] = ghosts[entity.ghost_name] or
                                            {name=entity.ghost_name, type="entity", count=0}
            ghosts[entity.ghost_name].count = ghosts[entity.ghost_name].count + 1

            if entity.item_requests and table_size(entity.item_requests) > 0 then
                for name, val in pairs(entity.item_requests) do
                    ghosts[name] = ghosts[name] or {name=name, type="item", count=0}
                    ghosts[name].count = ghosts[name].count + val
                end
            end
        elseif entity.type == "tile-ghost" then
            ghosts[entity.ghost_name] = ghosts[entity.ghost_name] or
                                            {name=entity.ghost_name, type="tile", count=0}
            ghosts[entity.ghost_name].count = ghosts[entity.ghost_name].count + 1
        end
    end

    -- Generate requests table
    for _, ghost in pairs(ghosts) do
        if ghost.type == "entity" then
            local prototype = game.entity_prototypes[ghost.name]
            local item = prototype.items_to_place_this and prototype.items_to_place_this[1] or nil
            if item then
                requests[item.name] = requests[item.name] or
                                          {
                        name=item.name,
                        type="item",
                        count=0,
                        logistic_request={}
                    }
                requests[item.name].count = requests[item.name].count + (ghost.count * item.count)
            end
        else
            requests[ghost.name] = ghost
        end
    end

    -- Sort requests table
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

    return ghosts, requests, requests_sorted
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
    for name, request in pairs(playerdata.logistic_requests) do
        if inventory.get_item_count(name) >= request.new_min then
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
---@param request table `request` table
function make_one_time_logistic_request(player_index, request)
    --  Abort if player already has more of item/tile in inventory than needed
    if request.inventory >= request.count then return end

    -- Abort if no player character
    local playerdata = get_make_playerdata(player_index)
    if not playerdata.luaplayer.character then return end

    -- Get any existing request and abort if it would already meet need
    local existing_request = get_existing_logistic_request(player_index, request.name) or {}
    if (existing_request.min or 0) > request.count then return end

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

    -- Actually modify personal logistic slot
    playerdata.luaplayer.set_personal_logistic_slot(slot_index, new_slot)
end

---Restores the prior logistic request (if any) that was in place before the one-time request was
---made
---@param player_index number Player index
---@param name string Item or tile name
function restore_prior_logistic_request(player_index, name)
    local playerdata = get_make_playerdata(player_index)
    if not playerdata.luaplayer.character then return end

    local request = playerdata.logistic_requests[name]

    -- Either clear or reset slot using old request values
    if request.old_min or request.old_max then
        local slot = {name=name, min=request.old_min, max=request.old_max}
        playerdata.luaplayer.set_personal_logistic_slot(request.slot_index, slot)
    else
        playerdata.luaplayer.clear_personal_logistic_slot(request.slot_index)
    end

    -- Delete one-time request from playerdata table
    playerdata.logistic_requests[name] = nil
end

---Iterates over global playerdata table and determines whether any connected players have their
---mod GUI open.
---@return boolean
function is_any_player_active()
    for _, playerdata in pairs(global.playerdata) do
        if playerdata.is_active and playerdata.luaplayer.connected then return true end
    end

    return false
end

---Iterates over the global playerdata table and checks to see if any one-time logistic requests
---are still unfulfilled.
---@return boolean
function is_any_player_waiting()
    for _, playerdata in pairs(global.playerdata) do
        if playerdata.luaplayer.connected and table_size(playerdata.logistic_requests) > 0 then
            return true
        end
    end
    return false
end
