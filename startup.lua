--- This program simply checks if it is running on a turtle, and if so, runs the
--- turtle redirect system. Mainly just a simple helper program to be put on a
--- startup disk.

-- Get the directory of this startup program.
local dir = fs.getDir(shell.getRunningProgram())
shell.setDir(dir)

if turtle then
  -- If we are on a turtle, run the turtle program.
  shell.run("turmitor_turtle.lua")
else
  -- If we are not on a turtle, run the control program.

  sleep(5)
  shell.run("turmitor_control.lua")
end