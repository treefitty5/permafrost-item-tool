-- GroundSnap  (UE4SS Lua mod for the Permafrost Item Tool)
-- After a teleport the tool cannot know the exact ground height: it only has estimates from the atlas flights. This mod asks the GAME where the ground really is.
-- The tool writes request.lua next to the Scripts folder when you teleport to an estimated height:
--   return { version = 1, x = 35691, y = -76695, z = 1000, created = 1793000000, label = "Location1" }
-- When the loaded world has you within 15 m (sideways) of that spot, the mod
--   1. holds you in the air (no falling through ground that is still streaming in),
--   2. traces down from above the estimate until the game's ground has loaded and two readings agree,
--   3. puts you just above that ground and lets you drop, then watches a few seconds in case you sank,
--   4. deletes the request and writes the result to status.txt (the tool shows it).
-- Without a request the mod does nothing. Everything it does is written to GroundSnap.log in the mod folder.
local TAG = "[GroundSnap] "
local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\GroundSnap"
end
local DIR = modDir()
local LOG_FILE, REQ_FILE, STATUS_FILE = DIR .. "\\GroundSnap.log", DIR .. "\\request.lua", DIR .. "\\status.txt"
local started = os.time()
local function log(msg)
  print(TAG .. msg .. "\n")
  local f = io.open(LOG_FILE, "a"); if f then f:write(string.format("%s (+%ds) %s\n", os.date("%H:%M:%S"), os.time() - started, msg)); f:close() end
