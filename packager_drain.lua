-- packager_drain.lua
-- Empties every packager output chest on the wired network into a
-- Create Connected item silo, as fast as CC allows (about one sweep every 1-2 ticks).
--
-- Setup: put a wired modem on every output chest and on the silo,
-- right-click each modem so it turns red (connected), and run networking
-- cable from them to the computer. Save this file as "startup.lua" so it
-- starts again whenever the chunk loads or the server restarts.

local CONFIG = {
  -- Peripheral name of the silo, e.g. "create_connected:item_silo_0".
  -- Leave nil to use the first item silo found on the network.
  silo = nil,

  -- Any inventory whose peripheral name contains one of these
  -- is treated as a source and gets emptied.
  sourcePatterns = { "chest", "barrel" },

  -- Peripheral names that must never be emptied, even if they match above.
  exclude = {
    -- ["minecraft:chest_12"] = true,
  },

  -- Seconds to wait after a sweep that moved nothing (0 = next tick).
  idleDelay = 0.1,
}

local silo
local sources = {}
local totalMoved = 0
local lastMoved = 0
local siloFull = false
local lastError = nil
local otherNet = 0

local function matchesSource(name)
  if CONFIG.exclude[name] or name == silo then return false end
  if not peripheral.hasType(name, "inventory") then return false end
  for _, pat in ipairs(CONFIG.sourcePatterns) do
    if string.find(name, pat, 1, true) then return true end
  end
  return false
end

local function scan()
  lastError = nil
  silo = CONFIG.silo
  if not silo then
    for _, name in ipairs(peripheral.getNames()) do
      if string.find(name, "item_silo", 1, true) then
        silo = name
        break
      end
    end
  end
  if not silo or not peripheral.isPresent(silo) then
    silo = nil
  end

  -- pushItems only works between inventories on the same cable network.
  -- Find which wired modem on the computer reaches the silo, and only
  -- drain chests on that network; anything else is reported, not drained.
  local siloNet = nil
  if silo then
    for _, side in ipairs(rs.getSides()) do
      if peripheral.hasType(side, "peripheral_hub") and peripheral.call(side, "isPresentRemote", silo) then
        siloNet = side
        break
      end
    end
  end

  sources = {}
  otherNet = 0
  for _, name in ipairs(peripheral.getNames()) do
    if matchesSource(name) then
      if not siloNet or peripheral.call(siloNet, "isPresentRemote", name) then
        sources[#sources + 1] = name
      else
        otherNet = otherNet + 1
      end
    end
  end
end

-- One pass: list every source chest at once, then push every filled slot
-- at once. Running the calls in parallel lets them all land in the same tick.
local function sweep()
  local listings = {}
  local listTasks = {}
  for i, src in ipairs(sources) do
    listTasks[i] = function()
      local ok, items = pcall(peripheral.call, src, "list")
      if ok and items then
        listings[src] = items
      else
        lastError = src .. " list: " .. tostring(items)
      end
    end
  end
  if #listTasks > 0 then parallel.waitForAll(table.unpack(listTasks)) end

  local moved = 0
  local full = false
  local pushTasks = {}
  for src, items in pairs(listings) do
    for slot, item in pairs(items) do
      pushTasks[#pushTasks + 1] = function()
        local ok, n = pcall(peripheral.call, src, "pushItems", silo, slot)
        if ok and n then
          moved = moved + n
          if n < item.count then
            full = true
            lastError = "silo took " .. n .. "/" .. item.count .. " " .. item.name
          end
        else
          lastError = src .. " push: " .. tostring(n)
        end
      end
    end
  end
  if #pushTasks > 0 then parallel.waitForAll(table.unpack(pushTasks)) end

  return moved, full
end

local function draw()
  term.setCursorPos(1, 1)
  term.clearLine()
  term.write("Packager Drain")
  term.setCursorPos(1, 3)
  term.clearLine()
  term.write("Silo:    " .. (silo or "NOT FOUND"))
  term.setCursorPos(1, 4)
  term.clearLine()
  term.write("Sources: " .. #sources .. " chests")
  term.setCursorPos(1, 5)
  term.clearLine()
  term.write("Moved:   " .. totalMoved .. " items total")
  term.setCursorPos(1, 6)
  term.clearLine()
  term.write("Last:    " .. lastMoved)
  term.setCursorPos(1, 7)
  term.clearLine()
  if otherNet > 0 then
    if term.isColour() then term.setTextColour(colours.red) end
    term.write(otherNet .. " chest(s) on a different cable than the silo")
    term.setTextColour(colours.white)
  end
  term.setCursorPos(1, 8)
  term.clearLine()
  if siloFull then
    if term.isColour() then term.setTextColour(colours.red) end
    term.write("SILO FULL - items are waiting in chests")
    term.setTextColour(colours.white)
  end
  -- Show the most recent problem so it's visible without a debugger.
  for y = 10, 13 do
    term.setCursorPos(1, y)
    term.clearLine()
  end
  term.setCursorPos(1, 10)
  if lastError then
    if term.isColour() then term.setTextColour(colours.orange) end
    print("Error: " .. lastError)
    term.setTextColour(colours.white)
  end
end

local function drainLoop()
  while true do
    if silo and #sources > 0 then
      local moved, full = sweep()
      totalMoved = totalMoved + moved
      if moved > 0 then lastMoved = moved end
      siloFull = full
      draw()
      if moved == 0 then sleep(CONFIG.idleDelay) end
    else
      draw()
      sleep(1)
    end
  end
end

-- Re-scan whenever a modem is connected or broken, so new packager
-- chests are picked up without restarting the computer.
local function watchLoop()
  while true do
    local ev = os.pullEvent()
    if ev == "peripheral" or ev == "peripheral_detach" then
      scan()
      draw()
    end
  end
end

term.clear()
scan()
draw()
parallel.waitForAny(drainLoop, watchLoop)
