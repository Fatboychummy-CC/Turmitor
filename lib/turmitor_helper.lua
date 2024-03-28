--- Helper methods for Turmitor

local file_helper = require "file_helper"
local logging = require "logging"

local context = logging.create_context("turmitor_helper")

---@diagnostic disable-next-line: inject-field I want to set the "global" working directory of file_helper here.
file_helper.working_directory = ""
local data_dir = file_helper:instanced("data")

---@alias valid_colors "white"|"lightGray"|"gray"|"black"|"brown"|"red"|"orange"|"yellow"|"lime"|"green"|"cyan"|"lightBlue"|"blue"|"purple"|"magenta"|"pink"

---@class TurmitorHelper
---@field public blocks_used table<string, string> The blocks that are needed to build the screen, and the color they correspond with in the `colors` library.
---@field public color_map table<valid_colors, integer> A map of color names to the inventory slot they should be in for the turtle.
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

if turtle then
  local function wipe_queue()
    os.queueEvent("__queue_end")
    for i = 1, math.huge do
      local ev = os.pullEvent()
      if ev == "__queue_end" then break end
      if i % 128 == 0 then os.queueEvent("__queue_end") end
    end
  end

  local tr = turtle.turnRight
  turtle.turnRight = function() ---@diagnostic disable-line
    coroutine.resume(coroutine.create(tr))
    wipe_queue()
    sleep(0.5)
  end

  local tl = turtle.turnLeft
  turtle.turnLeft = function() ---@diagnostic disable-line
    coroutine.resume(coroutine.create(tl))
    wipe_queue()
    sleep(0.5)
  end
end


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

--- Reset the turmitor data.
function TurmitorHelper.reset()
  context.debug("Resetting turmitor data.")
  turmitor_data = default_turmitor_data
  data_dir:delete("turmitor_data.lson")
  os.setComputerLabel()
  os.shutdown()
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

--- Get the position of the turtle in the grid.
---@return number|"unknown" x The x position of the turtle in the grid.
---@return number|"unknown" y The y position of the turtle in the grid.
function TurmitorHelper.get_position()
  return turmitor_data.position.x, turmitor_data.position.y
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

  --- Watch the sides of the turtle until they give a direction.
  ---@param top boolean Whether to watch the top side.
  ---@param right boolean Whether to watch the right side.
  ---@return number? x The x position of the turtle in the grid, or nil if the position is unknown.
  ---@return number? y The y position of the turtle in the grid, or nil if the position is unknown.
  ---@return "top"|"right" side The side that gave the position.
  local function watch_sides(top, right)
    while true do
      local label_top = top and peripheral.call("top", "getLabel")
      local label_right = right and peripheral.call("right", "getLabel")

      if label_top and label_top:match("(%d+),(%d+)") then
        local x, y = label_top:match("(%d+),(%d+)")
        return tonumber(x), tonumber(y), "top"
      end

      if label_right and label_right:match("(%d+),(%d+)") then
        local x, y = label_right:match("(%d+),(%d+)")
        return tonumber(x), tonumber(y), "right"
        end

      sleep(1)
    end
  end

  --- Set the position of the turtle in the grid.
  ---@param x number? The x position of the turtle in the grid.
  ---@param y number? The y position of the turtle in the grid.
  ---@param side "top"|"right"|"none" The side that gave the position.
  ---@return boolean success Whether the operation was successful.
  ---@return string? error The error message if the operation was not successful.
  local function x_y(x, y, side)
      if x and y then
      TurmitorHelper.set_position(side == "right" and x + 1 or x, side == "top" and y + 1 or y)
      context.debug("Set position to x, y.")
        return true
      else
      context.error("Unknown error determining position.")
      return false, "Unknown error determining position."
    end
  end

  if peripheral.getType("right") == "turtle" then
    context.debug("There is a turtle on the right.")
    if peripheral.getType("top") == "turtle" then
      context.debug("There is a turtle on the top.")
      return x_y(watch_sides(true, true))
    else
      context.debug("There is no turtle on the top.")
      return x_y(watch_sides(false, true))
    end
  else
    context.debug("There is no turtle on the right.")
    if peripheral.getType("top") == "turtle" then
      context.debug("There is a turtle on the top.")
      return x_y(watch_sides(true, false))
    else
      context.debug("There is no turtle on the top or right, we are 1,1.")
      return x_y(1, 1, "none")
    end
  end

  context.error("Unknown error determining position.")
end

--- Face the turtle in the "correct" direction, that is, so the wired modem is behind the turtle.
function TurmitorHelper.face_correct_direction()
  context.debug("Attempt face correct direction.")

  local i = 0
  while peripheral.getType("back") ~= "modem" do
    context.debug("Turn right, no modem behind.")
    turtle.turnRight()
    i = i + 1
    if i > 4 then
      error("Could not find the modem behind the turtle.")
    end
    context.debug("Turned.")
  end
end

function TurmitorHelper.check_wrong_concrete()
  context.debug("Checking for wrong concrete.")
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item then
      if slot ~= TurmitorHelper.color_map[TurmitorHelper.blocks_used[item.name]] then
        context.warn(("Slot %d has the wrong concrete, dropping it."):format(slot))
        turtle.select(slot)
        turtle.drop()
      end
    end
  end
end

--- Grab one of each color of concrete from an attached chest.
---@return boolean success Whether the operation was successful.
---@return string? error The error message if the operation was not successful.
function TurmitorHelper.grab_concrete()
  TurmitorHelper.check_wrong_concrete()

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

  local is_block, block_data = turtle.inspect()
  if is_block then
    blocks_dont_have[block_data.name] = nil
    turmitor_data.current_color = TurmitorHelper.blocks_used[block_data.name]
  end

  -- If we have all the blocks, we're done.
  if not next(blocks_dont_have) then
    context.debug("We have all the blocks we need.")
    return true
  end

  -- If we don't, check the chest.
  local chest = peripheral.find("inventory") --[[@as Inventory]]
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
        context.debug("We see the item")
        -- We found the block we need. Grab it.
        local moved = chest.pushItems(turtle_name, slot, 1, TurmitorHelper.color_map[TurmitorHelper.blocks_used[item_needed]])

        if moved == 1 then
          -- We successfully grabbed the block we need.
          found = true
          break
        else
          context.debug("We failed to move it lol")
        end -- otherwise we failed (another turtle probably grabbed it first), so we continue to the next slot.
      end
    end

    if not found then
      context.error(("Could not find '%s' in the chest."):format(item_needed))
      -- We couldn't find the block we need.
      return false, ("Could not find '%s' in the chest."):format(item_needed)
    end
  end

  if not TurmitorHelper.check_wrong_concrete() then
    return false, "Some concrete was placed in the wrong slot."
  end

  return true
end

--- Place a block of concrete of the given color.
---@param color valid_colors The color of the block to place.
---@return boolean success Whether the operation was successful.
function TurmitorHelper.place_concrete_color(color)
  if not TurmitorHelper.color_map[color] then
    error(("Invalid color '%s'."):format(color))
  end

  if turmitor_data.current_color == color then
    -- The block we want is already placed.
    return true
  end

  -- pick up the current block:
  -- 1. Select the position of the block we want to pick up
  -- 2. Pick up the block
  turtle.select(TurmitorHelper.color_map[color])
  turtle.dig()

  -- place the block
  -- 1. Select the position of the block we want to place
  -- 2. Place the block
  turtle.select(TurmitorHelper.color_map[color])
  turtle.place()

  turmitor_data.current_color = color
  TurmitorHelper.save()

  return true
end

return TurmitorHelper
