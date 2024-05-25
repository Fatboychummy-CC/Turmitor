--- Graphical implementation of lines, circles, pixels, etc.

---@class graphics_object
---@field enabled boolean Whether the object should be drawn. Ignored by the buffer methods, so parent graphics implementations should handle this.
---@field draw_order integer The order in which the object should be drawn. Ignored by the buffer methods, so parent graphics implementations should handle this.
---@field x integer The x-coordinate of the object.
---@field y integer The y-coordinate of the object.
---@field color color The color of the object.
---@field type string The type of the object.

---@class graphics_object-pixel: graphics_object
---@field type "pixel"

---@class graphics_object-line: graphics_object
---@field type "line"
---@field x2 integer The x-coordinate of the end of the line.
---@field y2 integer The y-coordinate of the end of the line.
---@field thickness integer The thickness of the line.

---@class graphics_object-ellipse: graphics_object
---@field type "ellipse"
---@field filled boolean Whether the circle should be filled.
---@field x integer The x-coordinate of the center of the circle.
---@field y integer The y-coordinate of the center of the circle.
---@field thickness integer The thickness of the circle (fills both inwards and outwards).
---@field a number The horizontal scaling factor.
---@field b number The vertical scaling factor.

---@class graphics_object-rectangle: graphics_object
---@field type "rectangle"
---@field width integer The width of the rectangle.
---@field height integer The height of the rectangle.
---@field filled boolean Whether the rectangle should be filled.
---@field thickness integer The thickness of lines of the rectangle (acts as an outline).

---@class graphics_object-text: graphics_object
---@field type "text"
---@field text string The text to draw.

---@class graphics_object-image: graphics_object
---@field type "image"
---@field image image The image to draw.
---@field animate boolean Whether the image should be animated (if it is an animated image).
---@field frame integer The current frame of the image.

---@class graphics
local graphics = {}

--- Initialize a buffer with the given size and color.
---@param x_size integer The width of the buffer.
---@param y_size integer The height of the buffer.
---@param color color? The color to fill the buffer with.
---@return color[][] buffer The buffer.
function graphics.init_buffer(x_size, y_size, color)
  local buffer = {}
  color = color or colors.black

  for y = 1, y_size do
    buffer[y] = {}

    for x = 1, x_size do
      buffer[y][x] = color
    end
  end

  return buffer
end

--- Debug a buffer to the console.
---@param buffer color[][] The buffer to debug.
function graphics.debug_buffer(buffer)
  local file = fs.open("buffer.txt", "a")
  if not file then
    error("Failed to open buffer.txt for writing.", 2)
  end

  file.writeLine("====")
  for y = 1, #buffer do
    local line = ""

    for x = 1, #buffer[y] do
      line = line .. colors.toBlit(buffer[y][x])
    end

    file.writeLine(line)
  end

  file.close()
end

local function set_buffer(buffer, x, y, color)
  if not buffer[y] or not buffer[y][x] then
    return
  end

  buffer[y][x] = color
end

--- Write a pixel to the given buffer.
---@param object graphics_object-pixel The object to draw.
---@param buffer color[][] The buffer to draw to.
function graphics.pixel(object, buffer)
  set_buffer(buffer, object.x, object.y, object.color)
end

--- Write a line to the given buffer.
---@param object graphics_object-line The object to draw.
---@param buffer color[][] The buffer to draw to.
function graphics.line(object, buffer, print_debug_info)
  if print_debug_info then
    print("====")
  end
  local x1, x2, y1, y2 = object.x, object.x2, object.y, object.y2

  -- Calculate the slope of the line.
  local dx = x2 - x1
  local dy = y2 - y1
  local m = dy / dx

  -- If the slope is less than 1, we can use the x-coordinate as the iterator.
  --[[
    ##
      ##
        ##
          ##
    and so on.
  ]]
  if print_debug_info then
    print("m:", m)
  end

  if math.abs(m) < 1 then
    -- Sort the x-coordinates so that x1 is always less than x2.
    if object.x > object.x2 then
      x1, x2 = object.x2, object.x
      y1, y2 = object.y2, object.y
    end

    for y_offset = -math.floor(object.thickness / 2), math.ceil(object.thickness / 2) - 1 do
      for x = x1, x2 do
        local y = math.floor(m * (x - x1) + y1) + y_offset

        set_buffer(buffer, x, y, object.color)
      end
    end
  else
    -- Otherwise, we use the y-coordinate as the iterator.
    --[[
      #
      #
       #
       #
      and so on.
    ]]

    -- Sort the y-coordinates so that y1 is always less than y2.
    if object.y > object.y2 then
      x1, x2 = object.x2, object.x
      y1, y2 = object.y2, object.y
    end

    for x_offset = -math.floor(object.thickness / 2), math.ceil(object.thickness / 2) - 1 do
      if print_debug_info then
        print("x_offset:", x_offset)
      end
      for y = y1, y2 do
        local x = math.floor((y - y1) / m + x1) + x_offset
        if print_debug_info then
          print("x,y:", x, y)
        end

        set_buffer(buffer, x, y, object.color)
      end
    end
  end
end

