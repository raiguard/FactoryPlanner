require("mod-gui")
require("ui.elements.actionbar")
require("ui.elements.subfactory_bar")
require("ui.elements.error_bar")
require("ui.elements.subfactory_pane")
require("ui.elements.production_titlebar")
require("ui.elements.production_table")

-- Create the always-present GUI button to open the main dialog + devmode setup
function player_gui_init(player)
    local frame_flow = mod_gui.get_button_flow(player)
    if not frame_flow["fp_button_toggle_interface"] then
        frame_flow.add
        {
            type = "button",
            name = "fp_button_toggle_interface",
            caption = "FP",
            tooltip = {"fp.open_main_dialog"},
            style = mod_gui.button_style,
            mouse_button_filter = {"left"}
        }
    end

    -- Incorporates the mod setting for the visibility of the toggle-main-dialog-button
    toggle_button_interface(player)
end

-- Destroys all GUI's so they are loaded anew the next time they are shown
function player_gui_reset(player)
    local screen = player.gui.screen
    local guis = {
        mod_gui.get_button_flow(player)["fp_button_toggle_interface"],
        screen["fp_frame_main_dialog"],
        unpack(cached_dialogs)
    }
    for _, gui in pairs(guis) do
        if type(gui) == "string" then gui = screen[gui] end
        if gui ~= nil and gui.valid then gui.destroy() end
    end
end


-- Toggles the visibility of the toggle-main-dialog-button
function toggle_button_interface(player)
    local enable = get_settings(player).show_gui_button
    mod_gui.get_button_flow(player)["fp_button_toggle_interface"].visible = enable
end

-- Returns true when the main dialog is open while no modal dialogs are
function is_main_dialog_in_focus(player)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    return (main_dialog ~= nil and main_dialog.visible
      and get_ui_state(player).modal_dialog_type == nil)
end


-- Toggles the main dialog open and closed
function toggle_main_dialog(player)
    -- Won't toggle if a modal dialog is open
    if get_ui_state(player).modal_dialog_type == nil then
        local main_dialog = player.gui.screen["fp_frame_main_dialog"]
        if main_dialog ~= nil then main_dialog.visible = not main_dialog.visible end
        main_dialog = refresh_main_dialog(player)
        player.opened = main_dialog.visible and main_dialog or nil

        -- Handle the pause_on_open_interface option
        if get_settings(player).pause_on_interface and not game.is_multiplayer() and
          player.controller_type ~= defines.controllers.editor then
            game.tick_paused = main_dialog.visible  -- only pause when the main dialog is open
        end
    end
end

-- Changes the main dialog in reaction to a modal dialog being opened/closed
function toggle_modal_dialog(player, frame_modal_dialog)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]

    -- If the frame parameter is not nil, the given modal dialog has been opened
    if frame_modal_dialog ~= nil then
        player.opened = frame_modal_dialog
        main_dialog.ignored_by_interaction = true
    else
        player.opened = main_dialog
        main_dialog.ignored_by_interaction = false
        refresh_main_dialog(player)
    end
end

-- Sets selection mode and configures the related GUI's
function set_selection_mode(player, state)
    local ui_state = get_ui_state(player)
    ui_state.selection_mode = state
    player.gui.screen["fp_frame_main_dialog"].visible = not state

    local frame_modal_dialog = player.gui.screen["fp_frame_modal_dialog"]
    frame_modal_dialog.ignored_by_interaction = state
    if state == true then
        frame_modal_dialog.location = {25, 50}
    else
        frame_modal_dialog.force_auto_center()
        player.opened = frame_modal_dialog
    end
end


-- Refreshes the entire main dialog, optionally including it's dimensions
-- Creates the dialog if it doesn't exist; Recreates it if needs to
function refresh_main_dialog(player, full_refresh)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]

    if (main_dialog == nil and not full_refresh) or (main_dialog ~= nil and full_refresh) then
        if main_dialog ~= nil then main_dialog.clear()
        else main_dialog = player.gui.screen.add{type="frame", name="fp_frame_main_dialog", style='dialog_frame', direction="vertical"} end

        local dimensions = ui_util.recalculate_main_dialog_dimensions(player)
        ui_util.properly_center_frame(player, main_dialog, dimensions.width, dimensions.height)
        main_dialog.style.minimal_width = dimensions.width
        main_dialog.style.height = dimensions.height
        main_dialog.visible = (not full_refresh) or false  -- hide dialog on a full refresh

        add_titlebar_to(main_dialog)

        -- background pane
        local background_pane = main_dialog.add{type='frame', name='fp_background_pane', style='inside_deep_frame'}

        add_actionbar_to(background_pane)

        -- tabbed pane
        add_subfactory_bar_to(main_dialog)
        add_error_bar_to(main_dialog)
        add_subfactory_pane_to(main_dialog)
        add_production_pane_to(main_dialog)

    elseif main_dialog ~= nil and main_dialog.visible then
        -- Re-center the main dialog because it get screwed up sometimes for reasons
        local dimensions = ui_util.recalculate_main_dialog_dimensions(player)
        ui_util.properly_center_frame(player, main_dialog, dimensions.width, dimensions.height)

        -- Refresh the elements on top of the hierarchy, which refresh everything below them
        refresh_actionbar(player)
        refresh_subfactory_bar(player, true)
    end

    ui_util.message.refresh(player)
    return main_dialog
end

-- Creates the titlebar including name and exit-button
function add_titlebar_to(main_dialog)
    local titlebar = main_dialog.add{type="flow", name="flow_titlebar", direction="horizontal"}
    titlebar.style.vertical_align = 'center'
    titlebar.style.top_margin = -2

    -- Title
    local label_title = titlebar.add{type="label", name="label_titlebar_name", style='frame_title', caption=" Factory Planner"}

    -- Hint
    local label_hint = titlebar.add{type="label", name="label_titlebar_hint"}
    label_hint.style.font = "fp-font-16p"
    label_hint.style.top_margin = 8
    label_hint.style.left_margin = 14
    label_hint.visible = false -- for now, until we move the hints to the action bar

    -- Drag handle
    local handle = titlebar.add{type="empty-widget", name="empty-widget_titlebar_space", style="draggable_space_header"}
    handle.style.horizontally_stretchable = true
    handle.style.height = 24
    handle.style.right_margin = 7
    handle.drag_target = main_dialog

    -- Buttons
    titlebar.add{type="sprite-button", name="fp_button_titlebar_tutorial", tooltip={"fp.tutorial"},
      style="close_button", mouse_button_filter={"left"}, sprite="fp_sprite_tutorial", hovered_sprite="fp_sprite_tutorial_black",
      clicked_sprite="fp_sprite_tutorial_black"}
    titlebar.add{type="sprite-button", name="fp_button_titlebar_preferences", tooltip={"fp.preferences"},
      style="close_button", mouse_button_filter={"left"}, sprite="fp_sprite_preferences", hovered_sprite="fp_sprite_preferences_black",
      clicked_sprite="fp_sprite_preferences_black"}

    local button_exit = titlebar.add{type="sprite-button", name="fp_button_titlebar_exit",
      style="close_button", mouse_button_filter={"left"}, sprite="utility/close_white", hovered_sprite="utility/close_black",
      clicked_sprite="utility/close_black"}
end