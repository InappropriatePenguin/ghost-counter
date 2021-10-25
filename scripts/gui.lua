Gui = {}

---Toggles mod GUI on or off
---@param player_index number Player index
---@param state boolean true -> on, false -> off
function Gui.toggle(player_index, state)
    local playerdata = get_make_playerdata(player_index)
    state = state or not playerdata.is_active

    if state then
        playerdata.is_active = true

        -- Create mod gui and register event handler
        Gui.make_gui(player_index)
        register_inventory_monitoring(true)
        register_logistic_slot_monitoring(true)
    else
        playerdata.is_active = false
        playerdata.job = nil

        -- Destroy mod GUI and remove references to it
        if playerdata.gui.root and playerdata.gui.root.valid then
            playerdata.gui.root.destroy()
            playerdata.gui = {}
        end

        -- Unbind event hook if no player has GC open
        if not is_any_player_active() then register_inventory_monitoring(false) end
    end
end

---Make mod GUI
---@param player_index number Player index
function Gui.make_gui(player_index)
    local playerdata = get_make_playerdata(player_index)
    local screen = playerdata.luaplayer.gui.screen

    -- Destory existing mod GUI if one exists
    if screen[NAME.gui.root_frame] then screen[NAME.gui.root_frame].destroy() end

    playerdata.gui.root = screen.add{
        type="frame",
        name=NAME.gui.root_frame,
        direction="vertical",
        style=NAME.style.root_frame
    }

    do
        local resolution = playerdata.luaplayer.display_resolution
        local x = 50
        local y = resolution.height / 2 - 300
        playerdata.gui.root.location = {x, y}
    end

    -- Create title bar
    local titlebar_flow = playerdata.gui.root.add{type="flow", direction="horizontal"}
    titlebar_flow.drag_target = playerdata.gui.root
    titlebar_flow.add{
        type="label",
        caption="Ghost Counter",
        ignored_by_interaction=true,
        style="frame_title"
    }
    titlebar_flow.add{
        type="empty-widget",
        ignored_by_interaction=true,
        style=NAME.style.titlebar_space_header
    }
    titlebar_flow.add{
        type="sprite-button",
        name=NAME.gui.close_button,
        sprite="utility/close_white",
        hovered_sprite="utility/close_black",
        style="close_button"
    }

    local deep_frame = playerdata.gui.root.add{type="frame", style=NAME.style.inside_deep_frame}
    playerdata.gui.requests_container = deep_frame.add{
        type="scroll-pane",
        name=NAME.gui.scroll_pane,
        style=NAME.style.scroll_pane
    }

    Gui.make_list(player_index)
end

---Creates/re-creates the list of request frames in the GUI
---@param player_index number Player index
function Gui.make_list(player_index)
    local playerdata = get_make_playerdata(player_index)
    local parent = playerdata.gui.requests_container
    local requests = playerdata.job.requests_sorted

    playerdata.gui.requests = {}

    -- Destroy any child elements in parent scroll pane
    if parent then parent.clear() end

    -- Create a new row frame for each request
    for _, request in pairs(requests) do Gui.make_row(player_index, request) end
end

---Generates the row frame for a given request table
---@param player_index number Player index
---@param request table `request` table, containing name, count, inventory, etc.
function Gui.make_row(player_index, request)
    local playerdata = get_make_playerdata(player_index)
    local parent = playerdata.gui.requests_container

    local prototype
    if request.type == "item" then
        prototype = game.item_prototypes[request.name]
    elseif request.type == "tile" then
        prototype = game.tile_prototypes[request.name]
    end

    -- Row frame
    local frame = parent.add{type="frame", direction="horizontal", style=NAME.style.row_frame}
    playerdata.gui.requests[request.name] = frame

    -- Ghost count
    frame.add{type="label", caption=request.count, style=NAME.style.ghost_number_label}

    -- Entity or tile sprite
    frame.add{
        type="sprite",
        sprite=request.type .. "/" .. request.name,
        resize_to_sprite=false,
        style=NAME.style.ghost_sprite
    }

    -- Item or tile localized name
    frame.add{type="label", caption=prototype.localised_name, style=NAME.style.ghost_name_label}

    -- Amount in inventory
    frame.add{type="label", caption=request.inventory, style=NAME.style.inventory_number_label}

    -- One-time request button or request fulfilled flow/sprite
    local diff = request.count - request.inventory
    if diff > 0 then
        local logistic_request = request.logistic_request or {}
        local enabled = ((logistic_request.min or 0) < request.count) or
                            playerdata.logistic_requests[request.name] and true or false
        local style = ((logistic_request.min or 0) < request.count) and
                          NAME.style.ghost_request_button or NAME.style.ghost_request_active_button
        frame.add{
            type="button",
            caption=diff,
            enabled=enabled,
            style=style,
            tags={ghost_counter_request=request}
        }
    else
        local sprite_container = frame.add{
            type="flow",
            direction="horizontal",
            style=NAME.style.ghost_request_fulfilled_flow
        }
        sprite_container.add{
            type="sprite",
            sprite="utility/check_mark_white",
            resize_to_sprite=false,
            style=NAME.style.ghost_request_fulfilled_sprite
        }
    end
end

---Event handler for GUI button clicks
---@param event table Event table
function Gui.on_gui_click(event)
    -- Close button
    if event.element.name == NAME.gui.close_button then
        Gui.toggle(event.player_index, false)
        -- One-time logistic request button
    elseif event.element.tags and event.element.tags.ghost_counter_request then
        local playerdata = get_make_playerdata(event.player_index)
        local request = event.element.tags.ghost_counter_request
        if not playerdata.logistic_requests[request.name] then
            make_one_time_logistic_request(event.player_index,
                event.element.tags.ghost_counter_request)
        else
            restore_prior_logistic_request(event.player_index, request.name)
        end
    end
end
script.on_event(defines.events.on_gui_click, Gui.on_gui_click)
