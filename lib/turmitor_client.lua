--- This is the Turmitor Client file. To use this, put it on a disk drive that
--- is connected to a network of turtles. Ensure that you right-click the modem
--- connecting the drive to the network, so that the turtles can actually see
--- the disk drive. Then, you should be able to simply create a startup file
--- with the following code on the disk:
--- ```lua
--- -- Set the working directory, so require works properly.
--- -- We use this in case we get set to `disk5` or something silly like that.
--- shell.setDir(fs.getDir(shell.getRunningProgram()))
--- 
--- -- Set the package path to include the lib directory.
--- package.path = package.path .. ";lib/?.lua;lib/?/init.lua"
---
--- -- Optional: Set logging level:
--- -- local logging = require "logging"
--- -- logging.set_level(logging.LOG_LEVEL.DEBUG)
---
--- -- Import the turtle client.
--- local turmitor_client = require "turmitor_client"
---
--- -- Optional: Set whether or not the Turmitor clients are built horizontally
--- -- or vertically. By default, this value is "vertical".
--- -- turmitor_client.array_style = "horizontal"
--- 
--- -- Run the Turmitor client.
--- turmitor_client.run()
--- ```
---
--- If you set the array style to horizontal, do note that you will need to
--- place **polished** andesite blocks all along the "top" of the array.
--- This will allow the turtles to orient themselves properly. A vertical array
--- does not need any sort of guide block, as they can just check if another
--- turtle is above them or not.

--[[
  Clients will act on the following actions without responding:
  - character: Have the specified 6x9 array of turtles place a character.
    - data: table
      - char_x: number The x position of the character in the font.
      - char_y: number The y position of the character in the font.
      - fg: valid_colors The foreground color of the character.
      - bg: valid_colors The background color of the character.
  - place-batch: Have the specified turtles place a batch of blocks.
    - data: table
      - orders: list<table>
        - x: number The x position of the turtle.
        - z: number The z position of the turtle.
        - color: valid_colors The color of the block to place.
  - place: Have a single specified turtle place a block.
    - data: table
      - x: number The x position of the turtle.
      - z: number The z position of the turtle.
      - color: valid_colors The color of the block to place.
  - clear: Have all turtles clear the screen.
    - data: table
      - color: valid_colors The color to clear the screen with.
  - reset: Have all turtles reset their position data.

  Clients will respond for the following actions:
  - get-size: Get the size of the array. Only the bottom-right-most turtle will
    respond.
    - response: table
      - x: number The x size of the array.
      - z: number The z size of the array.

  For example, to send a character:
  ```lua
  local to_transmit = {
    action = "character",
    data = {
      char_x = 37,
      char_y = 16,
      fg = "white",
      bg = "black"
    }
  }
  ```
  Assuming the character's top-left position in `font.fbmp` is at 37, 16, and
  the foreground color is white and the background color is black.

  All communications between turmitor clients and server should have the field
  "_turmitor" set to true, for easy filtering of other messages.
]]


-- Do not run if not on a turtle
if not turtle then
  error("The Turmitor Client can only run on a turtle.", 0)
end

-- Import libraries
local expect = require "cc.expect".expect
local logging = require "logging"
local smn = require "single_modem_network"
local file_helper = require "file_helper"
local read_fbmp = require "read_fbmp"
local TurmitorChannels = require "turmitor_channels"

-- Setup libraries

--- Main client logger.
local client_main = logging.create_context("client")

--- The data folder on the disk drive, so we can read the font file.
local disk_data_folder = file_helper:instanced("data")

-- We want this set to root so that we can access the root folder, since each
-- turtle needs to store its own data and we don't want to shove it all onto the
-- disk drive.
---@diagnostic disable-next-line: inject-field
file_helper.working_directory = ""
local data_folder = file_helper:instanced("data")

-- Constants
local FONT_FILE = "font.fbmp"
local TURTLE_LABEL_MATCHER = "(%d+),(%d+)"

-- Type definitions

---@class TurmitorPosition
---@field x number The x coordinate of the turtle. A negative value indicates unknown.
---@field z number The z coordinate of the turtle, or the y coordinate if the array is built vertically. A negative value indicates unknown.
---@field char_x number The character-x coordinate of the turtle (the array is divided into 6x9 "characters"). A negative value indicates unknown.
---@field char_z number The character-z coordinate of the turtle (the array is divided into 6x9 "characters"). A negative value indicates unknown.
---@field inner_x number The x coordinate inside of the character that the turtle is positioned at. A negative value indicates unknown.
---@field inner_z number The z coordinate inside of the character that the turtle is positioned at. A negative value indicates unknown.

