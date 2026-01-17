--- Simple BIMG reader, converter, and verifier.

local ACCEPTED_MAJOR_VERSION = 1

---@class bimg
local bimg = {}

local blit_lookup = {}
for i = 0, 15 do
  local hex = string.format("%x", i)
  blit_lookup[hex] = 2^i
end

--- Read a BIMG file, convert it to image data, and return it.
---@param path string The path to the BIMG file.
---@return image? image The BIMG data as image data, or nil if the file is invalid.
---@return string? error The error message, or nil if the file is valid.
function bimg.read(path)
  local handle = fs.open(path, "r") --[[@as ReadHandle]]
  if not handle then
    return nil, "File not found."
  end

  local data = handle.readAll()
  handle.close()

  if not data or data == "" then
    return nil, "File is empty."
  end

  local bimg_data = textutils.unserialize(data)

  if not bimg_data or type(bimg_data) ~= "table" then
    return nil, "Invalid BIMG file."
  end

  if type(bimg_data.version) ~= "string" or not bimg_data.version:match("^%d+%.%d+%.%d+$") then
    return nil, "Invalid BIMG version string or version string not found."
  end

  local major, minor, patch = bimg_data.version:match("^(%d+)%.(%d+)%.(%d+)$")
  major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)

  if major ~= ACCEPTED_MAJOR_VERSION then
    return nil, "Unsupported BIMG version."
  end

  ---@type image
  local image = {
    -- required data
    palette = {}, -- Ignore for now.

    type = "bimg",
    version = bimg_data.version,
    animated = bimg_data.animated or bimg_data.animation,
    width = 0,
    height = 0,
    frames = {},
    frame_count = #bimg_data,

    -- optional data

    author = bimg_data.author,
    description = bimg_data.description,
    creator = bimg_data.creator,
    date = bimg_data.date,
    secondsPerFrame = bimg_data.secondsPerFrame,
  }

  -- Frames in BIMG files are stored as bimg[1][frame_number], and each line is
  -- stored as bimg[1][frame_number][line_number], where each line is a table
  -- containing the text, fg, and bg of the line, all as one string.
  -- We need to convert this to a table of three tables: text, fg, and bg; where
  -- each table is a list of single characters.

  image.animated = image.animated or #bimg_data > 1

  --- Calculates the base pixel position for a given blit character position.
  ---@param x integer The blit character x position.
  ---@param y integer The blit character y position.
  ---@return integer base_x The base pixel x position.
  ---@return integer base_y The base pixel y position.
  ---@nodiscard
  local function base(x, y)
    return (x - 1) * 2 + 1, (y - 1) * 3 + 1
  end

  -- Blit characters start at 0x80 to 0x8f, and work by turning on pixels in a
  -- "binary" 2x3 grid.
  -- In theory, we should be able to just subtract 0x80 from the character code, and
  -- use bitwise operations to determine which pixels are on and off.

  --- Sets a 2x3 set of pixels in the image data, based off a blit character.
  ---@param char string The blit character.
  ---@param fg_color string The foreground color hex digit.
  ---@param bg_color string The background color hex digit.
  ---@param frame_data integer[][] The frame data to modify.
  ---@param x integer The blit character x position.
  ---@param y integer The blit character y position.
  local function set_blit_pixels(char, fg_color, bg_color, frame_data, x, y)
    local start_x, start_y = base(x, y)

    if char == ' ' then char = '\x80' end

    local char_code = string.byte(char)
    local bits = char_code - 0x80
    for bit_y = 0, 2 do
      for bit_x = 0, 1 do
        local pixel_on = bit32.band(bits, bit32.lshift(1, bit_y * 2 + bit_x)) ~= 0
        local pixel_x = start_x + bit_x
        local pixel_y = start_y + bit_y

        if pixel_on then
          frame_data[pixel_y][pixel_x] = blit_lookup[fg_color] or colors.white
        else
          frame_data[pixel_y][pixel_x] = blit_lookup[bg_color] or colors.black
        end
      end
    end
  end

  -- Get width and height from the first frame.
  if #bimg_data == 0 or #bimg_data[1] == 0 then
    return nil, "BIMG file contains no frames."
  end

  image.width = #bimg_data[1][1][1] * 2
  image.height = #bimg_data[1] * 3

  -- Initialize all the frames.
  for frame_number, frame in ipairs(bimg_data) do
    image.frames[frame_number] = {
      width = image.width,
      height = image.height,
      data = {},
      palette = frame.palette,
      duration = frame.duration,
    }

    for y = 1, image.height do -- Blit characters are 2x3 pixels.
      image.frames[frame_number].data[y] = {}
    end
  end

  for frame_number, frame in ipairs(bimg_data) do
    for y, line_data in ipairs(frame) do
      local frame_data = image.frames[frame_number].data
      for x = 1, image.width / 2 do
        local char = line_data[1]:sub(x, x) or " "
        local fg_color = line_data[2]:sub(x, x) or "0"
        local bg_color = line_data[3]:sub(x, x) or "f"

        set_blit_pixels(char, fg_color, bg_color, frame_data, x, y)
      end
    end
  end

  return image
end

return bimg