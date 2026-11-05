-- ContainerLabels  (UE4SS Lua mod for the Permafrost Item Tool)
-- Shows the labels you gave your storage containers (barrels, chests, bookshelves) in the Item Tool's "Container labels" tab as white text hanging in front of each one
-- (one word per line, capitals: FOOD / FATS / WOOD).
--   * The tool writes labels.lua next to the Scripts folder (position, type and text of every container of your base); the mod re-reads it every 15 seconds.
--   * A label is drawn only while you are within SHOW_DIST of its container, hangs on the side you are standing on and always turns to face you. Nothing is saved: the text is a temporary actor.
--   * Ctrl+F5 switches "numbers" on or off: every container within 25 m then also shows its number from the tool's list, so you can tell which row is which barrel.
-- One timer chain only (UE4SS's Lua timers are not thread-safe): the same pattern as the other mods. Log: ContainerLabels.log in the mod folder.
local TAG = "[ContainerLabels] "
local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\ContainerLabels"
end
local DIR = modDir()
local LOG_FILE, LABEL_FILE = DIR .. "\\ContainerLabels.log", DIR .. "\\labels.lua"
local started = os.time()
local function log(msg)
  print(TAG .. msg .. "\n")
  local f = io.open(LOG_FILE, "a"); if f then f:write(string.format("%s (+%ds) %s\n", os.date("%H:%M:%S"), os.time() - started, msg)); f:close() end
end
pcall(function() local f = io.open(LOG_FILE, "a"); if f then f:write("---- ContainerLabels loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)
local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end; return nil end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local UEHelpers = require("UEHelpers")

local SHOW_DIST    = 1000.0    -- cm: a label appears when you are this close to its container
local HIDE_DIST    = 1300.0    -- cm: and is removed again beyond this (the gap keeps it from flickering)
local NUMBERS_DIST = 2500.0    -- cm: in numbers mode every container this close shows its number
local TICK_MS      = 500
local REFRESH_TICKS = 5        -- containers are looked up again every 2.5 s
local RELOAD_TICKS  = 30       -- labels.lua is read again every 15 s
local TEXT_SIZE    = 16.0      -- cm: height of the letters
local COLOR        = { R = 255, G = 255, B = 255, A = 255 }   -- white
-- The label hangs IN FRONT of the container (on the side you are standing on), at about half its height; the text is one word per line, in capitals.
-- MID = height above the container's origin (cm), FRONT = how far out from the container's centre (cm). labels.lua can override per type: mid = { PlasticBarrel = 60 }, front = { ... }
local MID   = { PlasticBarrel = 55, Chest = 45, SmallChest = 35, LargeWoodenChest = 55, WoodenBookshelf = 120 }
local FRONT = { PlasticBarrel = 50, Chest = 55, SmallChest = 45, LargeWoodenChest = 65, WoodenBookshelf = 50 }
local DEFAULT_MID, DEFAULT_FRONT = 55, 50
local MOVE_DEG = 20.0           -- the label slides round the container only when you have moved this many degrees round it (it still turns to face you all the time)

local data = { items = {}, offsets = {} }
local numbersOn = false
local shown = {}               -- entry number -> { actor = text actor, text = what it shows }
local actors = {}              -- class name -> list of { a = actor, x, y, z }
local tick = 0

local function loadLabels()
  local f = io.open(LABEL_FILE, "r"); if not f then return end; f:close()
  local ok, t = pcall(dofile, LABEL_FILE)
  if ok and type(t) == "table" and type(t.items) == "table" then
    if #t.items ~= #data.items then log(string.format("labels.lua read: %d containers, %d with a label", #t.items, (function() local n = 0; for _, e in ipairs(t.items) do if e.text and e.text ~= "" then n = n + 1 end end; return n end)())) end
    data = t; data.offsets = t.offsets or {}
  end
end

local function classOf(e) return "BP_" .. e.type .. "_C" end

local function refreshActors()
  local wanted, seen = {}, {}
  for _, e in ipairs(data.items) do local c = classOf(e); if not seen[c] then seen[c] = true; wanted[#wanted + 1] = c end end
  actors = {}
  for _, c in ipairs(wanted) do
    local list = {}
    for _, a in ipairs(safe(function() return FindAllOf(c) end) or {}) do
      if valid(a) then
        local l = safe(function() return a:K2_GetActorLocation() end)
        if l then list[#list + 1] = { a = a, x = l.X, y = l.Y, z = l.Z } end
      end
    end
    actors[c] = list
  end
end

local function findContainer(e)
  local list = actors[classOf(e)]; if not list then return nil end
  for _, c in ipairs(list) do
    if math.abs(c.x - e.x) < 30 and math.abs(c.y - e.y) < 30 and math.abs(c.z - e.z) < 30 and valid(c.a) then return c end
  end
  return nil
end

local function removeLabel(n)
  local s = shown[n]; if s and valid(s.actor) then safe(function() s.actor:K2_DestroyActor() end) end
  shown[n] = nil
end

-- "Food / Fats wood" -> "FOOD\nFATS\nWOOD": one word under another, capitals
local function formatText(s)
  local words = {}
  for w in tostring(s):upper():gmatch("[^%s/,|]+") do words[#words + 1] = w end
  return table.concat(words, "\n")
end

-- where the label hangs: in front of the container, on the side of the camera, at mid height
local function labelSpot(e, cx, cy)
  local mid = (data.mid and data.mid[e.type]) or MID[e.type] or DEFAULT_MID
  local front = (data.front and data.front[e.type]) or FRONT[e.type] or DEFAULT_FRONT
  local dx, dy = cx - e.x, cy - e.y
  local len = math.sqrt(dx * dx + dy * dy); if len < 1 then dx, dy, len = 1, 0, 1 end
  local ux, uy = dx / len, dy / len
  return { X = e.x + ux * front, Y = e.y + uy * front, Z = e.z + mid }, math.deg(math.atan(uy, ux))
end

local function spawnLabel(n, e, text, cx, cy)
  local world = UEHelpers.GetWorld(); local cls = StaticFindObject("/Script/Engine.TextRenderActor")
  if not valid(world) or not valid(cls) then return end
  local spot, bearing = labelSpot(e, cx, cy)
  local actor = safe(function() return world:SpawnActor(cls, spot, { Pitch = 0, Yaw = bearing, Roll = 0 }) end)
  if not valid(actor) then log("could not spawn a label for #" .. n); return end
  local tr = safe(function() return actor.TextRender end)
  if valid(tr) then
    safe(function() tr:SetMobility(2) end)
    safe(function() tr:K2_SetText(FText(text)) end)
    safe(function() tr:SetWorldSize(TEXT_SIZE) end)
    safe(function() tr:SetTextRenderColor(COLOR) end)
    safe(function() tr:SetHorizontalAlignment(1) end)
    safe(function() tr:SetVerticalAlignment(1) end)
  end
  shown[n] = { actor = actor, text = text, tr = tr, bearing = bearing }
end

local function step()
  tick = tick + 1
  if tick % RELOAD_TICKS == 1 then loadLabels() end
  if #data.items == 0 then return end
  local pc = UEHelpers.GetPlayerController(); if not valid(pc) then return end
  local pawn = pc.Pawn; if not valid(pawn) then return end
  local p = safe(function() return pawn:K2_GetActorLocation() end); if not p then return end
  if tick % REFRESH_TICKS == 1 then refreshActors() end
  local cam = pc.PlayerCameraManager
  local cl = valid(cam) and safe(function() return cam:GetCameraLocation() end) or p
  for n, e in ipairs(data.items) do
    local dx, dy, dz = e.x - p.X, e.y - p.Y, e.z - p.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local text = formatText(e.text or "")
    if numbersOn then text = "#" .. n .. ((text ~= "") and ("\n" .. text) or "") end
    local limit = numbersOn and NUMBERS_DIST or SHOW_DIST
    local cur = shown[n]
    if text == "" or d > (cur and (limit + 300) or limit) then
      if cur then removeLabel(n) end
    else
      if cur and (not valid(cur.actor)) then shown[n] = nil; cur = nil end
      if cur and cur.text ~= text then removeLabel(n); cur = nil end
      if not cur then
        local c = findContainer(e)            -- only containers that really exist in the game now get a label
        if c then spawnLabel(n, e, text, cl.X, cl.Y); cur = shown[n] end
      end
      if cur and valid(cur.actor) then
        local spot, bearing = labelSpot(e, cl.X, cl.Y)
        local diff = math.abs(((bearing - (cur.bearing or bearing)) + 180) % 360 - 180)
        if diff > MOVE_DEG then                -- you walked round the container: slide the label to your side
          safe(function() cur.actor:K2_SetActorLocation(spot, false, {}, true) end); cur.bearing = bearing
        end
        local pl = safe(function() return cur.actor:K2_GetActorLocation() end) or spot
        local yaw = math.deg(math.atan(cl.Y - pl.Y, cl.X - pl.X))          -- always turn to face the camera
        safe(function() cur.actor:K2_SetActorRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false) end)
      end
    end
  end
end

LoopAsync(TICK_MS, function()
  ExecuteInGameThread(function() local ok, err = pcall(step); if not ok then log("step failed: " .. tostring(err)) end end)
  return false
end)

RegisterKeyBind(Key.F5, { ModifierKey.CONTROL }, function()
  numbersOn = not numbersOn
  for n in pairs(shown) do removeLabel(n) end
  log("numbers " .. (numbersOn and "ON (every container within 25 m shows its number)" or "OFF"))
end)

loadLabels()
log(string.format("loaded; %d containers listed in labels.lua. Ctrl+F5 shows or hides the numbers.", #data.items))