---@alias valid_colors "white"|"lightGray"|"gray"|"black"|"brown"|"red"|"orange"|"yellow"|"lime"|"green"|"cyan"|"lightBlue"|"blue"|"purple"|"magenta"|"pink"

-- Class definition

---@class TurmitorClient
---@field public position TurmitorPosition The current position of the turtle.
---@field public array_style "horizontal"|"vertical" The style of the array. If horizontal, the array is built along the x/z axis (i.e flat across the ground). If vertical, the array is built along the x/y axis, with `z` referring to the `y` position.
---@field public font table The font data for the turtle.
---@field public blocks_used table<string, string> The blocks that are needed to build the screen, and the color they correspond with in the `colors` library.
---@field public color_map table<valid_colors, integer> A map of color names to the inventory slot they should be in for the turtle.
---@field public current_color valid_colors? The current color that the turtle has placed.
---@field public color_want valid_colors? The color that the turtle wants to place next. This can update while currently placing a block, and allows the turtle to immediately place what is needed next, if needed.
---@field public guideblock_top "minecraft:polished_andesite"|string The block that is used to guide the turtle in the horizontal array style. This is by default polished andesite.
---@field public guideblock_left "minecraft:polished_diorite"|string The block that is used to guide the turtle in the horizontal array style. This is by default polished diorite.
---@field public control_channel number The channel that the turtle listens on for control messages.
local TurmitorClient = {
  position = {
    x = -1,
    z = -1,
    char_x = -1,
    char_z = -1,
    inner_x = -1,
    inner_z = -1
  },
  array_style = "vertical",
  font = {},
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
  },
  current_color = nil,
  color_want = "black",
  guideblock_top = "minecraft:polished_andesite",
  guideblock_left = "minecraft:polished_diorite",
  control_channel = -1,
  is_bottom_right_corner = false,
}

-- Private (local) functions

--- Wipe the event queue.
local function wipe_queue()
  os.queueEvent("__queue_end")
  for i = 1, math.huge do
    local ev = os.pullEvent()
    if ev == "__queue_end" then break end
    if i % 128 == 0 then os.queueEvent("__queue_end") end
  end
end

--- Turn the turtle to the left in a safe way that doesn't stall on too many events.
local function turn_left()
  coroutine.resume(coroutine.create(turtle.turnLeft))
  wipe_queue()
  sleep(0.5)
end

--- Turn the turtle to the right in a safe way that doesn't stall on too many events.
local function turn_right()
  coroutine.resume(coroutine.create(turtle.turnRight))
  wipe_queue()
  sleep(0.5)
end


--- Count the length of a dictionary style table.
---@param tbl table The table to count the length of.
---@return integer length The length of the table.
local function count(tbl)
  local length = 0
  for _ in pairs(tbl) do
    length = length + 1
  end
  return length
end

--- Check the orientation of the turtle in comparison to the `array_style`.
--- In particular, if the style is set to "horizontal", a modem should be below
--- the turtle (and in no other position). If the style is set to "vertical",
--- a modem should be on *some* side of the turtle, but not above or below it.
---
--- Throws an error on failure, and should be called during initialization of
--- the array.
local function check_orientation()
  client_main.debug("Checking orientation of the turtle.")
  if TurmitorClient.array_style == "vertical" then
    if peripheral.hasType("bottom", "modem")
      or peripheral.hasType("top", "modem") then
      error("Modem should not be below or above the turtle in vertical array style.", 0)
    end

    client_main.debug("Orientation check passed (vertical).")
  elseif TurmitorClient.array_style == "horizontal" then
    if not peripheral.hasType("bottom", "modem") then
      error("Modem should be below the turtle in horizontal array style.", 0)
    end

    client_main.debug("Orientation check passed (horizontal).")
  else
    error(("Invalid array style specified: %s"):format(TurmitorClient.array_style), 0)
  end
end

--- Set up the font data for this turtle.
local function setup_font()
  client_main.debug("Setting up font data.")

  local font = read_fbmp(fs.combine(disk_data_folder.working_directory, FONT_FILE))
  if not font then
    error("Could not read font data.")
  end

  client_main.debug("Font data read successfully.")
  TurmitorClient.font = font
