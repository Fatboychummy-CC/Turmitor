--- Helper methods for Turmitor

local file_helper = require "file_helper"
local logging = require "logging"

local context = logging.create_context("turmitor_helper")

---@diagnostic disable-next-line: inject-field I want to set the "global" working directory of file_helper here.
file_helper.working_directory = ""
local data_dir = file_helper:instanced("data")

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

---@type TurmitorData
local default_turmitor_data = {
  position = {
    x = "unknown",
    y = "unknown"
  },
  current_color = "none"
}


--- Load data from the configuration file, if it exists.
--- On failure, determine the position of the turtle in the grid.
function TurmitorHelper.load()
  context.debug("Loading turmitor data.")
  turmitor_data = data_dir:unserialize(
    "turmitor_data.lson",
    default_turmitor_data
  )
  context.debug("Loaded turmitor data.")

  if turmitor_data.position.x == "unknown" or turmitor_data.position.y == "unknown" then
    context.debug("Loaded data was unknown, determining position.")
    TurmitorHelper.determine_position(true)
  end
end

--- Write the configuration file and set the turtle's label.
function TurmitorHelper.save()
  context.debug("Saving turmitor data.")
  data_dir:serialize("turmitor_data.lson", turmitor_data)

  -- And set the label
  os.setComputerLabel(("%d,%d"):format(turmitor_data.position.x, turmitor_data.position.y))
end

--- Set the position of the turtle in the grid.
---@param x number The x position of the turtle in the grid.
---@param y number The y position of the turtle in the grid.
function TurmitorHelper.set_position(x, y)
  context.debug(("Setting position to %d, %d."):format(x, y))
  turmitor_data.position.x = x
  turmitor_data.position.y = y
  TurmitorHelper.save()
end

--- Determine the position of the turtle in the grid.
---@param skip_load boolean? Whether to skip loading the data from the configuration file.
---@return boolean success Whether the operation was successful.
---@return string? error The error message if the operation was not successful.
function TurmitorHelper.determine_position(skip_load)
  context.info("Determining position.")
  if not skip_load then
    TurmitorHelper.load()
  end
  TurmitorHelper.face_correct_direction()

  -- If we already know our position, we're done.
  if turmitor_data.position.x ~= "unknown" and turmitor_data.position.y ~= "unknown" then
    ---@diagnostic disable-next-line: param-type-mismatch I literally check if it is not "unknown" above here shut up
    TurmitorHelper.set_position(turmitor_data.position.x, turmitor_data.position.y)

    context.debug("We knew the position from our saved data.")
    return true
  end

  context.debug("Continuing to determine position.")

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
    context.info("Waiting for turtle above to know its position.")
    while true do
      local top_label = peripheral.call("top", "getLabel")

      if top_label and top_label ~= "Unknown" then
        context.debug("Turtle above knows its position.")
        -- We know the turtle above's position, so we can determine our Y position.
        local x, y = top_label:match("(%d+),(%d+)")
        x, y = tonumber(x), tonumber(y)

        if x and y then
          TurmitorHelper.set_position(1, y + 1)
          turtle.turnLeft()
          return true
        else
          context.error("Turtle above is giving us unknown position.")
          return false, "Turtle above is giving us unknown position."
        end
      end

      sleep(1)
    end

    return false, "Unknown error determining position (1)."
  end

  -- Wait for the turtle in front to know its position.
  context.info("Waiting for turtle in front to know its position.")
  while true do
    local front_label = peripheral.call("front", "getLabel")

    if front_label and front_label ~= "Unknown" then
      context.debug("Turtle in front knows its position.")
      -- We know the turtle in front's position, so we can determine our X and Y positions.
      local x, y = front_label:match("(%d+),(%d+)")
      x, y = tonumber(x), tonumber(y)

      if x and y then
        TurmitorHelper.set_position(x + 1, y)
        turtle.turnLeft()
        return true
      else
        context.error("Turtle in front is giving us unknown position.")
        return false, "Turtle in front is giving us unknown position."
      end
    end

    sleep(1)
  end

  context.fatal("Unknown error determining position (2).")
  return false, "Unknown error determining position (2)."
end

--- Face the turtle in the "correct" direction, that is, so the wired modem is behind the turtle.
function TurmitorHelper.face_correct_direction()
  context.debug("Attempt face correct direction.")

  local i = 0
  while peripheral.getType("back") ~= "modem" do
    turtle.turnRight()
    i = i + 1
    if i > 4 then
      error("Could not find the modem behind the turtle.")
    end
  end
end

--- Grab one of each color of concrete from an attached chest.
---@return boolean success Whether the operation was successful.
---@return string? error The error message if the operation was not successful.
function TurmitorHelper.grab_concrete()
  context.info("Grabbing concrete.")
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
    context.debug("We have all the blocks we need.")
    return true
  end

  -- If we don't, check the chest.
  local chest = peripheral.find("minecraft:chest")
  if not chest then
    context.error("No chest found.")
    -- No chest, cannot continue.
    return false, "No chest found."
  end

  context.debug(("We need %d blocks."):format((function()
    local count = 0
    for _ in pairs(blocks_dont_have) do
      count = count + 1
    end
    return count
  end)()))

  -- Get the turtle's name from the modem. Modem should be behind the turtle.
  local turtle_name = peripheral.call("back", "getNameLocal")
  if not turtle_name then
    context.error("Could not determine the turtle's name.")
    -- No name, cannot continue.
    return false, "Could not determine the turtle's name. Is the modem behind the turtle (and enabled)?"
  end

  -- Check the chest for the blocks we need.
  for item_needed in pairs(blocks_dont_have) do
    local found = false

    context.info(("Looking for '%s' in the chest."):format(item_needed))

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
      context.error(("Could not find '%s' in the chest."):format(item_needed))
      -- We couldn't find the block we need.
      return false, ("Could not find '%s' in the chest."):format(item_needed)
    end
  end

  return true
end

return TurmitorHelper