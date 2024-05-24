--- Graphics library for the turmitor server.

local TurmitorServer = require "turmitor_server"
local graphics = require "server.graphics.graphics"

local inverted_colors = {}
for k, v in pairs(colors) do
  if type(v) == "number" then
    inverted_colors[v] = k
  end
end

--- Convert a color from blit to a color that can be used by the turmitor server.
---@param hex string The blit color to convert.
---@return color? valid_color The converted color, or nil if the color is invalid.
local function from_blit(hex)
  if #hex ~= 1 then return end
  local n = tonumber(hex, 16)
  if not n then return end

  return inverted_colors[2 ^ n]
end

---@class line_data
---@field text string[] The characters of the line.
---@field fg string[] The foreground colors of the line, in blit format. A space means the color is transparent.
---@field bg string[] The background colors of the line, in blit format. A space means the color is transparent.

---@class frame
---@field duration number? The number of seconds this frame should be displayed.
---@field palette table<color, integer> The palette of the frame, mapping color indices to hexadecimal colors. Overrides the global palette.
---@field data line_data[] The data of the frame.

---@class image
---@field type string The original type of the image file, like "bimg".
---@field version string The version of the image file, in semver format.
---@field animated boolean Whether the image file is animated.
---@field secondsPerFrame number? The number of seconds each frame should be displayed, required if `animated` is true.
---@field author string? The author of the image file.
---@field description string? A description of the image file, set by the author.
---@field creator string? The program or software that created the image file.
---@field date string? The date the image file was created, ISO-8601 format.
---@field width integer The width of the image, in characters.
---@field height integer The height of the image, in characters.
---@field palette table<color, integer>? The palette of the image, mapping color indices to hexadecimal colors.
---@field frames frame[] The frames of the image.

---@class turmitor_graphics_object : graphics_object
---@field delete fun() Deletes the object from the pre-buffer.

---@class TurmitorGraphics
local turmitor_graphics = {}

--- The pre-buffer stores active objects, like sprites, that are not yet
--- actually flushed to buffer 1. This allows for simple movement of sprites
--- without having to redraw the entire screen.
---
--- The pre-buffer is a list of tables, where each table is a sprite, or pixel
--- information.
---@type turmitor_graphics_object[]
local pre_buffer = {}

--- Buffer layer 1: All current changes are made to this buffer, but nothing
--- here is drawn to the screen.
---@type color[][]
local buffer_1 = {}

--- Buffer layer 2: When `.flush()` is called, buffer layer 1 is compared with
--- this buffer, and only the differences are drawn to the screen. This buffer
--- is then updated with the new contents.
---@type color[][]
local buffer_2 = {}

--- If this is true, the screen will be updated after every change.
local auto_update = false

--- The size of the screen.
local size = { x = 0, y = 0 }
local _
_, _, size.x, size.y = TurmitorServer.get_size()

--- Sort everything in the pre-buffer by their draw order.
local function sort_pre_buffer()
  table.sort(pre_buffer, function(a, b)
    return a.draw_order < b.draw_order
  end)
end

--- Draw a graphics object to the first buffer.
---@param object graphics_object The object to draw.
local function draw(object)
  if object.enabled and graphics[object.type] then
    graphics[object.type](object, buffer_1)
  end
end

--- Merge the pre-buffer down from many sprite objects and pixel datum to a
--- single buffer.
local function merge_down()
  sort_pre_buffer()

  for _, object in ipairs(pre_buffer) do
    draw(object)
  end
end