end

--- Reset the turmitor data.
local function reset()
  client_main.warn("Resetting turmitor data.")
  data_folder:delete("turmitor_data.lson")
  os.setComputerLabel()
  os.shutdown()
end

--- Load data from the configuration file, if it exists.
--- On failure, determine the position of the turtle in the grid.
local function load()
  client_main.debug("Loading turmitor data.")
  local position_data = data_folder:unserialize(
    "turmitor_data.lson",
    TurmitorClient.position
  )
  client_main.debug("Loaded turmitor data.")

  if position_data.x == -1 or position_data.z == -1 then
    client_main.debug("Loaded data was unknown, determining position.")
    TurmitorClient.determine_position()
  elseif not position_data.x or not position_data.z then
    client_main.fatal("Loaded data was invalid, resetting.")
    reset()
  else
    TurmitorClient.set_position(position_data.x, position_data.z)
  end
end

--- Write the configuration file and set the turtle's label.
local function save()
  client_main.debug("Saving turmitor data.")
  data_folder:serialize("turmitor_data.lson", {
    x = TurmitorClient.position.x,
    z = TurmitorClient.position.z
  })

  -- And set the label
  os.setComputerLabel(("%d,%d"):format(TurmitorClient.position.x, TurmitorClient.position.z))
end

--- Return the items in a slot to the inventory. Keeps trying until successful,
--- so ensure the inventory isn't full!
local function return_to_inventory(slot)
  client_main.info(("Returning item(s) in slot %d to inventory."):format(slot))

  local moved_count = 0
  local in_slot = turtle.getItemCount(slot)
  while true do

    -- attempt to push to any inventory.
    local inventories = table.pack(smn.find("inventory"))
    for _, inventory in ipairs(inventories) do
      local inv_name = peripheral.getName(inventory)

      moved_count = moved_count + smn.call(inv_name, "pullItems", smn.getNameLocal(), slot, in_slot - moved_count)
      if moved_count >= in_slot then break end
    end

    if turtle.getItemCount(slot) == 0 then
      client_main.info(("Returned %d item(s) in slot %d to inventory."):format(moved_count, slot))
      return
    end
  end
end

--- Resolve incorrect slot items by moving them to the correct slot, or
--- returning them to the inventory.
---@param slot integer The slot that has the incorrect item.
local function resolve_incorrect_slot(slot)
  local block_data = turtle.getItemDetail(slot)
  if not block_data then return end -- Nothing to do.

  local color = TurmitorClient.blocks_used[block_data.name]
  local slot_want = TurmitorClient.color_map[color]

  if slot == slot_want then
    -- Nothing to do, why was this called?
    client_main.warn(("resolve_incorrect_slot called (%d : %s), but correct item is in slot."):format(slot, color))
    return
  end

  if turtle.transferTo(slot_want) then
    client_main.info(("Moved block for color %s to slot %d."):format(color, slot_want))
  else
    client_main.warn(("Could not move block for color %s to slot %d. Returning to inventory."):format(color, slot_want))
    return_to_inventory(slot)
  end
end

--- Check if the turtle has the right types of blocks in its inventory, in the
--- right slots.
---@return table<valid_colors, integer> blocks_missing The colors that are missing from the inventory.
local function check_inventory()
  client_main.debug("Checking inventory.")

  local blocks_missing = {}

  for color, slot in pairs(TurmitorClient.color_map) do
    local block_data = turtle.getItemDetail(slot)

    if block_data then
      -- Check if the block is in the wrong spot.
      if color ~= TurmitorClient.blocks_used[block_data.name] then
        client_main.warn(("Block for color %s is in the wrong slot (check)."):format(color))
        client_main.info(block_data.name, TurmitorClient.color_map[TurmitorClient.blocks_used[block_data.name]])
        sleep(5)

        resolve_incorrect_slot(slot)
      end
    else
      -- If the block is missing
      client_main.warn(("Missing block for color %s in slot %d."):format(color, slot))
      blocks_missing[color] = slot
    end
  end

  -- Check if a block is above (or in front) of the turtle, currently placed.
  local is_block, block_data
  if TurmitorClient.array_style == "vertical" then
    is_block, block_data = turtle.inspect()
  else
    is_block, block_data = turtle.inspectUp()
  end

  if is_block then
    local color = TurmitorClient.blocks_used[block_data.name]

    if not color then
      error("Unknown block placed.", 0)
    end

    if blocks_missing[color] then
      client_main.info(("Found placed block for color %s."):format(color))
      blocks_missing[color] = nil
    else
      -- Return the block to the inventory.
      client_main.warn(("Block of color %s is in our inventory AND placed. Returning one of them."):format(color))
      return_to_inventory(TurmitorClient.color_map[color])
    end

    -- Then select the slot we want, and pick up the block.
    turtle.select(TurmitorClient.color_map[color])
    if TurmitorClient.array_style == "vertical" then
      turtle.dig()
    else
      turtle.digUp()
    end
  end

  local success = count(blocks_missing) == 0

  if success then
    client_main.debug("Inventory check passed.")
  else
    client_main.warn("Inventory check failed.")
  end

  return blocks_missing