--- Write an ellipse to the given buffer.
---@param object graphics_object-ellipse The object to draw.
---@param buffer color[][] The buffer to draw to.
function graphics.ellipse(object, buffer)
  -- Midpoint ellipse drawing algorithm. Stolen and adapted to lua shamelessly
  -- from https://www.geeksforgeeks.org/mid-point-ellipse-drawing-algorithm/

  local x_center, y_center, a, b = object.x, object.y, object.a, object.b

  if a == 0 then return end

  if b == 0 then
    b = a
  end

  local a_sqr, b_sqr = a * a, b * b
  local x, y = 0, b
  local color = object.color

  -- Initial decision parameter of region 1.
  local d1 = b_sqr - a_sqr * b + 0.25 * a_sqr
  local dx, dy = 2 * b_sqr * x, 2 * a_sqr * y

  -- We need to save the values we plot (in case we want to fill the circle),
  -- so we'll use a table to store the left and right-most points, so we can
  -- fill in using scanlines.
  ---@type color[][] [y][1] = leftmost x, [y][2] = rightmost x
  local scanlines = {}

  --- Plot a point on the circle, and update the scanlines table.
  ---@param _x integer The x-coordinate of the point.
  ---@param _y integer The y-coordinate of the point.
  local function plot(_x, _y)
    -- For thickness...
    if object.thickness == 1 then
      set_buffer(buffer, _x, _y, color)
    else
      for offset = -math.floor(object.thickness / 2), math.ceil(object.thickness / 2) - 1 do
        set_buffer(buffer, _x, _y + offset, color)
        set_buffer(buffer, _x + offset, _y, color)
      end
    end

    if not scanlines[_y] then
      scanlines[_y] = {}
    end

    if not scanlines[_y][1] or _x < scanlines[_y][1] then
      scanlines[_y][1] = _x
    end

    if not scanlines[_y][2] or _x > scanlines[_y][2] then
      scanlines[_y][2] = _x
    end
  end

  -- For region 1.
  while dx < dy do
    -- Write the points based on 4-way symmetry.
    plot(x_center + x, y_center + y)
    plot(x_center - x, y_center + y)
    plot(x_center + x, y_center - y)
    plot(x_center - x, y_center - y)

    -- Checking and updating value of decision parameter based on algorithm.
    if d1 < 0 then
      x = x + 1
      dx = dx + 2 * b_sqr
      d1 = d1 + dx + b_sqr
    else
      x = x + 1
      y = y - 1
      dx = dx + 2 * b_sqr
      dy = dy - 2 * a_sqr
      d1 = d1 + dx - dy + b_sqr
    end
  end

  -- Decision parameter of region 2.
  local d2 = b_sqr * (x + 0.5) * (x + 0.5)
    + a_sqr * (y - 1) * (y - 1) - a_sqr * b_sqr

  -- Plotting points of region 2.
  while y >= 0 do
    -- Write the points based on 4-way symmetry.
    plot(x_center + x, y_center + y)
    plot(x_center - x, y_center + y)
    plot(x_center + x, y_center - y)
    plot(x_center - x, y_center - y)

    -- Checking and updating parameter value based on algorithm.
    if d2 > 0 then
      y = y - 1
      dy = dy - 2 * a_sqr
      d2 = d2 + a_sqr - dy
    else
      y = y - 1
      x = x + 1
      dx = dx + 2 * b_sqr
      dy = dy - 2 * a_sqr
      d2 = d2 + a_sqr + dx - dy
    end
  end

  -- Finally, fill the ellipse if needed.
  if object.filled then
    for y, scanline in pairs(scanlines) do
      for x = scanline[1], scanline[2] do
        set_buffer(buffer, x, y, color)
      end
    end
  end
end

--- Write a rectangle to the given buffer.
---@param object graphics_object-rectangle The object to draw.
---@param buffer color[][] The buffer to draw to.
function graphics.rectangle(object, buffer)
  -- If thickness > 1, then we can offset are start positions by -thickness, and
  -- increase the width and height by 2 * thickness. 
  local x, y, width, height = object.x, object.y, object.width, object.height
  local n1 = object.thickness - 1
  x = x - n1
  y = y - n1
  width = width + 2 * n1
  height = height + 2 * n1

  -- If the rectangle is filled, we can just make a buffer the size of the
  -- rectangle and fill it with the color.
  if object.filled then
    for y_offset = 0, height - 1 do
      for x_offset = 0, width - 1 do
        set_buffer(buffer, x + x_offset, y + y_offset, object.color)
      end
    end

    return
  end

  -- Copy the top and bottom lines.
  for y_offset = 0, object.thickness - 1 do
    for x_offset = 0, width - 1 do
      set_buffer(buffer, x + x_offset, y + y_offset, object.color)
      set_buffer(buffer, x + x_offset, y + height - y_offset - 1, object.color)
    end
  end

  -- Copy the left and right lines.
  for x_offset = 0, object.thickness - 1 do
    for y_offset = 0, height - 1 do
      set_buffer(buffer, x + x_offset, y + y_offset, object.color)
      set_buffer(buffer, x + width - x_offset - 1, y + y_offset, object.color)
    end
  end
end

--- Write text to the given buffer.
---@param object graphics_object-text The object to draw.
---@param buffer color[][] The buffer to draw to.
function graphics.text(object, buffer)
  error("Not yet implemented.")
end

--- Write an image to the given buffer.
---@param object graphics_object-image The object to draw.
---@param buffer color[][] The buffer to draw to.
function graphics.image(object, buffer)
  error("Not yet implemented.")
end

return graphics