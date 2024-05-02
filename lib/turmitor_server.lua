--- Server library for the Turmitor array.

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

-- Imports

local expect = require "cc.expect".expect
local TurmitorChannels = require "turmitor_channels"
local smn = require "single_modem_network"
local logging = require "logging"

-- Constants



-- Global variables

local main_context = logging.create_context("turmitor_server")
local inverted_colors = {}
for k, v in pairs(colors) do
  if type(v) == "number" then
    inverted_colors[v] = k
  end
end



-- Type definitions


---@alias BatchPixels PixelData[]

---@class PixelData
---@field x number The x position of the pixel.
---@field y number The y position of the pixel.
---@field color valid_colors The color of the pixel.


---@class TurmitorServer
local TurmitorServer = {
  array_size = {x = 0, z = 0}
}


-- Private methods


--- Send a message to all turtles.
local function send_to_all(action, data)
  main_context.debug("Send action to all turtles:", action)
  smn.transmit(
    TurmitorChannels.CHANNEL_ALL,
    TurmitorChannels.CHANNEL_TURTLE_REPLY,
    {
      action = action,
      data = data,
      _turmitor = true
    }
  )
end

--- Send a message to a specific character of turtles.
local function send_to_character(x, y, action, data)
  main_context.debug("Send action to character:", action, "at", x, y)
  smn.transmit(
    TurmitorChannels.get_client_channel(x, y),
    TurmitorChannels.CHANNEL_TURTLE_REPLY,
    {
      action = action,
      data = data,
      _turmitor = true
    }
  )
end

--- Convert a color from blit to a color that can be used by the turmitor server.
---@param hex string The blit color to convert.
---@return valid_colors? valid_color The converted color, or nil if the color is invalid.
local function from_blit(hex)
  if #hex ~= 1 then return end
  local n = tonumber(hex, 16)
  if not n then return end

  return inverted_colors[2^n]
end


-- Public methods


--- Set the modem to use for communication.
---@param modem_name computerSide The side of the computer the modem is on.
function TurmitorServer.set_modem(modem_name)
  smn.set_modem(modem_name)

  smn.closeAll()
  smn.open(TurmitorChannels.CHANNEL_ERROR)
  smn.open(TurmitorChannels.CHANNEL_TURTLE_REPLY)
end

--- Restart all connected turtles.
---@param shutdown_batch_size number? The number of turtles to shut down at once, defaults to 100.
---@param shutdown_batch_time number? The time to wait between shutting down each batch of turtles, defaults to 5 seconds.
---@param startup_batch_size number? The number of turtles to start at once, defaults to 100.
---@param startup_batch_time number? The time to wait between starting each batch of turtles, defaults to 5 seconds.
function TurmitorServer.restart(shutdown_batch_size, shutdown_batch_time, startup_batch_size, startup_batch_time)
  expect(1, shutdown_batch_size, "number", "nil")
  expect(2, shutdown_batch_time, "number", "nil")
  expect(3, startup_batch_size, "number", "nil")
  expect(4, startup_batch_time, "number", "nil")
  shutdown_batch_size = shutdown_batch_size or 100
  shutdown_batch_time = shutdown_batch_time or 5
  startup_batch_size = startup_batch_size or 100
  startup_batch_time = startup_batch_time or 5

  main_context.info("Restarting all connected turtles.")
  TurmitorServer.shutdown(shutdown_batch_size, shutdown_batch_time)
  sleep(1)
  TurmitorServer.startup(startup_batch_size, startup_batch_time)
end