end

--- Locate and collect each color of block that is missing from the inventory.
--- This function assumes that smn has been set up!
local function get_blocks()
  local blocks_missing = check_inventory()

  if next(blocks_missing) then
    client_main.info("Collecting blocks.")

    local inventories = table.pack(smn.find("inventory"))
    local turtle_name = smn.getNameLocal()

    while next(blocks_missing) do
      -- Iterate through each inventory, and do the following:
      -- 1. Check each slot for colors we need.
      -- 2. If we find a color we need, attempt to take it.

      for _, inventory in ipairs(inventories) do
        local inv_name = peripheral.getName(inventory)
        local list = smn.call(inv_name, "list")

        for slot, item_data in pairs(list) do
          local color = TurmitorClient.blocks_used[item_data.name]

          if color and blocks_missing[color] then
            client_main.info(("Found block for color %s in %s."):format(color, inv_name))

            -- Attempt to take the block.
            local moved_count = smn.call(inv_name, "pushItems", turtle_name, slot, 1, TurmitorClient.color_map[color])

            if moved_count >= 1 then
              client_main.info(("Took block for color %s from %s."):format(color, inv_name))

              -- And double check that the slot now contains the item we want,
              -- and not something different.
              local block_data = turtle.getItemDetail(TurmitorClient.color_map[color])
              if block_data and block_data.name ~= item_data.name then
                client_main.warn(("Block for color %s is in the wrong slot (get)."):format(color))
                resolve_incorrect_slot(TurmitorClient.color_map[color])
              elseif block_data then
                client_main.info(("Block for color %s is now in the correct slot."):format(color))
                blocks_missing[color] = nil
              end
            else
              client_main.warn(("Could not take block for color %s from %s."):format(color, inv_name))
            end
          end
        end

        sleep(1) -- Wait a small bit between tries.
      end
    end
  end
end

--- Check if the block on a given side is a turtle, and if so, get the label.
---@param side computerSide The side to get the turtle label from.
---@return boolean is_turtle Whether or not the block in that direction is a turtle.
---@return string? label The label of the turtle, if it is a turtle and has one.
local function get_turtle_label(side)
  expect(1, side, "string")

  local is_turtle = peripheral.hasType(side, "turtle")

  if is_turtle then
    return true, peripheral.call(side, "getLabel")
  end

  return false
end

local function determine_bottom_right_corner()
  if TurmitorClient.array_style == "vertical" then
    if not get_turtle_label("bottom") and not get_turtle_label("left") then
      client_main.info("Turtle is in the bottom-right corner.")
      TurmitorClient.is_bottom_right_corner = true
    end
  elseif TurmitorClient.array_style == "horizontal" then
    ---@fixme implement this
  end
end

local det_context = logging.create_context("determine_position")

