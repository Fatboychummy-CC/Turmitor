package.path = package.path .. ";lib/?.lua;lib/?/init.lua"

_G.bmp = require "bmp"
_G.logging = require "logging"
logging.set_level(logging.LOG_LEVEL.DEBUG)

_G.TurmitorServer = require "turmitor_server"

TurmitorServer.set_modem("bottom")
if ... then -- Only restart if any arguments are given.
  TurmitorServer.restart(
    300, 2
  )
end

local function yprint(...)
  local old = term.getTextColor()
  term.setTextColor(colors.yellow)
  print(...)
  term.setTextColor(old)
end


parallel.waitForAny(
  function()
    sleep(240)
  end,
  function()
    yprint("Turtles should be ready, press any key to continue...")
    sleep(1)
    os.pullEvent("key")
  end
)

_G.turm = TurmitorServer.get_terminal_interface()
_G.gfx = TurmitorServer.get_graphical_interface()
gfx.set_size(42, 36)


TurmitorServer.pickup_blocks()
yprint("Showing off turtles.")
yprint("Press any key to continue...")
sleep() -- Avoid os.pullEvent picking up the last keypress
os.pullEvent("key")

TurmitorServer.clear(colors.black)

sleep() -- Anti-timeout measure
yprint("Loading... Please wait.")

_G.bimg = require "lib/server/graphics/bimg"
_G.test_bimg = bimg.read("disk/badapple.bimg")
sleep() -- Anti-timeout measure
yprint("Image loaded, converting...")

if not test_bimg then error("bruh") end
_G.image = gfx.image(test_bimg)
image.enabled = true
image.animate = false -- we will manually step frames
image.x = 1
image.y = 1

sleep() -- Anti-timeout measure
yprint("Image converted, preprocessing colors...")


-- Pre-process: All colors need to map to either black or white.
-- Unfortunately, Sanjuuni tries to be smart about nearby colors and
-- makes some pixels pink, brown, etc.
local lookup = {}
for i = 0, 15 do
  local r, g, b = term.nativePaletteColor(2^i)
  local gray = (r + g + b) / 3
  if gray < 0.5 then
    lookup[2^i] = colors.black
  else
    lookup[2^i] = colors.white
  end
  -- probably close enough
end

sleep() -- Anti-timeout measure
yprint("Preprocessing frames...")
for frame = 1, image.image.frame_count do
  local img = image.image.frames[frame]
  for y = 1, img.height do
    for x = 1, img.width do
      local color = img.data[y][x]
      img.data[y][x] = lookup[color] or colors.black -- default to black if something's wrong
    end
  end
end

sleep() -- Anti-timeout measure
yprint("All processing done.")
yprint("Press any key when ready.")
os.pullEvent("key")

yprint("Starting playback in 10 seconds...")
sleep(10)

local total_pixels = image.image.width * image.image.height
local our_fps = 4 -- how many frames to skip per update
local delay_per_frame = 5 -- seconds

for i = 1, image.image.frame_count, our_fps do -- Note: 16 fps base.
  image.frame = i
  local n_changes = gfx.flush()

  local total_frames = image.image.frame_count
  local time_left = (total_frames - i) / our_fps * delay_per_frame
  local hours = math.floor(time_left / 3600)
  local minutes = math.floor((time_left % 3600) / 60)
  local seconds = math.floor(time_left % 60)

  print(("Frame %d / %d: %d changed. Est time: %02d:%02d:%02d"):format(
    i, image.image.frame_count, n_changes,
    hours, minutes, seconds
  ))

  if n_changes > (total_pixels / 2) then
    print("  (Large update: " .. n_changes .. " pixels changed)")
    sleep(delay_per_frame)
  else
    sleep(delay_per_frame) -- Showtime, all updates need to take the same amount of time. Let's do this.
    --sleep(2.5)
  end
end

-- Draw the screen red to indicate the end of playback.
TurmitorServer.clear(colors.red)

yprint("Playback complete.")