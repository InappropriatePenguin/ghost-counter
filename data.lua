require("scripts/constants")
require("prototypes/style")

data:extend{
    {
        type="selection-tool",
        name=NAME.tool.ghost_counter,
        subgroup="tool",
        selection_color={57, 156, 251},
        alt_selection_color={0, 89, 132},
        selection_mode={"any-entity", "same-force"},
        alt_selection_mode={"any-entity", "same-force"},
        selection_count_button_color = {43, 113, 180},
        alt_selection_count_button_color = {43, 113, 180},
        selection_cursor_box_type="copy",
        alt_selection_cursor_box_type="copy",
        stack_size=1,
        stackable=false,
        flags={"hidden", "only-in-cursor", "not-stackable", "spawnable"},
        icon="__ghost-counter__/graphics/ghost-counter-tool.png",
        icon_size=64
    }, {
        type="shortcut",
        name=NAME.shortcut.button,
        localised_name={"shortcut.make-ghost-counter"},
        action="spawn-item",
        icon={
            filename="__ghost-counter__/graphics/shortcut-button.png",
            priority="medium",
            size=64,
            flags={"gui-icon"}
        },
        item_to_spawn=NAME.tool.ghost_counter,
        associated_control_input=NAME.input.ghost_counter,
        style="blue"
    }, {
        type="custom-input",
        name=NAME.input.ghost_counter,
        key_sequence="ALT + G",
        action="spawn-item",
        item_to_spawn=NAME.tool.ghost_counter
    }, {
        type = "sprite",
        name = NAME.sprite.hide_empty_white,
        filename = "__ghost-counter__/graphics/hide_white.png",
        priority = "medium",
        width = 32,
        height = 32,
        flags = {"gui-icon"},
        scale = 0.5
    }, {
        type = "sprite",
        name = NAME.sprite.hide_empty_black,
        filename = "__ghost-counter__/graphics/hide_black.png",
        priority = "medium",
        width = 32,
        height = 32,
        flags = {"gui-icon"},
        scale = 0.5
    }
}