--- Determine the position of the turtle in the grid, vertical style
---@return number x The x position of the turtle in the grid.
---@return number z The z position of the turtle in the grid.
local function _determine_vertical()
  -- Vertical grid is easy, we can just:
  -- 1. Rotate so the modem is behind us.
  -- 2. Turn to the right once.
  -- From there, we can just inspect/inspectUp to check if a turtles is in front
  -- or above, and if so take the following actions:
  -- 1. Turtle in front, turtle above: Wait until either turtle knows its
  --    position, then set our position to the turtle's position + 1 (along
  --    whatever axis is needed).
  -- 2. Turtle in front, no turtle above: We know we are at z 1. Wait until the
  --    turtle in front knows its position, then set our position to x + 1, 1.
  -- 3. No turtle in front, turtle above: We know we are at x 1. Wait until the
  --    turtle above knows its position, then set our position to 1, z + 1.
  -- 4. No turtle in front, no turtle above: We are at 1, 1. We are the first
  --    turtle in the array.

  -- Rotate so the modem is behind us.
  while not peripheral.hasType("back", "modem") do
    det_context.debug("Rotating to find modem.")
    turn_right()
  end

  -- Check if a turtle is on the right or above.
  local is_turtle_right, label_right = get_turtle_label("right")
  local is_turtle_up, label_up = get_turtle_label("top")

  det_context.debug(("Turtle on right: %s, Turtle above: %s."):format(tostring(is_turtle_right), tostring(is_turtle_up)))

  -- Turtle on the right AND above.
  if is_turtle_right and is_turtle_up then
    -- Wait until both turtles know their position.
    det_context.debug("Waiting for turtles to know their position.")
    while not label_up or not label_up:match(TURTLE_LABEL_MATCHER)
    or not label_right or not label_right:match(TURTLE_LABEL_MATCHER) do
      sleep(1)
      label_right = peripheral.call("right", "getLabel")
      label_up = peripheral.call("top", "getLabel")
    end

    local x, z = label_right:match(TURTLE_LABEL_MATCHER)
    x, z = tonumber(x), tonumber(z)
    if x and z then
      det_context.debug(("Got position from right: %d, %d."):format(x, z))
      return x + 1, z
    end

    x, z = label_up:match(TURTLE_LABEL_MATCHER)
    x, z = tonumber(x), tonumber(z)
    if x and z then
      det_context.debug(("Got position from above: %d, %d."):format(x, z))
      return x, z + 1
    end
    error("Could not determine position of turtle in vertical array style (1).", 0)
  end

  -- Only a turtle on the right
  if is_turtle_right then
    -- Wait until the turtle on the right knows its position.
    det_context.debug("Waiting for turtle on right to know its position.")
    while not label_right or not label_right:match(TURTLE_LABEL_MATCHER) do
      sleep(1)
      label_right = peripheral.call("right", "getLabel")
    end

    local x, _ = label_right:match(TURTLE_LABEL_MATCHER)
    x = tonumber(x)
    if x then
      det_context.debug(("Got position from right: %d, 1."):format(x))
      return x + 1, 1
    end
    error("Could not determine position of turtle in vertical array style (2).", 0)
  end

  -- Only a turtle above.
  if is_turtle_up then
    -- Wait until the turtle above knows its position.
    det_context.debug("Waiting for turtle above to know its position.")
    while not label_up or not label_up:match(TURTLE_LABEL_MATCHER) do
      sleep(1)
      label_up = peripheral.call("top", "getLabel")
    end

    local _, z = label_up:match(TURTLE_LABEL_MATCHER)
    z = tonumber(z)
    if z then
      det_context.debug(("Got position from above: 1, %d."):format(z))
      return 1, z + 1
    end
    error("Could not determine position of turtle in vertical array style (3).", 0)
  end

  det_context.debug("No turtles in front or above, at 1, 1.")

  -- No turtles in front or above.
  return 1, 1
end

