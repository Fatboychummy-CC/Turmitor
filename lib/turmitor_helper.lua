--- Helper methods for Turmitor

local data_dir = require "file_helper":instanced("data")

---@class TurmitorHelper
---@field public blocks_used table<string, string> The blocks that are needed to build the screen, and the color they correspond with in the `colors` library.
---@field public color_map table<string, integer> A map of color names to the inventory slot they should be in for the turtle.
local TurmitorHelper = {
  blocks_used = {
    ["minecraft:white_concrete"] = "white",
    ["minecraft:light_gray_concrete"] = "lightGray",
    ["minecraft:gray_concrete"] = "gray",
    ["minecraft:black_concrete"] = "black",
    ["minecraft:brown_concrete"] = "brown",
    ["minecraft:red_concrete"] = "red",
    ["minecraft:orange_concrete"] = "orange",
    ["minecraft:yellow_concrete"] = "yellow",
    ["minecraft:lime_concrete"] = "lime",
    ["minecraft:green_concrete"] = "green",
    ["minecraft:cyan_concrete"] = "cyan",
    ["minecraft:light_blue_concrete"] = "lightBlue",
    ["minecraft:blue_concrete"] = "blue",
    ["minecraft:purple_concrete"] = "purple",
    ["minecraft:magenta_concrete"] = "magenta",
    ["minecraft:pink_concrete"] = "pink",
  },
  color_map = {
    white = 1,
    lightGray = 2,
    gray = 3,
    black = 4,
    brown = 5,
    red = 6,
    orange = 7,
    yellow = 8,
    lime = 9,
    green = 10,
    cyan = 11,
    lightBlue = 12,
    blue = 13,
    purple = 14,
    magenta = 15,
    pink = 16
  }
}

---@alias valid_colors "white"|"lightGray"|"gray"|"black"|"brown"|"red"|"orange"|"yellow"|"lime"|"green"|"cyan"|"lightBlue"|"blue"|"purple"|"magenta"|"pink"

---@class TurmitorData The data for the turmitor.
---@field position {x:"unknown"|number, y:"unknown"|number} The position of the turtle in the grid.
---@field current_color "none"|valid_colors The current color that the turtle has placed, or none.
local turmitor_data = {
  position = {
    x = "unknown",
    y = "unknown"
  },
  current_color = "none"
}


--- Load data from the configuration file, if it exists.
--- On failure, determine the position of the turtle in the grid.
function TurmitorHelper.load()
  turmitor_data = data_dir:unserialize(
    "turmitor_data.lson",
    turmitor_data
  )

  if turmitor_data.position.x == "unknown" or turmitor_data.position.y == "unknown" then
    TurmitorHelper.determine_position()
  end
end

--- Write the configuration file and set the turtle's label.
function TurmitorHelper.save()
  data_dir:serialize("turmitor_data.lson", turmitor_data)

  -- And set the label
  os.setComputerLabel(("%d,%d"):format(turmitor_data.position.x, turmitor_data.position.y))
end

--- Set the position of the turtle in the grid.
---@param x number The x position of the turtle in the grid.
---@param y number The y position of the turtle in the grid.
function TurmitorHelper.set_position(x, y)
  turmitor_data.position.x = x
  turmitor_data.position.y = y
  TurmitorHelper.save()
end

--- Determine the position of the turtle in the grid.
---@return boolean success Whether the operation was successful.
---@return string? error The error message if the operation was not successful.
function TurmitorHelper.determine_position()
  TurmitorHelper.load()
  TurmitorHelper.face_correct_direction()

  -- If we already know our position, we're done.
  if turmitor_data.position.x ~= "unknown" and turmitor_data.position.y ~= "unknown" then
    ---@diagnostic disable-next-line: param-type-mismatch I literally check if it is not "unknown" above here shut up
    TurmitorHelper.set_position(turmitor_data.position.x, turmitor_data.position.y)
    return true
  end

  -- Turn to the right.
  turtle.turnRight()

  -- Check for a turtle in front.
  if not turtle.detect() then
    -- If there's no turtle in front, we're at the edge of the grid, but we don't know our Y position yet.

    -- Check for a turtle above.
    if not turtle.detectUp() then
      -- If there's no turtle above, we're at the corner of the grid.
      TurmitorHelper.set_position(1, 1)
      return true
    end

    -- Wait for the turtle above to know its position.
    while true do
      local top_label = peripheral.call("top", "getLabel")

      if top_label and top_label ~= "Unknown" then
        -- We know the turtle above's position, so we can determine our Y position.
        local x, y = top_label:match("(%d+),(%d+)")
        x, y = tonumber(x), tonumber(y)

        if x and y then
          TurmitorHelper.set_position(1, y + 1)
          return true
        else
          return false, "Turtle above is giving us unknown position."
        end
      end

      sleep(1)
    end

    return false, "Unknown error determining position (1)."
  end

  -- Wait for the turtle in front to know its position.
  while true do
    local front_label = peripheral.call("front", "getLabel")

    if front_label and front_label ~= "Unknown" then
      -- We know the turtle in front's position, so we can determine our X and Y positions.
      local x, y = front_label:match("(%d+),(%d+)")
      x, y = tonumber(x), tonumber(y)

      if x and y then
        TurmitorHelper.set_position(x + 1, y)
        return true
      else
        return false, "Turtle in front is giving us unknown position."
      end
    end

    sleep(1)
  end

  return false, "Unknown error determining position (2)."
end

--- Face the turtle in the "correct" direction, that is, so the wired modem is behind the turtle.
function TurmitorHelper.face_correct_direction()
  while peripheral.getType("back") ~= "modem" do
    turtle.turnRight()
  end
end

--- Grab one of each color of concrete from an attached chest.
---@return boolean success Whether the operation was successful.
---@return string? error The error message if the operation was not successful.
function TurmitorHelper.grab_concrete()
  -- A lookup table of all the blocks we don't have.
  local blocks_dont_have = {}
  for k in pairs(TurmitorHelper.blocks_used) do
    blocks_dont_have[k] = true
  end

  -- Check the turtle's inventory for the blocks we need.
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item then
      blocks_dont_have[item.name] = nil
    end
  end

  -- If we have all the blocks, we're done.
  if not next(blocks_dont_have) then
    return true
  end

  -- If we don't, check the chest.
  local chest = peripheral.find("minecraft:chest")
  if not chest then
    -- No chest, cannot continue.
    return false, "No chest found."
  end

  -- Get the turtle's name from the modem. Modem should be behind the turtle.
  local turtle_name = peripheral.call("back", "getNameLocal")
  if not turtle_name then
    -- No name, cannot continue.
    return false, "Could not determine the turtle's name. Is the modem behind the turtle (and enabled)?"
  end

  -- Check the chest for the blocks we need.
  for item_needed in pairs(blocks_dont_have) do
    local found = false

    -- For each slot with an item in it, check if it's the block we need.
    for slot, item in pairs(chest.list()) do
      if item.name == item_needed then
        -- We found the block we need. Grab it.
        local moved = chest.pushItems(turtle_name, slot, 1)

        if moved == 1 then
          -- We successfully grabbed the block we need.
          found = true
          break
        end -- otherwise we failed (another turtle probably grabbed it first), so we continue to the next slot.
      end
    end

    if not found then
      -- We couldn't find the block we need.
      return false, ("Could not find '%s' in the chest."):format(item_needed)
    end
  end

  return true
end

return TurmitorHelper