--- Flush the differences of the first buffer to the screen, and update the
--- second buffer.
local function flush()
  ---@type BatchPixels
  local changes = {}

  for y = 1, size.y do
    for x = 1, size.x do
      if buffer_1[y][x] ~= buffer_2[y][x] then
        changes[#changes + 1] = { x = x, y = y, color = buffer_1[y][x] }
        buffer_2[y][x] = buffer_1[y][x]
      end
    end
  end

  TurmitorServer.set_pixels(changes)
end

--- Update the screen.
local function update_screen()
  merge_down()
  flush()
end

--#region Graphics object metatable

--- Graphics object metatable.
local turmitor_graphics_object_mt = {}

local function delete(self)
  for i, object in ipairs(pre_buffer) do
    if object == self then
      table.remove(pre_buffer, i)
      break
    end
  end
end

--- Index metamethod for the graphics object metatable.
--- Allows for getting `x1` and `y1` as aliases for `x` and `y`.
function turmitor_graphics_object_mt.__index(self, key)
  if key == "delete" then
    return delete
  end

  if key == "x1" then
    return self.x
  end

  if key == "y1" then
    return self.y
  end
end

--- Newindex metamethod for the graphics object metatable.
--- Allows for setting `x1` and `y1` as aliases for `x` and `y`.
function turmitor_graphics_object_mt.__newindex(self, key, value)
  if key == "x1" then
    self.x = value
  end

  if key == "y1" then
    self.y = value
  end
end

--#endregion

--- Create a new graphics object (inject the metatable and add it to the
--- pre-buffer).
---@param object graphics_object The object to create.
---@return turmitor_graphics_object object The created object.
local function create(object)
  setmetatable(object, turmitor_graphics_object_mt)

  ---@cast object turmitor_graphics_object

  pre_buffer[#pre_buffer + 1] = object
  return object
end

--- Set the size of the screen. Warning: this method instantly clears the
--- screen, no matter what you have set `auto_update` to.
---@param x integer The width of the screen.
---@param y integer The height of the screen.
function turmitor_graphics.set_size(x, y)
  size.x = x
  size.y = y

  buffer_1 = graphics.init_buffer(x, y)
  buffer_2 = graphics.init_buffer(x, y)
  TurmitorServer.clear(colors.black)
end

--- Get the size of the screen.
---@return integer x The width of the screen.
---@return integer y The height of the screen.
function turmitor_graphics.get_size()
  return size.x, size.y
end

--- Set the auto-update setting. If this is true, the screen will be updated
--- after every change.
---@param enabled boolean Whether to enable auto-update.
function turmitor_graphics.set_auto_update(enabled)
  auto_update = enabled
end

--- Get the auto-update setting.
---@return boolean enabled Whether auto-update is enabled.
function turmitor_graphics.get_auto_update()
  return auto_update
end

--- Draw a pixel to the screen.
---@param x integer The x-coordinate of the pixel.
---@param y integer The y-coordinate of the pixel.
---@param color color The color of the pixel.
---@return turmitor_graphics_object|graphics_object-pixel object The created pixel object.
function turmitor_graphics.pixel(x, y, color)
  local object = create {
    type = "pixel",
    x = x,
    y = y,
    color = color,
    draw_order = 0,
    enabled = true
  }
  ---@cast object +graphics_object-pixel

  if auto_update then
    update_screen()
  end

  return object
end

--- Draw a line to the screen.
---@param x1 integer The x-coordinate of the start of the line.
---@param y1 integer The y-coordinate of the start of the line.
---@param x2 integer The x-coordinate of the end of the line.
---@param y2 integer The y-coordinate of the end of the line.
---@param color color The color of the line.
---@param thickness integer? The thickness of the line. Defaults to 1.
---@return turmitor_graphics_object|graphics_object-line object The created line object.
function turmitor_graphics.line(x1, y1, x2, y2, color, thickness)
  local object = create {
    type = "line",
    x = x1,
    y = y1,
    x2 = x2,
    y2 = y2,
    color = color,
    thickness = thickness or 1,
    draw_order = 0,
    enabled = true
  }
  ---@cast object +graphics_object-line

  if auto_update then
    update_screen()
  end

  return object
end

--- Draw a rectangle to the screen.
---@param x integer The x-coordinate of the top-left corner of the rectangle.
---@param y integer The y-coordinate of the top-left corner of the rectangle.
---@param width integer The width of the rectangle.
---@param height integer The height of the rectangle.
---@param color color The color of the rectangle.
---@param thickness integer? The thickness of the rectangle. Defaults to 1.
---@param filled boolean? Whether the rectangle should be filled. Defaults to false.
---@return turmitor_graphics_object|graphics_object-rectangle object The created rectangle object.
function turmitor_graphics.rectangle(x, y, width, height, color, thickness, filled)
  local object = create {
    type = "rectangle",
    x = x,
    y = y,
    width = width,
    height = height,
    color = color,
    thickness = thickness or 1,
    filled = filled or false,
    draw_order = 0,
    enabled = true
  }
  ---@cast object +graphics_object-rectangle

  if auto_update then
    update_screen()
  end

  return object
end

--- Draw an ellipse to the screen.
---@param x integer The x-coordinate of the center of the ellipse.
---@param y integer The y-coordinate of the center of the ellipse.
---@param a integer The horizontal radius of the ellipse.
---@param b integer The vertical radius of the ellipse. Set to 0 or a to make a circle.
---@param color color The color of the ellipse.
---@param thickness integer? The line thickness of the ellipse. Defaults to 1.
---@param filled boolean? Whether the ellipse should be filled. Defaults to false.
---@return turmitor_graphics_object|graphics_object-ellipse object The created ellipse object.
function turmitor_graphics.ellipse(x, y, a, b, color, thickness, filled)
  local object = create {
    type = "ellipse",
    x = x,
    y = y,
    a = a,
    b = b,
    color = color,
    thickness = thickness or 1,
    filled = filled or false,
    draw_order = 0,
    enabled = true
  }
  ---@cast object +graphics_object-ellipse

  if auto_update then
    update_screen()
  end

  return object
end

--- Draw an image to the screen.
---@param image image The image to draw.
---@param x integer The x-coordinate of the top-left corner of the image.
---@param y integer The y-coordinate of the top-left corner of the image.
function turmitor_graphics.image(image, x, y)
  error("Not yet implemented.")
end

--- Draw text to the screen.
---@param text string The text to draw.
---@param x integer The x-coordinate of the text.
---@param y integer The y-coordinate of the text.
---@param fg color? The foreground color of the text. Leave nil for white.
---@param bg color? The background color of the text. Leave nil for transparent.
---@param font unknown? The font to use for the text.
function turmitor_graphics.text(text, x, y, fg, bg, font)
  error("Not yet implemented.")
end

--- Clear the pre buffer (remove all objects).
function turmitor_graphics.clear()
  pre_buffer = {}

  if auto_update then
    update_screen()
  end
end

--- Manually update the screen.
function turmitor_graphics.flush()
  update_screen()
end

turmitor_graphics.set_size(size.x, size.y)
return turmitor_graphics