--- Determine the position of the turtle in the grid, horizontal style.
--- This entire function is a mess, but I'm unsure how I'd clean it up.
---@return number x The x position of the turtle in the grid.
---@return number z The z position of the turtle in the grid.
local function _determine_horizontal()
  -- Determining the horizontal position is a bit more of a pain.
  -- 1. Check all sides to see if there is a turtle there.
  -- 2. If no turtle is in that direction, turn and check if there is a guide
  --    block there. At most, two sides should be empty.
  -- 3. If a top guideblock is there, then the turtle knows it is at z=1.
  --    a) From there, the turtle should face left and wait until the turtle in
  --       front knows its position, then it is at x+1,1.
  --    b) If a left guideblock is there, then the turtle knows it is at x=1.
  -- 4. If no guideblock, repeat step 3 with any other sides that are empty.
  -- 5. If no sides are empty, continuously check each side until we find a
  --    turtle that knows its position. Must wait for a second turtle to know
  --    its position, then we can extrapolate our position.

  -- Check all sides to see if there is a turtle there.
  local is_turtle_front, label_front = get_turtle_label("front")
  local is_turtle_back, label_back = get_turtle_label("back")
  local is_turtle_left, label_left = get_turtle_label("left")
  local is_turtle_right, label_right = get_turtle_label("right")

  local guideblock_type ---@type "top"|"left"?

  --- Check if a guideblock is in the given direction.
  --- @param override_data table<string, string>? The data to use for the check.
  local function is_guideblock(override_data)
    local is_block, block_data
    if override_data then
      is_block = true
      block_data = override_data
    else
      is_block, block_data = turtle.inspect()
    end

    if is_block then
      if block_data.name == TurmitorClient.guideblock_top then
        guideblock_type = "top"
        return true
      elseif block_data.name == TurmitorClient.guideblock_left then
        guideblock_type = "left"
        return true
      end
    end

    return false
  end

  -- On each empty side, check for a guideblock.

  -- Face the right-most empty side.
  local double = false
  if not is_turtle_front and not is_turtle_left then
    double = true
  elseif not is_turtle_left and not is_turtle_back then
    double = true
    turn_left()
  elseif not is_turtle_back and not is_turtle_right then
    double = true
    turn_left()
    turn_left()
  elseif not is_turtle_right and not is_turtle_front then
    double = true
    turn_right()
  end

  if not double then
    -- Face the only empty side.
    if not is_turtle_front then
      -- nothing, already facing the right way.
    elseif not is_turtle_left then
      turn_left()
    elseif not is_turtle_back then
      turn_left()
      turn_left()
    elseif not is_turtle_right then
      turn_right()
    end
  end

  if is_guideblock() then
    -- Facing a guideblock, are we at the top or left?
    if guideblock_type == "top" then
      -- We are at z=1.
      -- Face left and check if there is a left guideblock.
      turn_left()
      if is_guideblock()then
        -- We are at x=1.
        return 1, 1
      end

      -- if the front is not a guideblock, it should be a turtle.
      if not get_turtle_label("front") then
        error("No turtle in front of the turtle at z=1 while facing left of top guideblock.", 0)
      end

      -- Now we can just wait for that turtle to know its position, and we are
      -- at x+1,1.
      repeat
        sleep(1)
        label_front = peripheral.call("front", "getLabel")
      until label_front and label_front:match(TURTLE_LABEL_MATCHER)

      ---@fixme this is unfinished
    elseif guideblock_type == "left" then
      -- we are at x=1.
      -- Face right and check if there is a top guideblock.
      turn_right()
      if is_guideblock() then
        -- We are at z=1.
        return 1, 1
      end

      -- if the front is not a guideblock, it should be a turtle.
      if not get_turtle_label("front") then
        error("No turtle in front of the turtle at x=1 while facing right of left guideblock.", 0)
      end

      -- Now we can just wait for that turtle to know its position, and we are
      -- at z+1,1.
      repeat
        sleep(1)
        label_front = peripheral.call("front", "getLabel")
      until label_front and label_front:match(TURTLE_LABEL_MATCHER)

      ---@fixme this is unfinished
    else
      error("Guideblock, but no guideblock? Curious. (this should never happen)", 0)
    end
  else
    -- No guideblock, so we need to wait for two turtles to know their position.
    repeat
      sleep(1)
      label_front = peripheral.call("front", "getLabel")
      label_back = peripheral.call("back", "getLabel")
      label_right = peripheral.call("right", "getLabel")
      label_left = peripheral.call("left", "getLabel")

      local known_count = (
        (label_front and label_front:match(TURTLE_LABEL_MATCHER) and 1 or 0) +
        (label_back and label_back:match(TURTLE_LABEL_MATCHER) and 1 or 0) +
        (label_right and label_right:match(TURTLE_LABEL_MATCHER) and 1 or 0) +
        (label_left and label_left:match(TURTLE_LABEL_MATCHER) and 1 or 0)
      )
    until known_count >= 2

    -- Now we can extrapolate our position.
    -- The right-most turtle that knows its position we should take the 'z'
    -- value from, and the left-most turtle we should take the 'x' value from.
    if label_front and label_left then
      local _, z = label_front:match(TURTLE_LABEL_MATCHER)
      local x, _ = label_left:match(TURTLE_LABEL_MATCHER)
      x, z = tonumber(x), tonumber(z)
      if x and z then
        return x, z
      end
    elseif label_left and label_back then
      local _, z = label_left:match(TURTLE_LABEL_MATCHER)
      local x, _ = label_back:match(TURTLE_LABEL_MATCHER)
      x, z = tonumber(x), tonumber(z)
      if x and z then
        return x, z
      end
    elseif label_back and label_right then
      local _, z = label_back:match(TURTLE_LABEL_MATCHER)
      local x, _ = label_right:match(TURTLE_LABEL_MATCHER)
      x, z = tonumber(x), tonumber(z)
      if x and z then
        return x, z
      end
    elseif label_right and label_front then
      local _, z = label_right:match(TURTLE_LABEL_MATCHER)
      local x, _ = label_front:match(TURTLE_LABEL_MATCHER)
      x, z = tonumber(x), tonumber(z)
      if x and z then
        return x, z
      end
    end
    error("Could not extrapolate position from turtles.", 0)
  end

  error("Could not determine position of turtle.", 0)
