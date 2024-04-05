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


-- Public methods


--- Set the modem to use for communication.
---@param modem_name computerSide The side of the computer the modem is on.
function TurmitorServer.set_modem(modem_name)
  smn.set_modem(modem_name)
end

--- Restart all connected turtles.
function TurmitorServer.restart()
  main_context.info("Restarting all connected turtles.")
  TurmitorServer.shutdown()
  sleep(1)
  TurmitorServer.startup()
end

--- Start all connected turtles.
function TurmitorServer.startup()
  main_context.info("Starting up all connected turtles.")
  local turtles = table.pack(smn.find("turtle"))

  for i, turtle in ipairs(turtles) do
    main_context.debug("Starting up turtle", i)
    turtle.turnOn()
  end
end

--- Shutdown all connected turtles.
function TurmitorServer.shutdown()
  main_context.info("Shutting down all connected turtles.")
  local turtles = table.pack(smn.find("turtle"))

  for i, turtle in ipairs(turtles) do
    main_context.debug("Shutting down turtle", i)
    turtle.turnOff()
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
  local char_x, char_y = char:byte() % 16, math.floor(char:byte() / 16)
  local placement_x = 2 + 6 * char_x + 2 * char_x
  local placement_y = 2 + 9 * char_y + 2 * char_y

  send_to_character(
    term_x - 1,
    term_y - 1,
    "character",
    {
      char_x = placement_x,
      char_y = placement_y,
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

  local _, response

  parallel.waitForAny(
    function()
      -- Loop sending the request.
      while true do
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

        if side == modem and type(message) == "table" and message._turmitor and message.action == "size" then
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
    TurmitorServer.array_size.x = response.x
    TurmitorServer.array_size.z = response.z
  end

  return response.x or 0, response.z or 0
end

--- Get the size of the array. This method will return the cached value if it exists, instead of requesting a new value. Returns 0,0 if the cached value does not exist.
---@return number x The x size of the array.
---@return number z The z size of the array.
function TurmitorServer.get_size_cached()
  return TurmitorServer.array_size.x, TurmitorServer.array_size.z
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

  --- If this boolean is true, the next redraw will force a full screen update
  --- instead of computing the differences between the two buffers.
  local buffers_dirty = false

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

    buffers_dirty = true
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
  function redirect.blit(text, textColor, backgroundColor)
    expect(1, text, "string")
    expect(2, textColor, "string")
    expect(3, backgroundColor, "string")

    -- Ensure all inputs are the same length
    if #textColor ~= #text or #backgroundColor ~= #text then
      error("All inputs must be the same length.", 2)
    end

    -- Skeleton
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

  --- Scroll the screen. Positive scrolls up, negative scrolls down.
  function redirect.scroll(lines)
    expect(1, lines, "number")

    -- Compute the new buffer.
    local new_buffer = {}

    -- initialization
    for x = 1, size.x do
      new_buffer[x] = {}

      for z = 1, size.y do
        new_buffer[x][z] = {char = " ", fg = text_color, bg = background_color}
      end
    end

    -- copy the old buffer to the new buffer, with the y offset.
    for x = 1, size.x do
      for z = 1, size.y do
        local new_z = z + lines
        if new_z > 0 and new_z <= size.y then
          new_buffer[x][new_z] = buffer_1[x][z]
        end
      end
    end

    if auto_update then
      -- immediately order the scroll.
      for x = 1, size.x do
        for z = 1, size.y do
          local char = new_buffer[x][z]
          TurmitorServer.set_character(x, z, inverted_colors[char.fg], inverted_colors[char.bg], char.char)
        end
      end
    end

    -- update the buffer.
    buffer_1 = new_buffer
  end

  --- Set the background color.
  function redirect.setBackgroundColor(color)
    expect(1, color, "number")

    background_color = color
  end
  redirect.setBackgroundColour = redirect.setBackgroundColor

  --- Set the text color.
  function redirect.setTextColor(color)
    expect(1, color, "number")

    text_color = color
  end
  redirect.setTextColour = redirect.setTextColor

  --- Set the cursor position.
  function redirect.setCursorPos(x, y)
    expect(1, x, "number")
    expect(2, y, "number")

    cursor_x = math.floor(x)
    cursor_y = math.floor(y)
  end

  --- Write text to the screen.
  function redirect.write(text)
    expect(1, text, "string")

    if cursor_x > size.x or cursor_y > size.y or cursor_y < 1 then
      -- Nothing needs to be updated, cursor is off screen.
      -- Note we don't compare cursor_x < 1, as it's possible to have the cursor
      -- be off to the left of the screen and have text that eventually runs
      -- back onto the screen.
      return
    end

    if auto_update then
      -- immediately order the text to be written.
      for i = 1, #text do
        local x_pos = cursor_x + i - 1
        if x_pos <= size.x and x_pos > 0 then
          TurmitorServer.set_character(cursor_x + i - 1, cursor_y, inverted_colors[text_color], inverted_colors[background_color], text:sub(i, i))
        end
      end
    end

    -- update the buffer.
    for i = 1, #text do
      local x_pos = cursor_x + i - 1
      if x_pos <= size.x and x_pos > 0 then
        buffer_1[cursor_y][x_pos] = {char = text:sub(i, i), fg = text_color, bg = background_color}
      end
    end

    -- Update the cursor position to the end of the text.
    cursor_x = cursor_x + #text
  end

  --- Get the cursor blink state.
  function redirect.getCursorBlink()
    return cursor_blink
  end

  --- Set the cursor blink state.
  function redirect.setCursorBlink(blink)
    expect(1, blink, "boolean")

    cursor_blink = blink
  end

  --- Flush the buffer to the screen.
  function redirect.flush()
    flush_buffers()
  end

  --- Force updates on every call, instead of when flush is called.
  function redirect.auto_update()
    auto_update = true
  end

  return redirect
end

return TurmitorServer