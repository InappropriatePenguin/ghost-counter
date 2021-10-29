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
        register_logistics_monitoring(true)
    else
        playerdata.is_active = false
        playerdata.job = nil

        -- Destroy mod GUI and remove references to it
        if playerdata.gui.root and playerdata.gui.root.valid then
            playerdata.gui.root.destroy()
            playerdata.gui = {}
        end

        -- Unbind event hooks if no no longer needed
        if not is_inventory_monitoring_needed() then register_inventory_monitoring(false) end
        if not is_logistics_monitoring_needed() then register_logistics_monitoring(false) end
    end
end

---Make mod GUI
---@param player_index number Player index
function Gui.make_gui(player_index)
    local playerdata = get_make_playerdata(player_index)
    local screen = playerdata.luaplayer.gui.screen
    local window_loc_x, window_loc_y

    -- Destory existing mod GUI if one exists
    if screen[NAME.gui.root_frame] then
        local location = screen[NAME.gui.root_frame].location
        window_loc_x, window_loc_y = location.x, location.y
        screen[NAME.gui.root_frame].destroy()
    end

    playerdata.gui.root = screen.add{
        type="frame",
        name=NAME.gui.root_frame,
        direction="vertical",
        style=NAME.style.root_frame
    }

    do
        local resolution = playerdata.luaplayer.display_resolution
        local x = window_loc_x or 50
        local y = window_loc_y or (resolution.height / 2) - 300
        playerdata.gui.root.location = {x, y}
    end

    -- Create title bar
    local titlebar_flow = playerdata.gui.root.add{
        type="flow",
        direction="horizontal",
        style=NAME.style.titlebar_flow
    }
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

    local hide_empty = playerdata.options.hide_empty_requests
    titlebar_flow.add{
        type="sprite-button",
        name=NAME.gui.hide_empty_button,
        tooltip={"gui.ghost-counter-hide-empty-requests"},
        sprite=hide_empty and NAME.sprite.hide_empty_black or NAME.sprite.hide_empty_white,
        hovered_sprite=NAME.sprite.hide_empty_black,
        clicked_sprite=hide_empty and NAME.sprite.hide_empty_white or NAME.sprite.hide_empty_black,
        style=hide_empty and NAME.style.titlebar_button_active or NAME.style.titlebar_button
    }
    titlebar_flow.add{
        type="sprite-button",
        name=NAME.gui.close_button,
        sprite="utility/close_white",
        hovered_sprite="utility/close_black",
        clicked_sprite="utility/close_black",
        style="close_button"
    }

    local deep_frame = playerdata.gui.root.add{
        type="frame",
        direction="vertical",
        style=NAME.style.inside_deep_frame
    }

    local toolbar = deep_frame.add{
        type="frame",
        direction="horizontal",
        style=NAME.style.topbar_frame
    }
    toolbar.add{
        type="button",
        name=NAME.gui.request_all_button,
        caption="Request all",
        style=NAME.style.ghost_request_all_button
    }
    toolbar.add{
        type="sprite-button",
        name=NAME.gui.cancel_all_button,
        sprite=NAME.sprite.cancel_white,
        hovered_sprite=NAME.sprite.cancel_black,
        clicked_sprite=NAME.sprite.cancel_black,
        style=NAME.style.ghost_cancel_all_button
    }

    playerdata.gui.requests_container = deep_frame.add{
        type="scroll-pane",
        name=NAME.gui.scroll_pane,
        style=NAME.style.scroll_pane
    }

    Gui.make_list(player_index)
end

---Creates the list of request frames in the GUI
---@param player_index number Player index
function Gui.make_list(player_index)
    local playerdata = get_make_playerdata(player_index)

    -- Create a new row frame for each request
    playerdata.gui.requests = {}
    for _, request in pairs(playerdata.job.requests_sorted) do
        Gui.make_row(player_index, request)
    end
end

---Returns request button properties based on request fulfillment and other criteria
---@param request table `request` table
---@param one_time_request table `playerdata.logistic_requests[request.name]`
---@return boolean enabled Whehter button should be enabled
---@return string style Style that should be applied to the button
function make_request_button_properties(request, one_time_request)
    local logistic_request = request.logistic_request or {}

    local enabled = ((logistic_request.min or 0) < request.count) or one_time_request and true or
                        false
    local style =
        ((logistic_request.min or 0) < request.count) and NAME.style.ghost_request_button or
            NAME.style.ghost_request_active_button

    return enabled, style