end

--- Place a block of the given color.
---@param color valid_colors The color of the block to place.
local function place_block(color)
  expect(1, color, "string")

  -- Check if we actually need to change anything first.
  if TurmitorClient.current_color == color then
    return
  end

  -- Get the slot for the color.
  local slot = TurmitorClient.color_map[color]
  if not slot then
    error(("Invalid color specified: %s"):format(color), 0)
  end

  if TurmitorClient.current_color then
    -- Get the slot for the color that is currently placed.
    local slot_current = TurmitorClient.color_map[TurmitorClient.current_color]

    -- Select that slot, then dig the block.
    turtle.select(slot_current)
    if TurmitorClient.array_style == "vertical" then
      turtle.dig()
    else
      turtle.digUp()
    end
  end

  -- Select the slot of the block we want to place.
  turtle.select(slot)

  -- Place the block
  if TurmitorClient.array_style == "vertical" then
    turtle.place()
  else
    turtle.placeUp()
  end

  TurmitorClient.current_color = color
end

--- Queue a block placement using the font data.
---@param char_x number The x position of the character in the font.
---@param char_y number The y position of the character in the font.
---@param fg valid_colors The foreground color of the character.
---@param bg valid_colors The background color of the character.
local function queue_block_using_font(char_x, char_y, fg, bg)
  local used_x = char_x + TurmitorClient.position.inner_x
  local used_y = char_y + TurmitorClient.position.inner_z

  if TurmitorClient.font[used_y] and TurmitorClient.font[used_y][used_x] then
    TurmitorClient.queue_block(fg)
  else
    TurmitorClient.queue_block(bg)
  end
end


--- Coroutine which listens for messages stating what should be placed (or other actions that should be taken).
local function listen_for_actions()
  local client_comms =  logging.create_context("comms")
  client_main.info("Listening for placements.")
  client_main.info(("Control channel: %d | All channel: %d"):format(
    TurmitorClient.control_channel,
    TurmitorChannels.CHANNEL_ALL
  ))

  smn.closeAll()
  smn.open(TurmitorClient.control_channel)
  smn.open(TurmitorChannels.CHANNEL_ALL)

  while true do
    local event, side, _channel, _reply_channel, message = os.pullEvent("modem_message")

    client_comms.debug(("Received message on channel %d."):format(_channel))

    if type(message) == "table" and message._turmitor then
      client_comms.debug(("Received turmitor message (action: %s)."):format(message.action))
      if _channel == TurmitorClient.control_channel then
        if message.action == "character" then
          client_comms.debug("Received character message.")
          queue_block_using_font(
            message.data.char_x,
            message.data.char_y,
            message.data.fg,
            message.data.bg
          )
        elseif message.action == "place-batch" then
          -- Check if this turtle is one of the turtles that should place a
          -- block.
          for _, order in ipairs(message.data.orders) do
            if order.x == TurmitorClient.position.x
              and order.z == TurmitorClient.position.z then
              TurmitorClient.queue_block(order.color)
              client_comms.debug("Order is for us.")
              break
            end
          end
        elseif message.action == "place" then
          -- Check if this is the turtle that is being told to place a block.
          if message.data.x == TurmitorClient.position.x
            and message.data.z == TurmitorClient.position.z then
            TurmitorClient.queue_block(message.data.color)
            client_comms.debug("Order is for us.")
          else
            client_comms.debug("Not for us.")
          end
        end
      elseif _channel == TurmitorChannels.CHANNEL_ALL then
        if message.action == "clear" then
          client_comms.info("Received clear message of color", message.data.color)
          TurmitorClient.queue_block(message.data.color)
        elseif message.action == "reset" then
          client_comms.warn("Received reset message.")
          reset()
        elseif message.action == "get-size" then
          if TurmitorClient.is_bottom_right_corner then
            client_comms.info("Received get-size message, responding.")
            smn.transmit(
              TurmitorChannels.CHANNEL_TURTLE_REPLY,
              TurmitorClient.control_channel,
              {
                _turmitor = true,
                action = "size",
                data = {
                  x = TurmitorClient.position.char_x + 1,
                  z = TurmitorClient.position.char_z + 1
                }
              }
            )
          else
            client_comms.info("Received get-size message, but not in bottom-right corner.")
          end
        end
      end
    end
  end
