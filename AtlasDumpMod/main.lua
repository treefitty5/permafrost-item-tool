-- AtlasDump v4  (UE4SS Lua, for the Permafrost Item Tool's atlas of save ids)
-- Ctrl+F2 : fly the player along the next CHUNK stops of the route in Mods\AtlasDump\route.lua (progress is remembered in progress.txt, so pressing it again
--           continues). At every stop it arrives high (400 m), measures the first surface below, descends to hover HOVER cm above it so the world streams in
--           around you, waits, and writes every NEW actor that has a save id (class, full name, position, id) to Mods\AtlasDump\AtlasDump.log.
--           Stops where nothing loads are skipped quickly. At the end of a chunk you are put back where you started and walking is switched back on.
-- Ctrl+F3 : stop at once (you are put back where you started).      Ctrl+F4 : forget the progress (start the route again from stop 1).
-- Vitals keeper: while flying, health / stamina / energy / hunger / body warmth are held at their maximum (the first test left you at 0 warmth).
-- Use it in a THROWAWAY world only. It does not change the save by itself, but moving the player loads areas, and the game saves what is loaded.
local UEHelpers = require("UEHelpers")
local TAG = "[AtlasDump] "
local CHUNK = 100                 -- stops per press of Ctrl+F2
local HIGH_Z = 40000.0           -- cm: arrival height (above every structure)
local HOVER = 2500.0             -- cm: hover height above the first surface below
local MIN_CLEARANCE = 2000.0     -- cm: never closer than this to the first surface below
local EMPTY_RADIUS = 30000.0     -- cm: a stop is "empty" when no real object loaded within this horizontal distance
local IGNORE = { "Spawner", "PCGReActor", "Renovation", "QuestItemDispenser", "RespawnPoint", "WeatherManager", "WorldMapManager", "Companion", "PhaseWeather" }

local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\AtlasDump"
end
local DIR = modDir()
local LOG_FILE = DIR .. "\\AtlasDump.log"
local PROGRESS_FILE = DIR .. "\\progress.txt"
local buffer = {}
local function flush()
  if #buffer == 0 then return end
  local f = io.open(LOG_FILE, "a"); if f then f:write(table.concat(buffer, "\n") .. "\n"); f:close() end
  buffer = {}
end
local function log(msg) print(TAG .. msg .. "\n"); buffer[#buffer + 1] = os.date("%H:%M:%S ") .. msg; flush() end
pcall(function() local f = io.open(LOG_FILE, "a"); if f then f:write("---- AtlasDump v4 loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)

local function safe(fn, ...) local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end; return nil, a end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local function hex32(v) return string.format("%08X", (tonumber(v) or 0) & 0xFFFFFFFF) end
local function guidText(g)
  if g == nil then return nil end
  local a, b, c, d = safe(function() return g.A end), safe(function() return g.B end), safe(function() return g.C end), safe(function() return g.D end)
  if a ~= nil and b ~= nil and c ~= nil and d ~= nil then return hex32(a) .. hex32(b) .. hex32(c) .. hex32(d) end
  return nil
end

local function readProgress()
  local f = io.open(PROGRESS_FILE, "r"); if not f then return 0 end
  local n = tonumber(f:read("*l") or "0") or 0; f:close(); return n
end
local function writeProgress(n) local f = io.open(PROGRESS_FILE, "w"); if f then f:write(tostring(n) .. "\n"); f:close() end end

-- ------------------------------------------------------------------ vitals keeper
local WANT = { "health", "stamina", "energy", "hunger", "bodywarmth" }
local vitals = nil          -- list of { set=, cur=propName, max=propName }
local function pathOf(o) local n = safe(function() return o:GetFullName() end); if not n then return nil end; return (n:gsub("^%S+%s+", "")) end
local function findVitals(owners)
  local found, names = {}, {}
  local sets = safe(function() return FindAllOf("AttributeSet") end) or {}
  for _, s in ipairs(sets) do
    local sp = valid(s) and pathOf(s) or nil
    local mine = false
    if sp then for _, op in ipairs(owners) do if sp:find(op, 1, true) == 1 then mine = true; break end end end
    if sp then log("  attribute set " .. sp .. (mine and "  -> kept (player)" or "  -> ignored (not the player)")) end
    if mine then
      local props = {}
      local c = safe(function() return s:GetClass() end); local guard = 0
      while valid(c) and guard < 8 do
        guard = guard + 1
        safe(function() c:ForEachProperty(function(p) local n = safe(function() return p:GetFName():ToString() end); if n then props[#props + 1] = n end end) end)
        c = safe(function() return c:GetSuperStruct() end)
      end
      local byLower = {}
      for _, n in ipairs(props) do byLower[n:lower()] = n end
      for _, w in ipairs(WANT) do
        local cur, mx = byLower[w], byLower["max" .. w]
        if cur and mx then
          found[#found + 1] = { set = s, cur = cur, max = mx }
          names[#names + 1] = (safe(function() return s:GetClass():GetFName():ToString() end) or "?") .. "." .. cur .. "/" .. mx
        end
      end
    end
  end
  return found, names
end
local function topUp()
  if not vitals then return 0 end
  local n = 0
  for _, v in ipairs(vitals) do
    if valid(v.set) then
      local mx = safe(function() return v.set[v.max].CurrentValue end)
      if mx == nil then mx = safe(function() return v.set[v.max].BaseValue end) end
      if mx then
        local ok = safe(function() v.set[v.cur].CurrentValue = mx; return true end)
        safe(function() v.set[v.cur].BaseValue = mx end)
        if ok then n = n + 1 end
      end
    end
  end
  return n
end
local function vitalsText()
  if not vitals then return "no vitals found" end
  local parts = {}
  for _, v in ipairs(vitals) do
    local cv = safe(function() return v.set[v.cur].CurrentValue end)
    parts[#parts + 1] = v.cur .. "=" .. (cv and string.format("%.0f", cv) or "?")
  end
  return table.concat(parts, " ")
end

-- ------------------------------------------------------------------ world scan
local function ignored(cls) for _, w in ipairs(IGNORE) do if cls:find(w, 1, true) then return true end end; return false end
local function collect()
  collectgarbage("collect")
  local rows, total = {}, 0
  local all = safe(function() return FindAllOf("Actor") end) or {}
  for _, a in ipairs(all) do
    if valid(a) then
      total = total + 1
      local id = guidText(safe(function() return a:GetActorGuidForSaveAndLoad() end))
      if id and id ~= "00000000000000000000000000000000" then
        local cls = safe(function() return a:GetClass():GetFName():ToString() end) or "?"
        local loc = safe(function() return a:K2_GetActorLocation() end)
        local full = safe(function() return a:GetFullName() end) or "?"
        full = full:gsub("^%S+%s+", "")
        if loc then rows[#rows + 1] = { cls = cls, full = full, x = loc.X, y = loc.Y, z = loc.Z, id = id } end
      end
    end
  end
  all = nil
  collectgarbage("collect")      -- free the ~5000 actor wrappers NOW, while every actor is still alive (stale wrappers of streamed-out actors crashed v3/v4)
  return rows, total
end

local function groundBelow(pawn, x, y, z)
  local ksl = UEHelpers.GetKismetSystemLibrary()
  if not valid(ksl) then return nil end
  local s, e = { X = x, Y = y, Z = z }, { X = x, Y = y, Z = z - 120000 }
  local color = { R = 0, G = 0, B = 0, A = 0 }
  local hit = {}
  local was = safe(function() return ksl:LineTraceSingle(pawn, s, e, 0, false, {}, 0, hit, true, color, color, 0.0) end)
  if not was then return nil end
  local ip = safe(function() return hit.ImpactPoint end) or safe(function() return hit.Location end)
  if ip and ip.Z then return ip.Z end
  return nil
end

local route
do
  local ok, r = pcall(dofile, DIR .. "\\route.lua")
  if ok and type(r) == "table" then route = r else log("could not load route.lua: " .. tostring(r)) end
end

local running, abort = false, false
local seenAll = {}

-- ONE timer chain only (v3 crashed because the 2 s vitals timer and the per-stop timers called ExecuteWithDelay from the
-- delay thread at the same moment; UE4SS's Lua registry is not thread-safe). Every second ONE delayed call hops to the
-- game thread, does all the work of that second, and only then schedules the next second.
local TICK_MS = 1000

local function fly()
  if running then log("already running"); return end
  if not route or #route == 0 then log("no route"); return end
  local startIndex = readProgress()
  if startIndex >= #route then log("the whole route is done (" .. #route .. " stops). Ctrl+F4 resets the progress."); return end
  local pc = UEHelpers.GetPlayerController()
  local pawn = valid(pc) and pc.Pawn or nil
  if not valid(pawn) then log("no player pawn yet"); return end
  local cm = safe(function() return pawn.CharacterMovement end)
  if not valid(cm) then log("the pawn has no CharacterMovement - not flying"); return end
  local home = pawn:K2_GetActorLocation()
  local homeVec = { X = home.X, Y = home.Y, Z = home.Z + 150 }
  local vnames
  local owners = {}
  for _, o in ipairs({ pawn, pc, safe(function() return pc.PlayerState end) }) do local p = o and valid(o) and pathOf(o) or nil; if p then owners[#owners + 1] = p; log("  player owner path: " .. p) end end
  vitals, vnames = findVitals(owners)
  log(string.format("=== chunk starts at stop %d of %d: home X %.0f Y %.0f Z %.0f", startIndex + 1, #route, home.X, home.Y, home.Z))
  log("vitals keeper: " .. (#vitals > 0 and table.concat(vnames, ", ") or "NOTHING FOUND (you are not protected!)"))
  log("vitals now: " .. vitalsText())
  running, abort = true, false
  safe(function() cm:SetMovementMode(5, 0) end)                           -- MOVE_Flying: hover instead of falling

  local i = startIndex
  local doneInChunk, newTotal = 0, 0
  local tk = 0                    -- seconds since the chunk started
  local t0 = 0                    -- tick of arrival at the current stop
  local phase = "next"            -- next | arrived | hover | scanned
  local h = nil
  local cooldown = nil            -- ticks left after finish() (vitals kept up while you land)

  local function finish(why)
    safe(function() pawn:K2_SetActorLocation(homeVec, false, {}, true) end)
    safe(function() cm:SetMovementMode(3, 0) end)                         -- MOVE_Falling: drop onto the ground at home, then walking resumes by itself
    running = false
    cooldown = 6
    log("=== chunk " .. why .. ": back home; stops done in this chunk " .. doneInChunk .. ", new ids " .. newTotal .. ", progress " .. readProgress() .. " of " .. #route .. "; vitals " .. vitalsText())
  end

  local function stopDone()
    writeProgress(i); doneInChunk = doneInChunk + 1; phase = "next"
  end

  local function step()
    tk = tk + 1
    if tk % 2 == 0 then topUp() end
    if cooldown then cooldown = cooldown - 1; return cooldown > 0 end    -- false ends the chain
    if phase == "next" then
      if abort then finish("aborted"); return true end
      if i >= #route then finish("finished the whole route"); return true end
      if doneInChunk >= CHUNK then finish("chunk complete"); return true end
      i = i + 1; h = route[i]; h.empty = false
      safe(function() pawn:K2_SetActorLocation({ X = h.x, Y = h.y, Z = HIGH_Z }, false, {}, true) end)
      log(string.format("--- stop %d/%d %s: X %.0f Y %.0f (arrived at z %.0f)", i, #route, h.name, h.x, h.y, HIGH_Z))
      t0 = tk; phase = "arrived"
    elseif phase == "arrived" and tk - t0 >= 4 then
      -- the ground below has had a moment to stream in: measure it and descend to HOVER above the first surface
      local g = h.z or groundBelow(pawn, h.x, h.y, HIGH_Z)             -- route.lua gives the highest saved object here: far more reliable than the trace
      if h.z then log(string.format('  ground reference from the saved worlds: z %.0f', g)) end
      if (not h.z) and g and g > 30000 then                                           -- a surface above 300 m is a sky/structure hit: look again beneath it
        local g2 = groundBelow(pawn, h.x, h.y, g - 200)
        if g2 then log(string.format("  surface at z %.0f looks like a structure: using the one beneath it at z %.0f", g, g2)); g = g2 end
      end
      if g == nil then log("  no surface found below - staying at " .. HIGH_Z .. " (nothing loads far from the ground)")
      else
        local z = g + HOVER
        if z < g + MIN_CLEARANCE then z = g + MIN_CLEARANCE end
        -- roof / ridge check: trace down from just under the flat plane at z 24387 and never hover inside a building or mountain
        local top = groundBelow(pawn, h.x, h.y, 24300)
        if top and top < 22000 and top + HOVER > z then
          log(string.format("  solid surface at z %.0f is higher than the planned hover z %.0f (building or ridge): raising to z %.0f", top, z, top + HOVER))
          z = top + HOVER
        end
        safe(function() pawn:K2_SetActorLocation({ X = h.x, Y = h.y, Z = z }, false, {}, true) end)
        log(string.format("  first surface below at z %.0f: now hovering at z %.0f (%.0f m above it)", g, z, (z - g) / 100))
      end
      phase = "hover"
    elseif phase == "hover" and tk - t0 >= 12 then
      local ok, err = pcall(function()
        local pl = pawn:K2_GetActorLocation()
        local rows, total = collect()
        local near = 0
        for _, r in ipairs(rows) do
          if not ignored(r.cls) then
            local dx, dy = r.x - pl.X, r.y - pl.Y
            if dx * dx + dy * dy <= EMPTY_RADIUS * EMPTY_RADIUS then near = near + 1 end
          end
        end
        h.empty = (near == 0)
        log(string.format("  +12 s: %d actors in the world, %d with a save id, %d real objects within %.0f m", total, #rows, near, EMPTY_RADIUS / 100))
      end)
      if not ok then log("  scan failed: " .. tostring(err)); h.empty = false end
      if h.empty then log("  nothing here: skipping the rest of the wait"); stopDone() else phase = "scanned" end
    elseif phase == "scanned" and h.probe and (tk - t0) % 10 == 0 and tk - t0 < math.floor((h.wait or 20000) / 1000) then
      -- long-wait test: do objects that are generated late (cars, trash cans) keep appearing while we hover here?
      local ok, err = pcall(function()
        local rows = collect()
        local new, cars = 0, 0
        for _, r in ipairs(rows) do
          if r.cls:find("Car_", 1, true) or r.cls:find("TrashCan", 1, true) or r.cls:find("CartOfTrash", 1, true) then cars = cars + 1 end
          if not seenAll[r.id] then
            seenAll[r.id] = true; new = new + 1
            buffer[#buffer + 1] = string.format("STOP%d|A|%s|%s|%.2f|%.2f|%.2f|%s", i, r.cls, r.full, r.x, r.y, r.z, r.id)
          end
        end
        newTotal = newTotal + new
        flush()
        log(string.format("  probe +%d s: %d with a save id, %d car/trash-can objects, %d new ids", tk - t0, #rows, cars, new))
      end)
      if not ok then log("probe failed: " .. tostring(err)) end
    elseif phase == "scanned" and tk - t0 >= math.floor((h.wait or 20000) / 1000) then
      local ok, err = pcall(function()
        local rows = collect()
        local new = 0
        for _, r in ipairs(rows) do
          if not seenAll[r.id] then
            seenAll[r.id] = true; new = new + 1
            buffer[#buffer + 1] = string.format("STOP%d|A|%s|%s|%.2f|%.2f|%.2f|%s", i, r.cls, r.full, r.x, r.y, r.z, r.id)
          end
        end
        newTotal = newTotal + new
        flush()
        log(string.format("  final: %d with a save id, %d new ids written; vitals %s", #rows, new, vitalsText()))
      end)
      if not ok then log("dump failed: " .. tostring(err)) end
      stopDone()
    end
    return true
  end

  local function tick()
    ExecuteWithDelay(TICK_MS, function()
      ExecuteInGameThread(function()
        local ok, more = pcall(step)
        if not ok then log("step failed: " .. tostring(more)); running = false; more = false end
        if more then tick() end
      end)
    end)
  end
  tick()
end

RegisterKeyBind(Key.F2, { ModifierKey.CONTROL }, function() ExecuteInGameThread(function() local ok, e = pcall(fly); if not ok then log("fly failed: " .. tostring(e)); running = false end end) end)
RegisterKeyBind(Key.F3, { ModifierKey.CONTROL }, function() abort = true; log("abort requested") end)
RegisterKeyBind(Key.F4, { ModifierKey.CONTROL }, function() writeProgress(0); log("progress reset: the next Ctrl+F2 starts at stop 1") end)
log("loaded - Ctrl+F2 flies the next " .. CHUNK .. " stops (" .. tostring(route and #route or 0) .. " in the route, " .. readProgress() .. " done), Ctrl+F3 aborts, Ctrl+F4 resets")
