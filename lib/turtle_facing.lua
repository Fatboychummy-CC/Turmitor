--- Tiny library to handle turtle facing.

--- Wipe the event queue.
local function wipe_queue()
  os.queueEvent("__queue_end")
  for i = 1, math.huge do
    local ev = os.pullEvent()
    if ev == "__queue_end" then break end
    if i % 128 == 0 then os.queueEvent("__queue_end") end
  end
end

--- Turn the turtle to the left in a safe way that doesn't stall on too many events.
local function turn_left()
  coroutine.resume(coroutine.create(turtle.turnLeft))
  wipe_queue()
  sleep(0.5)
end

--- Turn the turtle to the right in a safe way that doesn't stall on too many events.
local function turn_right()
  coroutine.resume(coroutine.create(turtle.turnRight))
  wipe_queue()
  sleep(0.5)
end

---@alias turtle_facing
---| `0` # "forward"
---| `1` # "right"
---| `2` # "back"
---| `3` # "left"

---@class TurtleFacing
---@field facing turtle_facing The current facing of the turtle.
local TurtleFacing = {
  facing = 0
}

--- Turn to the right.
function TurtleFacing.turn_right()
  TurtleFacing.facing = (TurtleFacing.facing + 1) % 4
  turn_right()
end

--- Turn to the left.
function TurtleFacing.turn_left()
  TurtleFacing.facing = (TurtleFacing.facing - 1) % 4
  turn_left()
end

--- Turn to face a specified direction.
---@param direction number The direction to face.
function TurtleFacing.turn_to(direction)
  if TurtleFacing.facing == direction % 4 then
    return
  end

  if (TurtleFacing.facing + 1) % 4 == direction then
    TurtleFacing.turn_right()
  elseif (TurtleFacing.facing - 1) % 4 == direction then
    TurtleFacing.turn_left()
  else
    TurtleFacing.turn_right()
    TurtleFacing.turn_right()
  end
end

return TurtleFacing