end

--- "Redraw" coroutine which continuously checks if the turtle needs to place a new colored block.
local function redraw()
  while true do
    while TurmitorClient.color_want do
      local color_want = TurmitorClient.color_want
      TurmitorClient.color_want = nil
      place_block(color_want) ---@diagnostic disable-line: param-type-mismatch - Cannot be nil.
    end

    os.pullEvent("turmitorclient-queue-block")
  end
end

-- Public functions

--- Set the position of the turtle in the grid.
---@param x number The x position of the turtle in the grid.
---@param z number The z (or y) position of the turtle in the grid.
function TurmitorClient.set_position(x, z)
  expect(1, x, "number")
  expect(2, z, "number")

  TurmitorClient.position.x = x
  TurmitorClient.position.z = z
  TurmitorClient.position.char_x = math.floor((x - 1) / 6)
  TurmitorClient.position.char_z = math.floor((z - 1) / 9)
  TurmitorClient.position.inner_x = (x - 1) % 6
  TurmitorClient.position.inner_z = (z - 1) % 9

  client_main.info(("Set position to %d, %d."):format(x, z))
  client_main.info(("--> Char %d, %d; Inner %d, %d."):format(
    TurmitorClient.position.char_x,
    TurmitorClient.position.char_z,
    TurmitorClient.position.inner_x,
    TurmitorClient.position.inner_z
  ))

  TurmitorClient.control_channel = TurmitorChannels.get_client_channel(
    TurmitorClient.position.char_x,
    TurmitorClient.position.char_z
  )
  client_main.info("Will be listening on channel", TurmitorClient.control_channel)

  save()
end

--- Get the position of the turtle in the grid.
---@return number x The x position of the turtle in the grid.
---@return number z The z (or y) position of the turtle in the grid.
function TurmitorClient.get_position()
  return TurmitorClient.position.x, TurmitorClient.position.z
end

--- Determine the position of the turtle in the grid.
function TurmitorClient.determine_position()
  client_main.info("Determining position of the turtle.")

  local x, z

  if TurmitorClient.array_style == "vertical" then
    client_main.info("Vertical array is set up.")
    x, z = _determine_vertical()
  else
    client_main.info("Horizontal array is set up.")
    x, z = _determine_horizontal()
  end

  TurmitorClient.set_position(x, z)
end

--- Queue a block placement.
--- @param color valid_colors The color of the block to place.
function TurmitorClient.queue_block(color)
  TurmitorClient.color_want = color

  -- Queue an event to resume the placement coroutine, if it is ready.
  os.queueEvent("turmitorclient-queue-block")
end

--- Run the Turmitor Client.
function TurmitorClient.run()
  client_main.info("Initializing Turmitor Client.")

  load()
  check_orientation()

  if TurmitorClient.array_style == "horizontal" then
    smn.set_modem("bottom")
  elseif TurmitorClient.array_style == "vertical" then
    smn.set_modem("back")
  end

  setup_font()
  get_blocks()
  determine_bottom_right_corner()

  client_main.info("Initialization complete. Placing black block.")

  -- Ensure that the screen is blank.
  place_block("black")

  client_main.info("Running main loops.")
  if TurmitorClient.is_bottom_right_corner then
    client_main.info("Turtle is in the bottom-right corner.")
  end
  parallel.waitForAny(
    listen_for_actions,
    redraw
  )
end

return TurmitorClient