--- Start all connected turtles.
---@param batch_size number? The number of turtles to start at once, defaults to 100.
---@param batch_time number? The time to wait between starting each batch of turtles, defaults to 5 seconds.
function TurmitorServer.startup(batch_size, batch_time)
  expect(1, batch_size, "number", "nil")
  expect(2, batch_time, "number", "nil")
  batch_size = batch_size or 100
  batch_time = batch_time or 5

  main_context.info("Starting up all connected turtles.")
  local turtles = table.pack(smn.find("turtle"))
  local batches = math.ceil(#turtles / batch_size)
  local batch = 0

  for i = 1, #turtles, batch_size do
    batch = batch + 1
    for j = 1, batch_size do
      local turtle = turtles[i + j - 1]
      if not turtle then
        break
      end

      main_context.debug("Starting up turtle", i + j - 1)
      turtle.turnOn()
    end

    main_context.debug("End of batch", batch, "of", batches, "- waiting", batch_time, "seconds.")
    main_context.debug("ETA:", (batches - batch + 1) * batch_time, "seconds.")

    sleep(batch_time)
  end
end

--- Shutdown all connected turtles.
---@param batch_size number? The number of turtles to shut down at once, defaults to 100.
---@param batch_time number? The time to wait between shutting down each batch of turtles, defaults to 1 second.
function TurmitorServer.shutdown(batch_size, batch_time)
  expect(1, batch_size, "number", "nil")
  expect(2, batch_time, "number", "nil")
  batch_size = batch_size or 100
  batch_time = batch_time or 1

  main_context.info("Shutting down all connected turtles.")
  local turtles = table.pack(smn.find("turtle"))
  local batches = math.ceil(#turtles / batch_size)
  local batch = 0

  for i = 1, #turtles, batch_size do
    batch = batch + 1
    for j = 1, batch_size do
      local turtle = turtles[i + j - 1]
      if not turtle then
        break
      end

      main_context.debug("Shutting down turtle", i + j - 1)
      turtle.shutdown()
    end

    main_context.debug("End of batch", batch, "of", batches, "- waiting", batch_time, "seconds.")
    main_context.debug("ETA:", (batches - batch + 1) * batch_time, "seconds.")

    sleep(batch_time)
  end
end

--- Clear the entire screen with a specified color.
---@param color valid_colors The color to clear the screen with.
function TurmitorServer.clear(color)
  expect(1, color, "string")

  send_to_all(
    "clear",
    {
      color = color
    }
  )
end

--- Have all turtles reset their data.
function TurmitorServer.reset()
  send_to_all("reset", {})
end

--- Send a character to the specified terminal position.
---@param term_x number The x position on the terminal, 1-indexed.
---@param term_y number The y position on the terminal, 1-indexed.
---@param fg valid_colors|color The foreground color of the character.
---@param bg valid_colors|color The background color of the character.
---@param char string The character to display.
function TurmitorServer.set_character(term_x, term_y, fg, bg, char)
  expect(1, term_x, "number")
  expect(2, term_y, "number")
  expect(3, fg, "string", "number")
  expect(4, bg, "string", "number")
  expect(5, char, "string")

  if type(fg) == "number" then
    fg = inverted_colors[fg]
    if not fg then
      error("Invalid color (fg).", 2)
    end
  end

  if type(bg) == "number" then
    bg = inverted_colors[bg]
    if not bg then
      error("Invalid color (bg).", 2)
    end
  end

  if type(colors[fg]) ~= "number" then
    error("Invalid color (fg).", 2)
  end

  if type(colors[bg]) ~= "number" then
    error("Invalid color (bg).", 2)
  end

  -- Determine the position within the font that the character is at.
  local _placement_x, _placement_y = char:byte() % 16, math.floor(char:byte() / 16)
  local placement_x = 2 + 6 * _placement_x + 2 * _placement_x
  local placement_y = 2 + 9 * _placement_y + 2 * _placement_y

  send_to_character(
    term_x - 1,
    term_y - 1,
    "character",
    {
      offset_x = placement_x,
      offset_y = placement_y,
      fg = fg,
      bg = bg
    }
  )
end

--- Send an update to a single pixel.
---@param x number The x position of the pixel, 1-indexed.
---@param y number The y position of the pixel, 1-indexed.
---@param color valid_colors The color to set the pixel to.
function TurmitorServer.set_pixel(x, y, color)
  expect(1, x, "number")
  expect(2, y, "number")
  expect(3, color, "string")

  -- Determine the character position the pixel is at.
  local char_x, char_y = math.floor((x - 1) / 6), math.floor((y - 1) / 9)

  send_to_character(
    char_x,
    char_y,
    "place",
    {
      x = x,
      z = y,
      color = color
    }
  )
end

--- Send an update to a batch of pixels. This method is not recommended if making only small changes, as it triggers every single turtle to update regardless of what is being changed.
---@param pixels BatchPixels The table of pixels to update.
function TurmitorServer.set_pixels(pixels)
  expect(1, pixels, "table")

  ---@fixme add method to send messages to only specific turtles (on both sender and receiver side)

  send_to_all(
    "place-batch",
    {
      orders = pixels
    }
  )
end

--- Get the size of the array. We need to wait for a response from the bottom-right-most turtle, so this method may take some time. Returns 0,0 on timeout.
---@param max_time number? The maximum time to wait for a response, defaults to 5 seconds.
---@return number x The x size of the array.
---@return number z The z size of the array.
function TurmitorServer.get_size(max_time)
  expect(1, max_time, "number", "nil")
  max_time = max_time or 5

  local getsize_context = logging.create_context("get_size")
  getsize_context.info("Getting size of the array.")

  local _, response

  parallel.waitForAny(
    function()
      -- Loop sending the request.
      while true do
        getsize_context.debug("Sending size request.")
        smn.transmit(
          TurmitorChannels.CHANNEL_ALL,
          TurmitorChannels.CHANNEL_TURTLE_REPLY,
          {
            action = "get-size",
            _turmitor = true
          }
        )

        sleep(1) -- resent every second to ensure a response is received.
      end
    end,
    function()
      -- Loop receiving the response.
      local modem = smn.get_modem()

      while true do
        local _, side, _, _, message = os.pullEvent("modem_message")

        getsize_context.debug("Received message:", message)

        if side == modem and type(message) == "table" and message._turmitor and message.action == "size" then
          getsize_context.info("Received size response.")
          response = message.data
          break
        end
      end
    end,
    function()
      sleep(max_time)
      response = {}
    end
  )

  if response.x and response.z then
    getsize_context.info("Received size:", response.x, response.z, "(", response.actual_x, response.actual_z, ")")
    TurmitorServer.array_size.x = response.x
    TurmitorServer.array_size.z = response.z
  else
    getsize_context.warn("Did not receive size response.")
  end

  return response.x or 0, response.z or 0
end

--- Get the size of the array. This method will return the cached value if it exists, instead of requesting a new value. Returns 0,0 if the cached value does not exist.
---@return number x The x size of the array.
---@return number z The z size of the array.
function TurmitorServer.get_size_cached()
  return TurmitorServer.array_size.x, TurmitorServer.array_size.z
end

--- Listen for turtle errors. This method is meant to be used in parallel with
--- your main program, mainly for logging purposes. It is NOT required to be run
--- at all, but if any turtles error this will let you know from the controller.
---
--- This method assumes you have called `TurmitorServer.set_modem`.
---@see TurmitorServer.set_modem
function TurmitorServer.listen_for_errors()
  local error_context = logging.create_context("error_listener")

  local modem_name = smn.get_modem()

  while true do
    local _, side, _, _, message = os.pullEvent("modem_message")

    if side == modem_name and type(message) == "table"
    and message._turmitor and message.action == "error" then
      error_context.error("Turtle error:", message.message)
      error_context.error("      Turtle:", message.turtle_id)
      error_context.error("  Local name:", message.local_name)
    end
  end
end

--- Steal items from the turtles and put them in available inventories.
---
--- If `item_lookup`, `chest_lookup`, and `buffer_chest` are provided, the items
--- will be stolen and placed in the chests according to the lookup tables. If
--- they are not provided, the items will be stolen and placed in the first
--- available chest.
---@param item_lookup table<string, valid_colors>? A table of item names to colors.
---@param chest_lookup table<valid_colors, string[]>? A table of colors to chest names.
---@param buffer_chest string? The name of the buffer chest to use.
---@param no_freeze boolean? If true, the turtles will not be frozen before stealing items. This removes some of the wait time, and is mostly useful if you can ensure that nothing will be drawn to the screen during the stealing process.
function TurmitorServer.steal_items(item_lookup, chest_lookup, buffer_chest, no_freeze)
  expect(1, item_lookup, "table", "nil")
  expect(2, chest_lookup, "table", "nil")
  expect(3, buffer_chest, "string", "nil")

  local function _notify_turtles()
    if not no_freeze then
      -- Freeze the turtles to ensure nothing is attempting to draw.
      send_to_all("freeze", {})

      -- Wait a short bit to ensure nothing is attempting to draw.
      sleep(3)
    end


    -- Order turtles to pick up the currently placed block.
    send_to_all("pickup", {})

    main_context.info("Notification was sent to turtles to pick up their blocks.")
    main_context.info("Waiting 3 seconds for turtles to pick up their blocks.")
    sleep(3)
  end

  if item_lookup then
    -- Steal items and place them in the chests according to the lookup tables.
    main_context.debug("Item lookup provided, will be attempting to sort.")

    if not chest_lookup or not buffer_chest then
      error("If item_lookup is provided, chest_lookup and buffer_chest must also be provided.", 2)
    end

    -- Stage one: Ensure a chest exists for each color.
    for _, color in pairs(item_lookup) do
      if not chest_lookup[color] then
        error("No chest found for color: " .. color, 2)
      end
    end

    -- Stage two: Ensure all chests *exist* on the network.
    for _, chest_names in pairs(chest_lookup) do
      for _, chest_name in ipairs(chest_names) do
        if not smn.isPresent(chest_name) then
          error("Chest not found: " .. chest_name, 2)
        end
      end
    end
    if not smn.isPresent(buffer_chest) then
      error("Buffer chest not found: " .. buffer_chest, 2)
    end
    local size = smn.call(buffer_chest, "size")
    if size < 16 then
      error("Buffer chest is too small (Need at least 16 slots).", 2)
    end

    -- All error cases should be dealt with.
    _notify_turtles()

    local function sort_buffer()
      main_context.debug("Sorting buffer chest.")
      local list = smn.call(buffer_chest, "list")
      local funcs = {}

      for slot, item in pairs(list) do
        local color = item_lookup[item.name]
        if color then
          local chests = chest_lookup[color]
          local pushed = 0

          table.insert(funcs, function()
            for i = 1, #chests do
              local pushed_this_time = smn.call(chests[i], "pushItems", buffer_chest, slot)
              pushed = pushed + pushed_this_time
              if pushed >= item.count then
                break
              end
            end
          end)
        end
      end
    end

    -- Stage three: Become thief.
    local turtles = table.pack(smn.find("turtle"))
    local turtle_names = {}
    for _, turtle in ipairs(turtles) do
      table.insert(turtle_names, peripheral.getName(turtle))
    end

    -- Quickly just ensure the buffer chest is empty.
    sort_buffer()

    for i, turtle_name in ipairs(turtle_names) do
      main_context.debug("Stealing from turtle", i, ":", turtle_name)
      -- Step 1: Dump all items from this turtle into the buffer chest.
      local funcs = {}

      for j = 1, 16 do
        table.insert(funcs, function()
          smn.call(buffer_chest, "pullItems", turtle_name, j)
        end)
      end

      parallel.waitForAll(table.unpack(funcs))

      -- Step 2: Sort all items from the buffer chest into the correct chests.
      sort_buffer()
    end
  else
    -- Just dump all items into the first available chest.
    local turtles = table.pack(smn.find("turtle"))
    local invs = table.pack(smn.find("inventory"))

    _notify_turtles()

    for i, turtle in ipairs(turtles) do
      main_context.debug("Stealing from turtle", i, ":", peripheral.getName(turtle))

      local funcs = {}

      for j = 1, 16 do
        table.insert(funcs, function()
          for _, inv in ipairs(invs) do
            if inv.pullItems(peripheral.getName(turtle), j) > 0 then
              break
            end
          end
        end)
      end

      parallel.waitForAll(table.unpack(funcs))
    end
  end

  if not no_freeze then
    -- Unfreeze the turtles.
    send_to_all("thaw", {})
  end
end

--- Get an object that can be used like a terminal object (i.e: for `term.redirect`).
---@return TurmitorRedirect redirect The window-like redirect object.
function TurmitorServer.get_redirect()
  return require "server.redirect"
end

--- Get an object that can be used for drawing pixel-graphics to the screen.
---@return TurmitorGraphics graphics The graphics object.
function TurmitorServer.get_graphical_interface()
  return require "server.graphics"
end

return TurmitorServer