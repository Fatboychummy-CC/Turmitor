--- Turmitor communication: Communication library between turtles and the control computer.

local expect = require "cc.expect".expect
local smn = require "single_modem_network"

---@class TurmitorCommunication
local TurmitorCommunication = {}

-- Turtle -> Controller --

--- The channel that turtles will send messages to the controller on.
TurmitorCommunication.CHANNEL_TURTLE_REPLY = 10000
--- The channel turtles will notify on if there are issues.
TurmitorCommunication.CHANNEL_ERROR = 10001


-- Controller -> Turtle --

--- The channel that the controller will send messages to the turtles on.
--- This is used for messages that are specific to one or more turtles.
TurmitorCommunication.CHANNEL_CONTROL = 11000
--- The channel that the controller will send "all" messages to the turtles on.
--- This is used for messages that all turtles should act on.
TurmitorCommunication.CHANNEL_ALL = 11001

--- Handle communications from the controller to the turtles, given the turtle's x,y position in the array.
--- Warning: This method assumes that SMN is set up!
---@param x number The x position of the turtle in the array.
---@param y number The y position of the turtle in the array.
---@param callback_color function The function to call when a color is received.
function TurmitorCommunication.turtle_handle_comms(x, y, callback_color)
  expect(1, x, "number")
  expect(2, y, "number")

  smn.closeAll()
  smn.open(TurmitorCommunication.CHANNEL_CONTROL)
  smn.open(TurmitorCommunication.CHANNEL_ALL)

  while true do
    local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    if channel == TurmitorCommunication.CHANNEL_CONTROL then
      local message_table = textutils.unserialize(message)
      if message_table.x == x and message_table.y == y then
        callback_color(message)
      end
    elseif channel == TurmitorCommunication.CHANNEL_ALL then
      callback_color(message)
    end
  end
end

--- Send a color clear to the turtles.
---@param color string The color to clear with.
function TurmitorCommunication.send_color_clear(color)
  expect(1, color, "string")

  smn.transmit(TurmitorCommunication.CHANNEL_ALL, TurmitorCommunication.CHANNEL_TURTLE_REPLY, color)
end

--- Transmit a reset message to the turtles.
function TurmitorCommunication.transmit_reset()
  smn.transmit(TurmitorCommunication.CHANNEL_ALL, TurmitorCommunication.CHANNEL_TURTLE_REPLY, "reset")
end


--- Set the modem network to use.
---@param modem_side computerSide The side of the modem to use.
function TurmitorCommunication.set_modem(modem_side)
  expect(1, modem_side, "string")

  smn.set_modem(modem_side)
end

return TurmitorCommunication