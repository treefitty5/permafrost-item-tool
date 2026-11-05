-- ContainerLabels  (UE4SS Lua mod for the Permafrost Item Tool)  v2
-- White capitals, one word per line (FOOD / FATS / WOOD), hanging at a FIXED spot in front of each storage container (barrel, chest, bookshelf) of your base.
--   * Labels come from the Item Tool (Player tools > Container labels: labels.lua next to the Scripts folder, re-read every 15 s) and from labelling in the game itself:
--       Ctrl + right mouse button while you look at a container (within 6 m)  -> label mode: type the text (letters, digits, space), it appears on the container as you type
--       Enter, or Ctrl + right mouse button again  -> save      Esc -> cancel      Backspace -> delete a letter      Insert -> hang the label on the other side
--     The label hangs on the side of the container you were standing on when you saved it. Saving an empty text removes the label.
--     Delete clears the whole text, Ctrl + Backspace removes the last word (holding Backspace does not repeat: the game gives the mod one key press at a time).
--     In-game labels are written to ingame-labels.lua; the tool picks them up the next time you open or save the Container labels tab.
--   * A label shows while you are within SHOW_DIST of the container. Ctrl+F5 shows every container's number (the # column of the tool's list) for 25 m around you.
-- Nothing is saved in your world: a label is a temporary text actor. One timer chain only (UE4SS's Lua timers are not thread-safe). Log: ContainerLabels.log.
local TAG = "[ContainerLabels] "
local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\ContainerLabels"
end
local DIR = modDir()
local LOG_FILE, LABEL_FILE, INGAME_FILE = DIR .. "\\ContainerLabels.log", DIR .. "\\labels.lua", DIR .. "\\ingame-labels.lua"
local started = os.time()
local function log(msg)
  print(TAG .. msg .. "\n")
  local f = io.open(LOG_FILE, "a"); if f then f:write(string.format("%s (+%ds) %s\n", os.date("%H:%M:%S"), os.time() - started, msg)); f:close() end
end
pcall(function() local f = io.open(LOG_FILE, "a"); if f then f:write("---- ContainerLabels v2 loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)
local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end; return nil end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local UEHelpers = require("UEHelpers")

local SHOW_DIST    = 1000.0    -- cm: a label shows when you are this close to its container
local NUMBERS_DIST = 2500.0    -- cm: numbers mode
local AIM_DIST     = 600.0     -- cm: how far away a container can be and still be labelled in the game
local AIM_DEG      = 14.0      -- how close to the crosshair it has to be (degrees)
local TICK_MS      = 500
local REFRESH_TICKS = 5        -- containers are looked up again every 2.5 s
local RELOAD_TICKS  = 30       -- labels.lua is read again every 15 s
local TEXT_SIZE    = 8.0       -- cm: height of the letters
local HINT_SIZE    = 3.6
local MAX_CHARS    = 40
local COLOR        = { R = 255, G = 255, B = 255, A = 255 }
local HINT_COLOR   = { R = 170, G = 170, B = 170, A = 255 }
-- MID = height of the label's centre above the container's origin (cm), FRONT = how far out from its centre (cm). labels.lua can override per type: mid = { PlasticBarrel = 60 }, front = { ... }
local MID   = { PlasticBarrel = 55, Chest = 45, SmallChest = 35, LargeWoodenChest = 55, WoodenBookshelf = 120 }
local FRONT = { PlasticBarrel = 38, Chest = 50, SmallChest = 40, LargeWoodenChest = 60, WoodenBookshelf = 45 }
local DEFAULT_MID, DEFAULT_FRONT = 55, 42
local DEFAULT_TYPES = { "PlasticBarrel", "WoodenBookshelf", "Chest", "SmallChest", "LargeWoodenChest" }

local data = { items = {}, options = {}, generated = "" }
local edits = {}               -- in-game labels: { type, x, y, z, text, dir }
local numbersOn = false
local shown = {}               -- entry number -> { actor, text, dir }
local actors = {}              -- class name -> list of { a, x, y, z }
local tick = 0
local typing = nil             -- label mode: { target = {a,type,x,y,z}, buf, dir, actor, hint, entryN }

-- ------------------------------------------------------------------ small helpers
local function near(e, x, y, z) return math.abs(e.x - x) < 30 and math.abs(e.y - y) < 30 and math.abs(e.z - z) < 30 end
local function classOf(t) return "BP_" .. t .. "_C" end
local function typeOf(a) local c = safe(function() return a:GetClass():GetFName():ToString() end) or ""; return (c:gsub("^BP_", ""):gsub("_C$", "")) end
local function luaQuote(s) return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("[\r\n\t]", " ") .. '"' end

-- "Food / Fats wood" -> "FOOD\nFATS\nWOOD"
local function formatText(s)
  local words = {}
  for w in tostring(s):upper():gmatch("[^%s/,|]+") do words[#words + 1] = w end
  return table.concat(words, "\n")
end

-- ------------------------------------------------------------------ the label lists
local function findEdit(x, y, z) for i, ed in ipairs(edits) do if near(ed, x, y, z) then return ed, i end end; return nil end

-- everything that can carry a label: the tool's list (with in-game changes laid over it) plus containers labelled only in the game
local function entries()
  local out = {}
  for _, e in ipairs(data.items) do
    local ed = findEdit(e.x, e.y, e.z)
    out[#out + 1] = { type = e.type, x = e.x, y = e.y, z = e.z, text = ed and ed.text or (e.text or ""), dir = (ed and ed.dir) or e.dir, n = #out + 1 }
  end
  for _, ed in ipairs(edits) do
    local known = false
    for _, e in ipairs(data.items) do if near(e, ed.x, ed.y, ed.z) then known = true; break end end
    if not known then out[#out + 1] = { type = ed.type, x = ed.x, y = ed.y, z = ed.z, text = ed.text, dir = ed.dir, n = #out + 1 } end
  end
  return out
end

local function writeIngame()
  local sb = { "-- written by the ContainerLabels mod (labels typed in the game). The Item Tool merges this file and then deletes it.", "return { generated = " .. luaQuote(data.generated or "") .. ", items = {" }
  for _, ed in ipairs(edits) do
    sb[#sb + 1] = string.format("  { type = %s, x = %.3f, y = %.3f, z = %.3f, text = %s, dir = %.1f },", luaQuote(ed.type), ed.x, ed.y, ed.z, luaQuote(ed.text or ""), ed.dir or 0)
  end
  sb[#sb + 1] = "} }"
  local f = io.open(INGAME_FILE, "w"); if f then f:write(table.concat(sb, "\n") .. "\n"); f:close() end
end

local function loadIngame()
  local f = io.open(INGAME_FILE, "r"); if not f then return end; f:close()
  local ok, t = pcall(dofile, INGAME_FILE)
  if ok and type(t) == "table" and type(t.items) == "table" and (t.generated == (data.generated or "")) then
    edits = {}; for _, e in ipairs(t.items) do if e.x and e.y and e.z and e.type then edits[#edits + 1] = { type = e.type, x = e.x, y = e.y, z = e.z, text = e.text or "", dir = e.dir } end end
  end
end

local function loadLabels()
  local f = io.open(LABEL_FILE, "r"); if not f then return end; f:close()
  local ok, t = pcall(dofile, LABEL_FILE)
  if ok and type(t) == "table" and type(t.items) == "table" then
    local changed = (t.generated or "") ~= (data.generated or "")
    if #t.items ~= #data.items or changed then
      local n = 0; for _, e in ipairs(t.items) do if e.text and e.text ~= "" then n = n + 1 end end
      log(string.format("labels.lua read: %d containers, %d with a label", #t.items, n))
    end
    data = t; data.options = t.options or {}
    if changed then edits = {}; pcall(writeIngame) end        -- the tool saved again (after merging the in-game labels): its list is the truth now
  end
end

-- ------------------------------------------------------------------ finding the containers in the game
local function wantedClasses()
  local wanted, seen = {}, {}
  local function add(t) local c = classOf(t); if not seen[c] then seen[c] = true; wanted[#wanted + 1] = c end end
  for _, t in ipairs(DEFAULT_TYPES) do add(t) end
  for _, e in ipairs(data.items) do add(e.type) end
  for _, e in ipairs(edits) do add(e.type) end
  return wanted
end

local function refreshActors()
  actors = {}
  for _, c in ipairs(wantedClasses()) do
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
  local list = actors[classOf(e.type)]; if not list then return nil end
  for _, c in ipairs(list) do if near(c, e.x, e.y, e.z) and valid(c.a) then return c end end
  return nil
end

-- ------------------------------------------------------------------ where a label hangs (fixed)
local function labelSpot(e, c, dirDeg)
  local mid = (data.mid and data.mid[e.type]) or MID[e.type] or DEFAULT_MID
  local front = (data.front and data.front[e.type]) or FRONT[e.type] or DEFAULT_FRONT
  local d = dirDeg
  if d == nil then                         -- no side chosen yet: the side opposite to the way the container faces (the way it was placed)
    local rot = c and valid(c.a) and safe(function() return c.a:K2_GetActorRotation() end)
    d = ((rot and rot.Yaw) or 0) + 180
  end
  local r = math.rad(d)
  return { X = e.x + math.cos(r) * front, Y = e.y + math.sin(r) * front, Z = e.z + mid }, d
end

local function spawnText(spot, yaw, text, size, color)
  local world = UEHelpers.GetWorld(); local cls = StaticFindObject("/Script/Engine.TextRenderActor")
  if not valid(world) or not valid(cls) then return nil end
  local actor = safe(function() return world:SpawnActor(cls, spot, { Pitch = 0, Yaw = yaw, Roll = 0 }) end)
  if not valid(actor) then return nil end
  local tr = safe(function() return actor.TextRender end)
  if valid(tr) then
    safe(function() tr:K2_SetText(FText(text)) end)
    safe(function() tr:SetWorldSize(size) end)
    safe(function() tr:SetTextRenderColor(color) end)
    safe(function() tr:SetHorizontalAlignment(1) end)
    safe(function() tr:SetVerticalAlignment(1) end)
  end
  return actor
end
local function setText(actor, text) local tr = valid(actor) and safe(function() return actor.TextRender end); if valid(tr) then safe(function() tr:K2_SetText(FText(text)) end) end end

local function removeLabel(n)
  local s = shown[n]; if s and valid(s.actor) then safe(function() s.actor:K2_DestroyActor() end) end
  shown[n] = nil
end
local function removeAllLabels() for n in pairs(shown) do removeLabel(n) end end

-- ------------------------------------------------------------------ the periodic step
local function step()
  tick = tick + 1
  if tick % RELOAD_TICKS == 1 then loadLabels() end
  local list = entries()
  if #list == 0 then return end
  local pc = UEHelpers.GetPlayerController(); if not valid(pc) then return end
  local pawn = pc.Pawn; if not valid(pawn) then return end
  local p = safe(function() return pawn:K2_GetActorLocation() end); if not p then return end
  if tick % REFRESH_TICKS == 1 then refreshActors() end
  for _, e in ipairs(list) do
    local n = e.n
    local dx, dy, dz = e.x - p.X, e.y - p.Y, e.z - p.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local text = formatText(e.text or "")
    if numbersOn then text = "#" .. n .. ((text ~= "") and ("\n" .. text) or "") end
    local limit = numbersOn and NUMBERS_DIST or SHOW_DIST
    local cur = shown[n]
    local want = (text ~= "") and (d <= (cur and (limit + 300) or limit)) and not (typing and typing.entryN == n) and (data.options.floating ~= false)
    if not want then
      if cur then removeLabel(n) end
    else
      if cur and (not valid(cur.actor)) then shown[n] = nil; cur = nil end
      if cur and (cur.text ~= text or cur.dir ~= e.dir) then removeLabel(n); cur = nil end
      if not cur then
        local c = findContainer(e)            -- only containers that really exist in the game now get a label
        if c then
          local spot, dir = labelSpot(e, c, e.dir)
          local actor = spawnText(spot, dir, text, TEXT_SIZE, COLOR)
          if actor then shown[n] = { actor = actor, text = text, dir = e.dir } else log("could not spawn the label of #" .. n) end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ label mode (typing in the game)
local function setInputBlocked(block)
  local pc = UEHelpers.GetPlayerController(); if not valid(pc) then return end
  local pawn = pc.Pawn
  if block then
    if valid(pawn) then safe(function() pawn:DisableInput(pc) end) end
    safe(function() pc:DisableInput(pc) end); safe(function() pc:SetIgnoreMoveInput(true) end); safe(function() pc:SetIgnoreLookInput(true) end)
  else
    safe(function() pc:EnableInput(pc) end); if valid(pawn) then safe(function() pawn:EnableInput(pc) end) end
    safe(function() pc:SetIgnoreMoveInput(false) end); safe(function() pc:SetIgnoreLookInput(false) end)
  end
end

local function aimedContainer()
  local pc = UEHelpers.GetPlayerController(); if not valid(pc) then return nil end
  local cam = pc.PlayerCameraManager; if not valid(cam) then return nil end
  local cl = safe(function() return cam:GetCameraLocation() end); local kml = UEHelpers.GetKismetMathLibrary()
  local fwd = safe(function() return kml:GetForwardVector(cam:GetCameraRotation()) end); if not cl or not fwd then return nil end
  refreshActors()
  local best, bestAng
  for cn, list in pairs(actors) do
    for _, c in ipairs(list) do
      if valid(c.a) then
        local vx, vy, vz = c.x - cl.X, c.y - cl.Y, (c.z + 50) - cl.Z
        local len = math.sqrt(vx * vx + vy * vy + vz * vz)
        if len > 1 and len <= AIM_DIST then
          local ang = math.deg(math.acos(math.max(-1, math.min(1, (vx * fwd.X + vy * fwd.Y + vz * fwd.Z) / len))))
          if ang <= AIM_DEG and (not bestAng or ang < bestAng) then best, bestAng = { a = c.a, type = typeOf(c.a), x = c.x, y = c.y, z = c.z }, ang end
        end
      end
    end
  end
  return best
end

local function currentText(t)
  for _, e in ipairs(entries()) do if near(e, t.x, t.y, t.z) then return e.text or "", e.dir, e.n end end
  return "", nil, nil
end

local function previewText(buf) return formatText(buf .. "_") end

local function renderTyping()
  if not typing then return end
  local text = previewText(typing.buf)
  if valid(typing.actor) then setText(typing.actor, text) end
end

local function stopTyping(save)
  if not typing then return end
  local t = typing; typing = nil
  if valid(t.actor) then safe(function() t.actor:K2_DestroyActor() end) end
  if valid(t.hint) then safe(function() t.hint:K2_DestroyActor() end) end
  setInputBlocked(false)
  if save then
    local text = (t.buf or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local _, idx = findEdit(t.target.x, t.target.y, t.target.z)
    local ed = { type = t.target.type, x = t.target.x, y = t.target.y, z = t.target.z, text = text, dir = t.dir }
    if idx then edits[idx] = ed else edits[#edits + 1] = ed end
    writeIngame()
    removeAllLabels()
    log(string.format("label of the %s at (%.0f, %.0f, %.0f) saved: %s", t.target.type, t.target.x, t.target.y, t.target.z, text == "" and "(removed)" or text))
  else
    log("label mode cancelled")
  end
end

local function startTyping()
  if typing then return end
  local target = aimedContainer()
  if not target then log("label mode: no container within 6 m under the crosshair"); return end
  local pc = UEHelpers.GetPlayerController(); local pawn = valid(pc) and pc.Pawn or nil
  local pl = valid(pawn) and safe(function() return pawn:K2_GetActorLocation() end) or nil
  if not pl then return end
  local buf, _, n = currentText(target)
  -- the label hangs on the side you stand on
  local dir = math.deg(math.atan(pl.Y - target.y, pl.X - target.x))
  local e = { type = target.type, x = target.x, y = target.y, z = target.z }
  local spot, d = labelSpot(e, target, dir)
  removeAllLabels()
  typing = { target = target, buf = buf, dir = dir, entryN = n or -1, started = os.time(), last = os.time() }
  typing.actor = spawnText(spot, d, previewText(buf), TEXT_SIZE, COLOR)
  local mid = (data.mid and data.mid[target.type]) or MID[target.type] or DEFAULT_MID
  typing.hint = spawnText({ X = spot.X, Y = spot.Y, Z = spot.Z - 20 }, d, "ENTER = SAVE   ESC = CANCEL   INSERT = OTHER SIDE", HINT_SIZE, HINT_COLOR)
  if not typing.actor then typing = nil; log("label mode: could not draw the text"); return end
  setInputBlocked(true)
  log(string.format("label mode started for the %s at (%.0f, %.0f, %.0f)", target.type, target.x, target.y, target.z))
end

local function typed(ch)
  if not typing then return end
  typing.last = os.time()
  if #typing.buf < MAX_CHARS then typing.buf = typing.buf .. ch; renderTyping() end
end
local function backspace() if typing and #typing.buf > 0 then typing.buf = typing.buf:sub(1, #typing.buf - 1); renderTyping() end end
local function flipSide()
  if not typing then return end
  typing.dir = (typing.dir + 180) % 360
  local e = { type = typing.target.type, x = typing.target.x, y = typing.target.y, z = typing.target.z }
  local spot, d = labelSpot(e, typing.target, typing.dir)
  if valid(typing.actor) then safe(function() typing.actor:K2_SetActorLocation(spot, false, {}, true); typing.actor:K2_SetActorRotation({ Pitch = 0, Yaw = d, Roll = 0 }, false) end) end
  if valid(typing.hint) then safe(function() typing.hint:K2_SetActorLocation({ X = spot.X, Y = spot.Y, Z = spot.Z - 20 }, false, {}, true); typing.hint:K2_SetActorRotation({ Pitch = 0, Yaw = d, Roll = 0 }, false) end) end
end

-- key bindings (a key press reaches us whatever the game does with it; the game's own input is switched off while you type)
local function guarded(fn, ...) local a = { ... }; ExecuteInGameThread(function() local ok, err = pcall(function() fn(table.unpack(a)) end); if not ok then log("error: " .. tostring(err)); pcall(stopTyping, false) end end) end
local function bind(name, fn, mods)
  local k = Key and Key[name]; if not k then return false end
  local ok = pcall(function() if mods then RegisterKeyBind(k, mods, fn) else RegisterKeyBind(k, fn) end end)
  return ok
end

for i = 0, 25 do local ch = string.char(65 + i); bind(ch, function() if typing then guarded(typed, ch) end end) end
local DIGITS = { "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }
for i, nm in ipairs(DIGITS) do local ch = tostring(i - 1); bind(nm, function() if typing then guarded(typed, ch) end end) end
bind("SPACE", function() if typing then guarded(typed, " ") end end)
bind("OEM_MINUS", function() if typing then guarded(typed, "-") end end)
bind("OEM_PERIOD", function() if typing then guarded(typed, ".") end end)
bind("OEM_TWO", function() if typing then guarded(typed, "/") end end)
bind("BACKSPACE", function() if typing then guarded(backspace) end end)
-- holding a key does not repeat (a key press reaches the mod once), so two shortcuts delete faster: Delete clears the whole text, Ctrl + Backspace removes the last word
local function clearAll() if typing then typing.last = os.time(); typing.buf = ""; renderTyping() end end
local function backWord() if typing then typing.last = os.time(); typing.buf = typing.buf:gsub("%s+$", ""):gsub("[^%s/,]+$", ""); renderTyping() end end
bind("DEL", function() if typing then guarded(clearAll) end end)
bind("DELETE", function() if typing then guarded(clearAll) end end)
bind("BACKSPACE", function() if typing then guarded(backWord) end end, { ModifierKey.CONTROL })
bind("INS", function() if typing then guarded(flipSide) end end)
bind("RETURN", function() if typing then guarded(stopTyping, true) end end)
bind("ESCAPE", function() if typing then guarded(stopTyping, false) end end)
local startOk = bind("RIGHT_MOUSE_BUTTON", function() guarded(function() if typing then stopTyping(true) else startTyping() end end) end, { ModifierKey.CONTROL })
bind("F5", function() numbersOn = not numbersOn; removeAllLabels(); log("numbers " .. (numbersOn and "ON (every container within 25 m shows its number)" or "OFF")) end, { ModifierKey.CONTROL })

loadLabels(); loadIngame()
LoopAsync(TICK_MS, function()
  ExecuteInGameThread(function()
    local ok, err = pcall(step); if not ok then log("step failed: " .. tostring(err)) end
    if typing and (os.time() - typing.last > 120) then log("label mode timed out"); pcall(stopTyping, false) end
  end)
  return false
end)
log(string.format("loaded; %d containers in labels.lua, %d labelled in the game. Ctrl+right-click on a container = label it (%s), Ctrl+F5 = numbers.", #data.items, #edits, startOk and "key ok" or "RIGHT MOUSE KEY NOT AVAILABLE"))
