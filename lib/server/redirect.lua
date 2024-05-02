--- A redirect object that can be used to draw text to the screen.

local TurmitorServer = require "turmitor_server"

local inverted_colors = {}
for k, v in pairs(colors) do
  if type(v) == "number" then
    inverted_colors[v] = k
  end
end

--- Convert a color from blit to a color that can be used by the turmitor server.
---@param hex string The blit color to convert.
---@return valid_colors? valid_color The converted color, or nil if the color is invalid.
local function from_blit(hex)
  if #hex ~= 1 then return end
  local n = tonumber(hex, 16)
  if not n then return end

  return inverted_colors[2 ^ n]
end

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
local size = { x = 0, y = 0 }
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
      buffer_1[y][x] = { char = " ", fg = colors.white, bg = colors.black }
      buffer_2[y][x] = { char = " ", fg = colors.white, bg = colors.black }
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
    buffer_1[order.y][order.x] = { char = order.char, fg = order.fg, bg = order.bg }
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
      buffer_1[y][x] = { char = " ", fg = text_color, bg = background_color }
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
    buffer_1[cursor_y][x] = { char = " ", fg = text_color, bg = background_color }
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
      new_buffer[y][x] = { char = " ", fg = text_color, bg = background_color }
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
        TurmitorServer.set_character(cursor_x + i - 1, cursor_y, inverted_colors[text_color],
          inverted_colors[background_color], value:sub(i, i))
      end
    end
  end

  -- update the buffer.
  for i = 1, #value do
    local x_pos = cursor_x + i - 1
    if x_pos <= size.x and x_pos > 0 then
      buffer_1[cursor_y][x_pos] = { char = value:sub(i, i), fg = text_color, bg = background_color }
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
  if visible and not auto_update then
    -- If we're turning on auto update, we need to redraw.
    flush_buffers()
  end

  auto_update = visible
end

--- Disable automatic updates.
function redirect.isVisible()
  return auto_update
end

return redirect
