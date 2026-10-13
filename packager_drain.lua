-- packager_drain.lua
-- Empties every packager output chest on the wired network into a
-- Create Connected item silo, as fast as CC allows (about one sweep every 1-2 ticks).
--
-- Setup: put a wired modem on every output chest and on the silo,
-- right-click each modem so it turns red (connected), and run networking
-- cable from them to the computer. Save this file as "startup.lua" so it
-- starts again whenever the chunk loads or the server restarts.

-- Peripheral name of the silo, e.g. "create_connected:item_silo_0".
-- nil = use the first item silo found on the network.
SILO = nil

-- Any inventory whose peripheral name contains one of these gets emptied.
SOURCE_PATTERNS = { "chest", "barrel" }

-- Peripheral names that must never be emptied, even if they match above.
EXCLUDE = {
  -- ["minecraft:chest_12"] = true,
}

-- Seconds to wait after a sweep that moved nothing (0 = next tick).
IDLE_DELAY = 0.1
AUTO_UPDATE = true        -- install new versions from GitHub automatically, keeping these settings

local silo
local sources = {}
local totalMoved = 0
local lastMoved = 0
local siloFull = false
local lastError = nil
local otherNet = 0

local function matchesSource(name)
  if EXCLUDE[name] or name == silo then return false end
  if not peripheral.hasType(name, "inventory") then return false end
  for _, pat in ipairs(SOURCE_PATTERNS) do
    if string.find(name, pat, 1, true) then return true end
  end
  return false
end

local function scan()
  lastError = nil
  silo = SILO
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
      if moved == 0 then sleep(IDLE_DELAY) end
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
local function readyToUpdate()
  return true
end

-- ============================================================ auto-update

-- Every UPDATE_CHECK_MINUTES this checks GitHub for a newer version. A new
-- version is downloaded, checked that it loads, given your current settings
-- (the UPPERCASE lines at the top of this file), saved, and the computer
-- reboots into it. Set AUTO_UPDATE = false at the top to turn this off.
local UPDATE_REPO = "levisnakes/cc-packager-drain"
local UPDATE_FILE = "packager_drain.lua"
local UPDATE_CHECK_MINUTES = 15
local PROGRAM_PATH = (shell and shell.getRunningProgram()) or "startup.lua"
local SHA_FILE = "/.version_" .. UPDATE_FILE

-- Settings are the top-of-file assignments to UPPERCASE names, before the
-- first "local" line or "-- ====" section. Tables can span several lines.
local function splitSettings(src)
  local settings, rest = {}, {}
  local inSettings = true
  for line in (src .. "\n"):gmatch("(.-)\n") do
    if inSettings and (line:match("^local ") or line:match("^%-%- ====")) then inSettings = false end
    table.insert(inSettings and settings or rest, line)
  end
  return settings, rest
end

local function braceDelta(line)
  local code = line:gsub('"[^"]*"', ""):gsub("%-%-.*$", "")
  local _, opens = code:gsub("{", "")
  local _, closes = code:gsub("}", "")
  return opens - closes
end

-- [NAME] = the full statement text, possibly several lines
local function statements(lines)
  local out = {}
  local i = 1
  while i <= #lines do
    local name = lines[i]:match("^([%u_][%u%d_]*)%s*=")
    if name then
      local block = { lines[i] }
      local depth = braceDelta(lines[i])
      while depth > 0 and i < #lines do
        i = i + 1
        table.insert(block, lines[i])
        depth = depth + braceDelta(lines[i])
      end
      out[name] = table.concat(block, "\n")
    end
    i = i + 1
  end
  return out
end

-- New file, with each setting that already exists replaced by your value.
local function mergeSettings(oldSrc, newSrc)
  local oldSettings = statements((splitSettings(oldSrc)))
  local newSettings, rest = splitSettings(newSrc)
  local out = {}
  local i = 1
  while i <= #newSettings do
    local line = newSettings[i]
    local name = line:match("^([%u_][%u%d_]*)%s*=")
    if name and oldSettings[name] then
      table.insert(out, oldSettings[name])
      local depth = braceDelta(line)
      while depth > 0 and i < #newSettings do
        i = i + 1
        depth = depth + braceDelta(newSettings[i])
      end
    else
      table.insert(out, line)
    end
    i = i + 1
  end
  for _, line in ipairs(rest) do table.insert(out, line) end
  local merged = table.concat(out, "\n")
  -- splitting added one trailing newline's worth of empty line; match the source
  if newSrc:sub(-1) == "\n" and merged:sub(-1) ~= "\n" then merged = merged .. "\n" end
  return (merged:gsub("\n\n$", "\n"))
end

local function fetch(url, headers)
  local ok, h = pcall(http.get, url, headers)
  if not ok or not h then return nil end
  local body = h.readAll()
  h.close()
  return body
end

local function readText(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  local t = f.readAll()
  f.close()
  return t
end

local function writeText(path, text)
  local f = fs.open(path, "w")
  f.write(text)
  f.close()
end

local function checkForUpdate(atBoot)
  if AUTO_UPDATE == false or not http then return end
  local sha = fetch("https://api.github.com/repos/" .. UPDATE_REPO .. "/commits/main",
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-auto-update" })
  if not sha then return end
  sha = sha:match("^%s*(%x+)%s*$")
  if not sha or #sha < 40 or readText(SHA_FILE) == sha then return end

  local newSrc = fetch("https://raw.githubusercontent.com/" .. UPDATE_REPO .. "/" .. sha .. "/" .. UPDATE_FILE)
  if not newSrc or not _G.load(newSrc, UPDATE_FILE) then return end
  local oldSrc = readText(PROGRAM_PATH)
  if not oldSrc then return end
  local merged = mergeSettings(oldSrc, newSrc)
  if not _G.load(merged, UPDATE_FILE) then return end
  if merged == oldSrc then
    writeText(SHA_FILE, sha)
    return
  end

  -- at boot nothing is running yet, so there is nothing to wait for
  while not atBoot and not readyToUpdate() do sleep(5) end
  writeText(PROGRAM_PATH .. ".old", oldSrc)
  writeText(PROGRAM_PATH, merged)
  writeText(SHA_FILE, sha)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Updated to " .. sha:sub(1, 7) .. ", restarting...")
  if not atBoot then sleep(1) end
  os.reboot()
end

local function updateLoop()
  while true do
    sleep(UPDATE_CHECK_MINUTES * 60)
    pcall(checkForUpdate)
  end
end

-- Check for a new version as soon as the computer starts, before the
-- program runs, so a restart always picks up the latest version.
local function bootUpdate()
  if AUTO_UPDATE == false or not http then return end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Checking for updates...")
  pcall(checkForUpdate, true)
end

bootUpdate()
parallel.waitForAny(drainLoop, watchLoop, updateLoop)
