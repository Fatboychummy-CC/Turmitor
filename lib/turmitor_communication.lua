--- Turmitor communication: Communication library between turtles and the control computer.

local expect = require "cc.expect".expect
local smn = require "single_modem_network"
local read_fbmp = require "read_fbmp"
local logging = require "logging"

local context = logging.create_context("communication")
local font = read_fbmp(fs.combine(shell.dir(), "data/font.fbmp"))

---@class TurmitorControlMessage
---@field pos_x integer The top-left X position of the character that should be displayed in the bitmap.
---@field pos_y integer The top-left Y position of the character that should be displayed in the bitmap.
---@field fg valid_colors The foreground color.
---@field bg valid_colors The background color.
---@field action string? An optional action to take, only used on CHANNEL_ALL.

---@class TurmitorCommunication
local TurmitorCommunication = {}

local selected_modem = nil

-- Turtle -> Controller --

--- The channel that turtles will send messages to the controller on.
TurmitorCommunication.CHANNEL_TURTLE_REPLY = 10000
--- The channel turtles will notify on if there are issues.
TurmitorCommunication.CHANNEL_ERROR = 10001


-- Controller -> Turtle --

--- The channel that the controller will send messages to the turtles on.
--- This is used for messages that are specific to one or more turtles.
--- Turtles are chunked into their specific characters, so character 1,1 will
--- be on channel 11000, 1,2 will be on 11001, etc. This assumes a base size of
--- 51 characters wide, so when wrapping around to 2,1, the channel will be 11051.
TurmitorCommunication.CHANNEL_CONTROL = 11000
--- The channel that the controller will send "all" messages to the turtles on.
--- This is used for messages that all turtles should act on.
TurmitorCommunication.CHANNEL_ALL = 15000

--- Handle communications from the controller to the turtles, given the turtle's x,y position in the array.
--- Warning: This method assumes that SMN is set up!
---@param x number The x position of the turtle in the array.
---@param y number The y position of the turtle in the array.
---@param callback_color fun(color:valid_colors) The function to call when a color is received.
---@param callback_action fun(action:string) The function to call when an action is received.
function TurmitorCommunication.turtle_handle_comms(x, y, callback_color, callback_action)
  expect(1, x, "number")
  expect(2, y, "number")

  -- Determine which character this turtle is a part of (characters are 6x9)
  local char_x, char_y = math.floor((x - 1) / 6), math.floor((y - 1) / 9)
  local inner_x, inner_y = (x - 1) % 6, (y - 1) % 9

  smn.closeAll()
  local control_channel = TurmitorCommunication.CHANNEL_CONTROL + char_x + char_y * 51
  smn.open(control_channel)
  smn.open(TurmitorCommunication.CHANNEL_ALL)

  context.debug("Listening on channel", control_channel, "for turtle at", x, y)

  while true do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    ---@cast message TurmitorControlMessage
    if side == selected_modem then
      if channel == control_channel then
        local used_x, used_y = message.pos_x + inner_x, message.pos_y + inner_y
        if font[used_y] and font[used_y][used_x] then
          -- foreground color
          callback_color(message.fg)
        else
          -- background color.
          callback_color(message.bg)
        end
      elseif channel == TurmitorCommunication.CHANNEL_ALL then
        if message.action then
          callback_action(message.action)
        else
          -- Likely just a clear color.
          callback_color(message.fg)
        end
      end
    end
  end
end

local function make_message(pos_x, pos_y, fg, bg, action)
  expect(1, pos_x, "number")
  expect(2, pos_y, "number")
  expect(3, fg, "string")
  expect(4, bg, "string")
  expect(5, action, "string", "nil")

  return {
    pos_x = pos_x,
    pos_y = pos_y,
    fg = fg,
    bg = bg,
    action = action
  }
end

--- Send a color clear to the turtles.
---@param color string The color to clear with.
function TurmitorCommunication.send_color_clear(color)
  expect(1, color, "string")

  smn.transmit(
    TurmitorCommunication.CHANNEL_ALL,
    TurmitorCommunication.CHANNEL_TURTLE_REPLY,
    make_message(0, 0, color, color)
  )
  context.debug("Transmitted color clear message to all turtles.")
end

--- Transmit a reset message to the turtles.
function TurmitorCommunication.transmit_reset()
  smn.transmit(
    TurmitorCommunication.CHANNEL_ALL,
    TurmitorCommunication.CHANNEL_TURTLE_REPLY,
    make_message(0, 0, "black", "black", "reset")
  )
  context.debug("Transmitted reset message to all turtles.")
end

--- Transmit a character to the turtles.
---@param x integer The x position of the character on the screen.
---@param y integer The y position of the character on the screen.
---@param char string The character to transmit.
---@param fg valid_colors The foreground color.
---@param bg valid_colors The background color.
function TurmitorCommunication.transmit_character(x, y, char, fg, bg)
  expect(1, x, "number")
  expect(2, y, "number")
  expect(3, char, "string")
  expect(4, fg, "string")
  expect(5, bg, "string")

  -- Step 1: Determine the position in the font that this character originates
  -- The font is 16x16 characters, and each character is 6x9 pixels. Each char
  -- has two spaces in between it.
  -- Char 0 is the top left character, 255 is the bottom right.
  local char_x, char_y = char:byte() % 16, math.floor(char:byte() / 16)
  local inner_x, inner_y = 2 + 6 * char_x + 2 * char_x, 2 + 9 * char_y + 2 * char_y

  -- Step 2: Transmit the character to the turtles.
  -- 2.a) Determine which channel to use.
  local channel = TurmitorCommunication.CHANNEL_CONTROL + (x - 1) + (y - 1) * 51
  smn.transmit(
    channel,
    TurmitorCommunication.CHANNEL_TURTLE_REPLY,
    make_message(inner_x, inner_y, fg, bg)
  )
  context.debug("Transmitted character", char, "to channel", channel, "with fg", fg, "and bg", bg)
end

--- Set the modem network to use.
---@param modem_side computerSide The side of the modem to use.
function TurmitorCommunication.set_modem(modem_side)
  expect(1, modem_side, "string")

  smn.set_modem(modem_side)
  selected_modem = modem_side
end

return TurmitorCommunication