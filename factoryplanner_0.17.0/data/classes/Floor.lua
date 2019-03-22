-- Represents a level of a subfactory, is a container for (assembly) lines
Floor = {}

function Floor.init()
    return {
        id = 0,
        level = 0,
        parent_id = 0,
        lines = {},
        line_index = 0,
        line_counter = 0,
        aggregate = {
            energy_consumption = 0,
            products = {},
            byproducts = {},
            ingredients = {}
        },
        valid = true,
        type = "Floor"
    }
end


local function get_floor(player, subfactory_id, id)
    return global.players[player.index].factory.subfactories[subfactory_id].Floor.datasets[id]
end


function Floor.get_level(player, subfactory_id, id)
    return get_floor(player, subfactory_id, id).level
end

function Floor.set_level(player, subfactory_id, id, level)
    get_floor(player, subfactory_id, id).level = level
end


function Floor.add_line(player, subfactory_id, id, line)
    local self = get_floor(player, subfactory_id, id)
    self.line_index = self.line_index + 1
    self.line_counter = self.line_counter + 1
    line.id = self.line_index
    line.gui_position = self.line_counter
    self.lines[self.line_index] = line
    return self.line_index
end

function Floor.delete_line(player, subfactory_id, id, line_id)
    local self = get_floor(player, subfactory_id, id)
    self.line_counter = self.line_counter - 1

    local line = self.lines[line_id]
    if line.type == "FloorReference" then
        Subfactory.delete(player, subfactory_id, "Floor", line.floor_id)
    end

    data_util.update_positions(self.lines, line.gui_position)
    self.lines[line_id] = nil
end

-- Deletes all floors attached to this one (recursively)
-- This leaves the object in disrepair, but it will be deleted afterwards anyway
function Floor.delete_subfloors(player, subfactory_id, id)
    for _, line in ipairs(get_floor(player, subfactory_id, id).lines) do
        if line.type == "FloorReference" then
            Subfactory.delete(player, subfactory_id, "Floor", line.floor_id)
        end
    end
end


function Floor.convert_line_to_floor(player, subfactory_id, id, line_id)
    local self = get_floor(player, subfactory_id, id)
    local line = self.lines[line_id]

    local floor = Floor.init()
    floor.level = self.level + 1
    floor.parent_id = self.id
    floor.line_id = line_id  -- Indicates it's id in the parent floor
    local new_floor_id = Subfactory.add(player, subfactory_id, floor)

    local recipe = global.all_recipes[line.recipe_name]
    local new_line = Line.init(player, recipe)
    new_line.percentage = line.percentage
    new_line.machine_name = line.machine_name
    Floor.add_line(player, subfactory_id, new_floor_id, new_line)
    
    local floor_reference = {
        id = line_id,
        floor_id = new_floor_id,
        gui_position = line.gui_position,
        type = "FloorReference"
    }
    self.lines[line_id] = floor_reference
    return new_floor_id
end

function Floor.convert_floor_to_line(player, subfactory_id, id)
    local floor = get_floor(player, subfactory_id, id)
    local top_floor = get_floor(player, subfactory_id, floor.parent_id)

    local old_line = floor.lines[1]
    local new_line = Line.init(player, global.all_recipes[old_line.recipe_name])
    new_line.id = floor.line_id
    new_line.gui_position = top_floor.lines[floor.line_id].gui_position
    new_line.percentage = old_line.percentage
    new_line.machine_name = old_line.machine_name

    top_floor.lines[floor.line_id] = new_line
    Subfactory.delete(player, subfactory_id, "Floor", id)
end


function Floor.get_line_count(player, subfactory_id, id)
    return get_floor(player, subfactory_id, id).line_counter
end

function Floor.get_line(player, subfactory_id, id, line_id)
    return get_floor(player, subfactory_id, id).lines[line_id]
end

-- Returns line id's in order by position (-> [gui_position] = id)
function Floor.get_lines_in_order(player, subfactory_id, id)
    return data_util.order_by_position(get_floor(player, subfactory_id, id).lines)
end


-- Returns true when a recipe already exists on the given floor
function Floor.recipe_exists(player, subfactory_id, id, recipe)
    if recipe ~= nil then
        for _, line in pairs(get_floor(player, subfactory_id, id).lines) do
            if line.recipe_name == recipe.name then return true end
        end
    end
    return false
end


function Floor.get_aggregate(player, subfactory_id, id)
    return get_floor(player, subfactory_id, id).aggregate
end

-- Updates whole floor from top to bottom, including subfloors
function Floor.update(player, subfactory_id, id)
    local self = get_floor(player, subfactory_id, id)

    local energy_consumption = 0
    for _, line_id in ipairs(Floor.get_lines_in_order(player, subfactory_id, id)) do
        local line = self.lines[line_id]
        if line.type == "FloorReference" then
            local aggregate = Floor.get_aggregate(player, subfactory_id, line.floor_id)
            energy_consumption = energy_consumption + aggregate.energy_consumption
        else
            energy_consumption = energy_consumption + line.energy_consumption
        end
            
    end

    self.aggregate.energy_consumption = energy_consumption
end


function Floor.is_valid(player, subfactory_id, id)
    return get_floor(player, subfactory_id, id).valid
end

-- Updates validity values of the datasets of all data_types
function Floor.check_validity(player, subfactory_id, id)
    local self = get_floor(player, subfactory_id, id)
    self.valid = true
    for line_id, line in pairs(self.lines) do
        if line.type ~= "FloorReference" then
            if not Line.check_validity(player, subfactory_id, id, line_id) then
                self.valid = false
            end
        end
    end
    return self.valid
end

-- Removes all invalid datasets from the given floor
function Floor.remove_invalid_datasets(player, subfactory_id, id)
    local self = get_floor(player, subfactory_id, id)

    for line_id, line in pairs(self.lines) do
        if line.type == "FloorReference" then
            -- Checks if the main (assembly) line of a subfloor is fine, else deletes whole subfloor
            if not Line.attempt_repair(player, subfactory_id, line.floor_id, 1) then
                Floor.delete_line(player, subfactory_id, id, line_id)
            else  -- Recursively calls this method all subordinate floors
                Floor.remove_invalid_datasets(player, subfactory_id, line.floor_id)
            end
        else
            if not line.valid and not Line.attempt_repair(player, subfactory_id, id, line_id) then
                Floor.delete_line(player, subfactory_id, id, line_id)
            end
        end
    end
    -- Convert floor to line if no additional recipes remain
    if self.level > 1 and self.line_counter == 1 then
        Floor.convert_floor_to_line(player, subfactory_id, id)
    end

    self.valid = true
end


function Floor.shift(player, subfactory_id, id, line_id, direction)
    local self = get_floor(player, subfactory_id, id)
    data_util.shift_position(self.lines, line_id, direction, self.line_counter)
end