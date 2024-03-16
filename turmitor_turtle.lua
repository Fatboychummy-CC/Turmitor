--- A program for a turtle that allows a network of turtles to be used as a
--- terminal redirect object, by drawing colors to a "screen" made out of blocks
--- placed in front of each turtle. This program is designed to be run on a
--- turtle, and will not work on a computer.

--- Turmitor --> Turtle + Monitor

--- Turtles should be placed in a grid, with each turtle facing the direction
--- that the screen should be drawn. The turtles will automatically determine
--- their positioning by the following:
--- 1. Check for the file `turtle_redirect_info.lson` in the root directory.
---   a) If it exists, read the file and set the turtle's position and direction
---      accordingly. Set name to `x,y` where x and y are the coordinates of the
---      turtle in the grid.
---   b) If it does not exist, set name to "Unknown" and continue.
--- 2. Turn to the right.
--- 3. Inspect front.
---   a) If there is no turtle in front, then the turtle is at the edge of the
---      grid. That means this turtle is at position x=1, y=?. Skip to
---      [no front turtle].
---   b) If there is a turtle in front, then the turtle is not at the edge of
---      the grid. Continue.
--- 4. Wait until the turtle in front knows its position (name is not "Unknown").
--- 5. Read the turtle in front's position. The turtle's position is x=front's
---    x+1, y=front's y. We are done now, exit.
---
--- [no front turtle]:
---   1. Inspect above.
---     a) If there is no turtle above, then the turtle is at the corner of the
---        grid. That means this turtle is at position x=1, y=1. We are done now,
---        exit.

-- Set the package path so lib is included.
package.path = package.path .. ";lib/?.lua;lib/?/init.lua"

if not turtle then
  error("This program requires a turtle to run.", 0)
end