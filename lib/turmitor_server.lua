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
    getsize_context.info("Received size:", response.x, response.z)
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
  --[[ The following methods need to be implemented in our fake window.
    x.blit
    x.clear
    x.clearLine
    x.getBackgroundColor
    x.getBackgroundColour
    x.getCursorPos
    x.getSize
    x.getTextColor
    x.getTextColour
    x.isColor --> Always return true? We may be able to make a b&w or grayscale mode?
    x.scroll
    x.setBackgroundColor
    x.setBackgroundColour
    x.setCursorPos
    x.setTextColor
    x.setTextColour
    x.write
    
    x.getCursorBlink --> We will need to implement something for cursor blink!
    --> x.setCursorBlink
    --> x.getCursorBlink
    
    For setVisible/etc: Do we want to cache what currently exists, or should
    we assume the user will handle that by placing a `window` object on top of
    the redirect object? Perhaps we just return a window object on top of this?
    --> x.setVisible
    --> x.isVisible
    --> x.getLine
    --> x.redraw
    ]]

  ---@class TurmitorRedirect
  local redirect = {}

  --- Buffer layer 1: All current changes are made to this buffer, but nothing
  --- here is drawn to the screen.
  local buffer_1 = {}

  --- Buffer layer 2: When `.flush()` is called, buffer layer 1 is compared with
  --- this buffer, and only the differences are drawn to the screen. This buffer
  --- is then updated with the new contents.
  local buffer_2 = {}

  --- If this is true, instead of waiting for `.flush()` to be called, the
  --- screen will be updated on every call to a drawing function. Only buffer 1
  --- is used in this mode, so that we can do operations like scrolling.
  local auto_update = false

  --- The current cursor position.
  local cursor_x, cursor_y = 1, 1

  --- The size of the screen.
  local size = {x = 0, y = 0}
  size.x, size.y = TurmitorServer.get_size()

  --- The text color.
  local text_color = colors.white

  --- The background color.
  local background_color = colors.black

  --- Cursor blink state.
  local cursor_blink = false


  --- Set up the buffers.
  local function setup_buffers()
    for y = 1, size.y do
      buffer_1[y] = {}
      buffer_2[y] = {}

      for x = 1, size.x do
        buffer_1[y][x] = {char = " ", fg = colors.white, bg = colors.black}
        buffer_2[y][x] = {char = " ", fg = colors.white, bg = colors.black}
      end
    end
  end
  setup_buffers()

  --- Flush the buffers to the screen.
  local function flush_buffers()
    local diffs = {}

    for y = 1, size.y do
      local Ys_1 = buffer_1[y]
      local Ys_2 = buffer_2[y]
      for x = 1, size.x do
        local char_1 = Ys_1[x]
        local char_2 = Ys_2[x]
        if char_1.char ~= char_2.char or char_1.fg ~= char_2.fg or char_1.bg ~= char_2.bg then
          -- insert the difference into the diffs table.
          table.insert(diffs, {
            y = y,
            x = x,
            char = char_1.char,
            fg = char_1.fg,
            bg = char_1.bg
          })

          -- and update layer 2 buffer.
          char_2.char = char_1.char
          char_2.fg = char_1.fg
          char_2.bg = char_1.bg
        end
      end
    end

    -- For each difference, queue up a message to send to the turtles.
    for _, diff in ipairs(diffs) do
      TurmitorServer.set_character(diff.x, diff.y, diff.fg, diff.bg, diff.char)
    end
  end


  --- Blit multiple characters and colors at once to the screen.
  ---@param text string The text to blit.
  ---@param _text_color string The text color string.
  ---@param _background_color string The background color string.
  ---@deprecated Not actually deprecated, but this method is not yet implemented and I want LLS to generate a warning if it gets used.
  function redirect.blit(text, _text_color, _background_color)
    expect(1, text, "string")
    expect(2, _text_color, "string")
    expect(3, _background_color, "string")

    -- Ensure all inputs are the same length
    if #_text_color ~= #text or #_background_color ~= #text then
      error("All inputs must be the same length.", 2)
    end

    if cursor_x > size.x or cursor_y > size.y or cursor_y < 1 then
      -- Nothing needs to be updated, cursor is off screen.
      -- Note we don't compare cursor_x < 1, as it's possible to have the cursor
      -- be off to the left of the screen and have text that eventually runs
      -- back onto the screen.

      -- HOWEVER, we should still offset the cursor to the right by the length
      -- of the text. I don't see any point where someone's could would *rely*
      -- on this behaviour, but... it's possible.
      cursor_x = cursor_x + #text
      return
    end

    -- Convert all inputs to lowercase, so users can use any case.
    _text_color = _text_color:lower()
    _background_color = _background_color:lower()

    local orders = {}

    for i = 1, #text do
      -- Convert current text color and background color from blit.
      local fg = from_blit(_text_color:sub(i, i))
      local bg = from_blit(_background_color:sub(i, i))

      -- From some short analysis, it looks like this is how blit is treated
      -- when given a character that isn't hex.
      -- Not sure if this is exactly how it works, but until someone yells at me
      -- for doing it wrong, this will be how it be.
      if not fg then
        fg = "white"
      end
      if not bg then
        bg = "black"
      end

      -- Add the order to the orders table, but only if on screen.
      local x_pos = cursor_x + i - 1
      if x_pos <= size.x and x_pos > 0 then
        table.insert(orders, {
          x = x_pos,
          y = cursor_y,
          fg = fg,
          bg = bg,
          char = text:sub(i, i)
        })
      end
    end

    if auto_update then
      -- For each order, set the character.
      for _, order in ipairs(orders) do
        TurmitorServer.set_character(order.x, order.y, order.fg, order.bg, order.char)
      end
    end

    -- Update the buffer with the new characters.
    for _, order in ipairs(orders) do
      buffer_1[order.y][order.x] = {char = order.char, fg = order.fg, bg = order.bg}
    end

    -- Update the cursor position.
    cursor_x = cursor_x + #text
  end

  --- Clear the screen.
  function redirect.clear()
    if auto_update then
      -- immediately order a clear of the current background color.
      TurmitorServer.clear(inverted_colors[background_color])
    end

    -- Set all characters in the buffer to the background color.
    for y = 1, size.y do
      for x = 1, size.x do
        buffer_1[y][x] = {char = " ", fg = text_color, bg = background_color}
      end
    end
  end

  --- Clear a line.
  function redirect.clearLine()
    if auto_update then
      -- Immediately order all characters along the given y position to be cleared.
      for x = 1, size.x do
        TurmitorServer.set_character(x, cursor_y, inverted_colors[text_color], inverted_colors[background_color], " ")
      end
    end

    -- Set all characters along the given y position to the background color.
    for x = 1, size.x do
      buffer_1[cursor_y][x] = {char = " ", fg = text_color, bg = background_color}
    end
  end

  --- Get the background color.
  function redirect.getBackgroundColor()
    return background_color
  end
  redirect.getBackgroundColour = redirect.getBackgroundColor

  --- Get the text color.
  function redirect.getTextColor()
    return text_color
  end
  redirect.getTextColour = redirect.getTextColor

  --- Get the cursor position.
  function redirect.getCursorPos()
    return cursor_x, cursor_y
  end

  --- Get the size of the screen.
  function redirect.getSize()
    return size.x, size.y
  end

  --- Check if the terminal supports color, currently always returns true.
  function redirect.isColor()
    return true
  end
  redirect.isColour = redirect.isColor

  --- Scroll the screen. Positive scrolls up, negative scrolls down.
  ---@param lines number The number of lines to scroll.
  function redirect.scroll(lines)
    expect(1, lines, "number")

    -- Compute the new buffer.
    local new_buffer = {}

    -- initialization
    for y = 1, size.y do
      new_buffer[y] = {}

      for x = 1, size.x do
        new_buffer[y][x] = {char = " ", fg = text_color, bg = background_color}
      end
    end

    -- copy the old buffer to the new buffer, with the y offset.
    if lines > 0 then
      for y = 1, size.y do
        local new_y = y - lines
        local buf_y = {}
        new_buffer[new_y] = buf_y
        for x = 1, size.x do
          if new_y >= 1 and new_y <= size.y then
            local buf_char = {}
            buf_y[x] = buf_char

            buf_char.char = buffer_1[y][x].char
            buf_char.fg = buffer_1[y][x].fg
            buf_char.bg = buffer_1[y][x].bg
          end
        end
      end
    else
      for y = size.y, 1, -1 do
        local new_y = y - lines
        local buf_y = {}
        new_buffer[new_y] = buf_y
        for x = 1, size.x do
          if new_y >= 1 and new_y <= size.y then
            local buf_char = {}
            buf_y[x] = buf_char

            buf_char.char = buffer_1[y][x].char
            buf_char.fg = buffer_1[y][x].fg
            buf_char.bg = buffer_1[y][x].bg
          end
        end
      end
    end

    if auto_update then
      -- immediately order the scroll.
      for y = 1, size.y do
        for x = 1, size.x do
          local char = new_buffer[y][x]
          TurmitorServer.set_character(x, y, inverted_colors[char.fg], inverted_colors[char.bg], char.char)
        end
      end
    end

    -- update the buffer.
    buffer_1 = new_buffer
  end

  --- Set the background color.
  ---@param color color The color to set the background to.
  function redirect.setBackgroundColor(color)
    expect(1, color, "number")

    background_color = color
  end
  redirect.setBackgroundColour = redirect.setBackgroundColor

  --- Set the text color.
  ---@param color color The color to set the text to.
  function redirect.setTextColor(color)
    expect(1, color, "number")

    text_color = color
  end
  redirect.setTextColour = redirect.setTextColor

  --- Set the cursor position.
  ---@param x number The x position of the cursor.
  ---@param y number The y position of the cursor.
  function redirect.setCursorPos(x, y)
    expect(1, x, "number")
    expect(2, y, "number")

    cursor_x = math.floor(x)
    cursor_y = math.floor(y)
  end

  --- Write text to the screen.
  ---@param value any The value to write to the screen.
  function redirect.write(value)
    value = tostring(value)

    if cursor_x > size.x or cursor_y > size.y or cursor_y < 1 then
      -- Nothing needs to be updated, cursor is off screen.
      -- Note we don't compare cursor_x < 1, as it's possible to have the cursor
      -- be off to the left of the screen and have text that eventually runs
      -- back onto the screen.

      -- HOWEVER, we should still offset the cursor to the right by the length
      -- of the text. I don't see any point where someone's could would *rely*
      -- on this behaviour, but... it's possible.
      cursor_x = cursor_x + #value
      return
    end

    if auto_update then
      -- immediately order the text to be written.
      for i = 1, #value do
        local x_pos = cursor_x + i - 1
        if x_pos <= size.x and x_pos > 0 then
          TurmitorServer.set_character(cursor_x + i - 1, cursor_y, inverted_colors[text_color], inverted_colors[background_color], value:sub(i, i))
        end
      end
    end

    -- update the buffer.
    for i = 1, #value do
      local x_pos = cursor_x + i - 1
      if x_pos <= size.x and x_pos > 0 then
        buffer_1[cursor_y][x_pos] = {char = value:sub(i, i), fg = text_color, bg = background_color}
      end
    end

    -- Update the cursor position to the end of the text.
    cursor_x = cursor_x + #value
  end

  --- Get the cursor blink state.
  function redirect.getCursorBlink()
    return cursor_blink
  end

  --- Set the cursor blink state.
  ---@param blink boolean Whether or not the cursor should blink.
  function redirect.setCursorBlink(blink)
    expect(1, blink, "boolean")

    cursor_blink = blink
  end

  --- Flush the buffer to the screen.
  function redirect.redraw()
    flush_buffers()
  end

  --- Force updates on every call, instead of when flush is called.
  ---@param visible boolean Whether or not to automatically update the screen.
  function redirect.setVisible(visible)
    auto_update = visible
  end

  --- Disable automatic updates.
  function redirect.isVisible()
    return auto_update
  end

  return redirect
end

return TurmitorServer