end
pcall(function() local f = io.open(LOG_FILE, "a"); if f then f:write("---- GroundSnap loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)
local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end; return nil end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local function writeStatus(msg) local f = io.open(STATUS_FILE, "w"); if f then f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. msg .. "\n"); f:close() end end

local UEHelpers = require("UEHelpers")

local NEAR_CM        = 1500     -- the player must be this close (sideways) to the requested spot to count as "just teleported there"
local GIVE_UP_S      = 120      -- seconds to wait for the ground to load
local LOW_START      = 1500     -- first trace starts this far above the estimated height
local HIGH_START     = 10000    -- second trace starts this far above it (catches ground higher than the estimate)
local SKY_PLANE      = 21500    -- never start a trace above this: the map has a flat surface at about z 24387
local ABOVE_GROUND   = 30       -- cm of air between the capsule's bottom and the ground when placing the player
local TICK_MS        = 500

local function removeRequest() pcall(os.remove, REQ_FILE) end
local function readRequest()
  local f = io.open(REQ_FILE, "r"); if not f then return nil end; f:close()
  local ok, t = pcall(dofile, REQ_FILE)
  if ok and type(t) == "table" and tonumber(t.x) and tonumber(t.y) and tonumber(t.z) then return t end
  return nil
end

-- the first surface below (x, y, z): its height, or nil when the game has no collision there (yet)
local function surfaceBelow(pawn, x, y, z)
  local ksl = UEHelpers.GetKismetSystemLibrary(); if not valid(ksl) then return nil end
  local s, e = { X = x, Y = y, Z = z }, { X = x, Y = y, Z = z - 60000 }
  local color = { R = 0, G = 0, B = 0, A = 0 }
  local hit = {}
  local was = safe(function() return ksl:LineTraceSingle(pawn, s, e, 0, false, {}, 0, hit, true, color, color, 0.0) end)
  if not was then return nil end
  local ip = safe(function() return hit.ImpactPoint end) or safe(function() return hit.Location end)
  if ip and ip.Z then return ip.Z end
  return nil
end

-- which height is the ground? A = trace from a little above the estimate, B = trace from far above it.
-- Same answer: that is the ground. B higher than A: something stands above (a roof, a ledge) or the ground is higher than the estimate: take the top one when it is
-- within 60 m of the estimate, else the one near the estimate. B only: the estimate was below the ground (the case that put players under the map).
local function chooseGround(estZ, a, b)
  if a and b then
    if math.abs(b - a) <= 100 then return b, "both traces agree" end
    if b > a then
      if b - estZ <= 6000 then return b, string.format("something higher above (%.0f m over the lower surface): standing on top of it", (b - a) / 100) end
      if a >= estZ - 1500 then return a, "the top surface is far above the estimate: using the one near it" end
      return b, "only the top surface is plausible"
    end
    return a, "the lower trace found a higher surface than the top trace (odd): using the higher"
  end
  if b then return b, "the estimate was below the ground" end
  if a then return a, "only the near trace found a surface" end
  return nil, "no surface yet"
end

local function halfHeight(pawn)
  local h = safe(function() return pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
  if type(h) == "number" and h > 20 and h < 400 then return h end
  return 96
end

local req, phase, ticks = nil, "idle", 0
local cm, lastG, agree, snaps, groundZ, estZ = nil, nil, 0, 0, nil, 0
local watchLeft, activeTicks = 0, 0

local function finish(msg)
  log(msg); writeStatus(msg)
  if cm and valid(cm) and phase ~= "idle" then safe(function() cm:SetMovementMode(3, 0) end) end
  removeRequest(); req, phase, cm, lastG, agree, snaps, groundZ, watchLeft, activeTicks = nil, "idle", nil, nil, 0, 0, nil, 0, 0
end

local function step()
  if phase == "idle" then
    local r = readRequest(); if not r then return end
    local pc = UEHelpers.GetPlayerController(); local pawn = valid(pc) and pc.Pawn or nil
    if not valid(pawn) then return end
    local loc = safe(function() return pawn:K2_GetActorLocation() end); if not loc then return end
    local d = math.sqrt((loc.X - r.x) ^ 2 + (loc.Y - r.y) ^ 2)
    if d > NEAR_CM then return end   -- not there (main menu, a different save, an old request): keep waiting
    req, estZ = r, tonumber(r.z) + 0.0
    cm = safe(function() return pawn.CharacterMovement end)
    if valid(cm) then safe(function() cm:SetMovementMode(5, 0) end) end   -- MOVE_Flying: hold still while the ground streams in
    phase, activeTicks = "find", 0
    log(string.format("request for %s: X %.0f Y %.0f, tool height Z %.0f (%s); you are at Z %.0f; holding you while the ground loads", tostring(r.label or "?"), r.x, r.y, estZ, os.date("%H:%M:%S", tonumber(r.created) or os.time()), loc.Z))
    return
  end
  local pc = UEHelpers.GetPlayerController(); local pawn = valid(pc) and pc.Pawn or nil
  if not valid(pawn) then activeTicks = activeTicks + 1; if activeTicks > GIVE_UP_S * 1000 / TICK_MS then finish("gave up: no player pawn") end; return end
  local loc = safe(function() return pawn:K2_GetActorLocation() end); if not loc then return end
  activeTicks = activeTicks + 1
  if phase == "find" then
    if math.sqrt((loc.X - req.x) ^ 2 + (loc.Y - req.y) ^ 2) > 3 * NEAR_CM then finish("stopped: you are no longer at the requested spot"); return end
    if not valid(cm) then cm = safe(function() return pawn.CharacterMovement end) end
    if valid(cm) then safe(function() cm:SetMovementMode(5, 0) end) end
    local a = surfaceBelow(pawn, loc.X, loc.Y, estZ + LOW_START)
    local b = surfaceBelow(pawn, loc.X, loc.Y, math.min(estZ + HIGH_START, SKY_PLANE))
    local g, why = chooseGround(estZ, a, b)
    if activeTicks % 4 == 1 then log(string.format("  tick %d: near trace %s, far trace %s -> %s", activeTicks, a and string.format("%.0f", a) or "-", b and string.format("%.0f", b) or "-", g and string.format("ground %.0f (%s)", g, why) or why)) end
    if g then
      if lastG and math.abs(g - lastG) <= 50 then agree = agree + 1 else agree = 0 end
      lastG = g
      if agree >= 2 then
        groundZ = g; local z = g + halfHeight(pawn) + ABOVE_GROUND
        safe(function() pawn:K2_SetActorLocation({ X = loc.X, Y = loc.Y, Z = z }, false, {}, true) end)
        if valid(cm) then safe(function() cm:SetMovementMode(3, 0) end) end   -- MOVE_Falling: drop the last few centimetres, walking resumes by itself
        snaps = snaps + 1; phase = "watch"; watchLeft = 16
        log(string.format("ground found at Z %.0f (%s); the tool's height was Z %.0f (%+.1f m); placed you at Z %.0f", g, why, estZ, (g - estZ) / 100, z))
      end
    elseif activeTicks > GIVE_UP_S * 1000 / TICK_MS then
      finish(string.format("gave up after %d s: the game never produced ground at X %.0f Y %.0f; you were let go where you are (use Undo in the tool if you are stuck)", GIVE_UP_S, loc.X, loc.Y))
    end
  elseif phase == "watch" then
    watchLeft = watchLeft - 1
    if loc.Z < groundZ - 60 then   -- sank below the ground we measured (it was not solid yet): put you back up, up to 3 times
      if snaps >= 3 then finish(string.format("you sank below the measured ground again (Z %.0f, ground %.0f); giving up after 3 tries", loc.Z, groundZ)); return end
      snaps = snaps + 1; phase = "find"; agree = 0; lastG = nil; activeTicks = 0
      if valid(cm) then safe(function() cm:SetMovementMode(5, 0) end) end
      log(string.format("you sank to Z %.0f (ground %.0f): measuring again (try %d)", loc.Z, groundZ, snaps)); return
    end
    if watchLeft <= 0 then
      finish(string.format("done: the real ground here is Z %.0f; the tool's height was Z %.0f (%+.1f m). You are at Z %.0f.", groundZ, estZ, (groundZ - estZ) / 100, loc.Z))
    end
  end
end

-- ONE timer chain (a second chain at the same time crashed another mod): every TICK_MS, hop to the game thread, do the work, then schedule the next tick
local function tick()
  ExecuteWithDelay(TICK_MS, function()
    ExecuteInGameThread(function()
      ticks = ticks + 1
      local ok, e = pcall(step); if not ok then log("step failed: " .. tostring(e)); if phase ~= "idle" then finish("stopped after an error: " .. tostring(e)) end end
      tick()
    end)
  end)
end
log("loaded; waiting for a request in " .. REQ_FILE)
tick()
