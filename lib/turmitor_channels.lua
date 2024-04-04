--- A list of channels used by Turmitor for communication between the controller
--- and the turtles.

local expect = require "cc.expect".expect

---@class TurmitorChannels
local TurmitorChannels = {
  --- The channel that turtles will send messages to the controller on.
  CHANNEL_TURTLE_REPLY = 10000,

  --- The channel turtles will notify on if there are issues.
  CHANNEL_ERROR = 10001,

  --- The channel that the controller will send messages to the turtles on.
  --- This is used for messages that are specific to one or more turtles.
  --- Turtles are chunked into their specific characters, so character 1,1 will
  --- be on channel 11000, 1,2 will be on 11001, etc. This assumes a base size of
  --- 51 characters wide, so when wrapping around to 2,1, the channel will be 11051.
  --- This unfortunately *does* mean that there is a hard-limit of 51 characters wide.
  CHANNEL_CONTROL = 11000,

  --- The channel that the controller will send "all" messages to the turtles on.
  --- This is used for messages that all turtles should act on.
  CHANNEL_ALL = 15000,
}

--- Get the channel that a client should be listening on.
---@param char_x number The character-x position of the client, should be zero-indexed.
---@param char_y number The character-y position of the client, should be zero-indexed.
---@return number channel The channel that the client should be listening on.
function TurmitorChannels.get_client_channel(char_x, char_y)
  expect(1, char_x, "number")
  expect(2, char_y, "number")

  return TurmitorChannels.CHANNEL_CONTROL + char_x + char_y * 51
end

return TurmitorChannels