end

---Updates the list of request frames in the GUI
---@param player_index number Player index
function Gui.update_list(player_index)
    local playerdata = get_make_playerdata(player_index)

    local indices = {count=1, sprite=2, label=3, inventory=4, request=5}

    -- Destroy any child elements in parent scroll pane
    for name, frame in pairs(playerdata.gui.requests) do
        local request = playerdata.job.requests[name]

        if request.count > 0 or not playerdata.options.hide_empty_requests then
            frame.visible = true
            -- Update ghost count
            frame.children[indices.count].caption = request.count

            -- Update amont in inventory
            frame.children[indices.inventory].caption = request.inventory

            -- Calculate amount missing
            local diff = request.count - request.inventory

            -- If amount needed exceeds amount in inventory, show request button
            local request_element = frame.children[indices.request]
            if diff > 0 then
                local enabled, style = make_request_button_properties(request,
                                           playerdata.logistic_requests[request.name])

                if request_element.type == "button" then
                    request_element.enabled = enabled
                    request_element.style = style
                    request_element.caption = diff
                    request_element.tooltip = enabled and
                                                  {"gui.ghost-counter-set-temporary-request"} or
                                                  {"gui.ghost-counter-existing-logistic-request"}
                else
                    frame.children[indices.request].destroy()
                    frame.add{
                        type="button",
                        caption=diff,
                        enabled=enabled,
                        style=style,
                        tooltip=enabled and {"gui.ghost-counter-set-temporary-request"} or
                            {"gui.ghost-counter-existing-logistic-request"},
                        tags={ghost_counter_request=request.name}
                    }
                end
                -- Otherwise create request-fulfilled checkmark previous element was a request button
            elseif request_element.type == "button" then
                request_element.destroy()

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
        else
            frame.visible = false
        end
    end
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

    -- Calculate amount missing
    local diff = request.count - request.inventory

    -- Show one-time request logistic button
    if diff > 0 then
        local enabled, style = make_request_button_properties(request,
                                   playerdata.logistic_requests[request.name])

        frame.add{
            type="button",
            caption=diff,
            enabled=enabled,
            style=style,
            tooltip=enabled and {"gui.ghost-counter-set-temporary-request"} or
                {"gui.ghost-counter-existing-logistic-request"},
            tags={ghost_counter_request=request.name}
        }
    else -- Show request fulfilled sprite
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

    -- Hide frame if ghost count is 0 and player toggled hide empty requests
    frame.visible = request.count > 0 or not playerdata.options.hide_empty_requests and true or
                        false
end

---Event handler for GUI button clicks
---@param event table Event table
function Gui.on_gui_click(event)
    local player_index = event.player_index
    local element = event.element

    if element.name == NAME.gui.close_button then
        -- Close button
        Gui.toggle(player_index, false)
    elseif element.tags and element.tags.ghost_counter_request then
        -- One-time logistic request button
        local playerdata = get_make_playerdata(player_index)
        local request_name = element.tags.ghost_counter_request
        if not playerdata.logistic_requests[request_name] then
            make_one_time_logistic_request(player_index, request_name)
            Gui.update_list(player_index)
        else
            restore_prior_logistic_request(player_index, request_name)
            Gui.update_list(player_index)
        end
    elseif element.name == NAME.gui.hide_empty_button then
        local playerdata = get_make_playerdata(player_index)
        local new_state = not playerdata.options.hide_empty_requests
        playerdata.options.hide_empty_requests = new_state

        element.style = new_state and NAME.style.titlebar_button_active or
                            NAME.style.titlebar_button
        element.sprite = new_state and NAME.sprite.hide_empty_black or NAME.sprite.hide_empty_white
        element.clicked_sprite = new_state and NAME.sprite.hide_empty_white or
                                     NAME.sprite.hide_empty_black

        Gui.update_list(player_index)
    elseif element.name == NAME.gui.request_all_button then
        local playerdata = get_make_playerdata(player_index)
        for _, request in pairs(playerdata.job.requests) do
            if request.count > 0 and not playerdata.logistic_requests[request.name] then
                make_one_time_logistic_request(player_index, request.name)
            end
        end

        Gui.update_list(player_index)
    elseif element.name == NAME.gui.cancel_all_button then
        cancel_all_one_time_requests(player_index)

        Gui.update_list(player_index)
    end
end
script.on_event(defines.events.on_gui_click, Gui.on_gui_click)
