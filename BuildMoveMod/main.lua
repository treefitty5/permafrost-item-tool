-- BuildMove  (UE4SS Lua mod, installed by the Permafrost Item Tool's "Build move" button)
--
-- Lets you pick up a placed building part (furniture, workbenches, storage, lights, braziers, beds, planters...) and put it down somewhere else,
-- keeping its health, contents and variation: the SAME object is moved, nothing is rebuilt, no materials are used or refunded.
-- Structural pieces (foundations, walls, floors, roofs, doors, beams, stairs...) are refused: they are tied to the building grid.
--
--   Q wheel -> Move   look at a building part, open the wheel and choose Move: you now hold it and it follows your crosshair.
--             Left click puts it down (or choose Move / press F7 again).
--   F7        the same as choosing Move in the wheel: pick up / put down.
--   Page Up / Page Down   turn the held part 15 degrees left / right (while holding)
--   F6        cancel: the held part jumps back to where it was
--   Q wheel   the mod also tries to add a "Move" entry to the Q wheel (see wheelEntry below). If the wheel cannot be extended, F7 still works.
--
-- Everything the mod does is written to UE4SS.log and to BuildMove.log in the mod folder (search for [BuildMove]).
-- To switch it off: "BuildMove : 0" in Mods\mods.txt. Your save is not touched by the mod; the part simply sits at its new position when the game saves.

local UEHelpers = require("UEHelpers")
local TAG = "[BuildMove] "

local function modDir()
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$") or "Mods\\BuildMove"
end
local DIR = modDir()
local LOG_FILE = DIR .. "\\BuildMove.log"
local function log(msg)
  print(TAG .. msg .. "\n")
  local f = io.open(LOG_FILE, "a"); if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n"); f:close() end
end
pcall(function() local f = io.open(LOG_FILE, "w"); if f then f:write("BuildMove log, started " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"); f:close() end end)

-- ---------------------------------------------------------------- settings
local ROTATE_STEP = 15.0         -- degrees per Page Up / Page Down
local MAX_REACH = 1200.0         -- how far (cm) the held part can be carried from you
local TRACE_DISTANCE = 900.0     -- how far (cm) you can reach to pick a part up (the game's build trace is 900)
local wheelEntry = { enabled = true, name = "Move" }
-- grid types that may be moved (EBuildGridType: 0 None, 3 Furniture). Everything else is structural.
local MOVABLE_GRID = { [0] = true, [3] = true }

-- ---------------------------------------------------------------- helpers
local function safe(fn, ...) local ok, a, b, c = pcall(fn, ...); if ok then return a, b, c end; return nil end
local function nameOf(o) return safe(function() return o:GetFullName() end) or "?" end

-- the trace hands back the thing that was hit, which is usually a COMPONENT (e.g. the StaticMesh of a barrel): go to the actor that owns it
local function asActor(o)
  if not o or not safe(function() return o:IsValid() end) then return nil end
  if safe(function() return o:IsA("/Script/Engine.ActorComponent") end) then
    local ow = safe(function() return o:GetOwner() end)
    if ow and safe(function() return ow:IsValid() end) then return ow end
  end
  return o
end
local function hitActor(hit)
  local a = safe(function() return hit.HitObjectHandle.ReferenceObject:Get() end)
  a = asActor(a); if a then return a end
  a = safe(function() return hit.HitObjectHandle.Actor:Get() end)
  return asActor(a)
end

-- line trace from the camera; returns hit(bool), hitResult, actor, startVec, dirVec
local function trace(distance, ignore)
  local pc = UEHelpers.GetPlayerController()
  if not pc or not pc:IsValid() then return nil end
  local ksl, kml = UEHelpers.GetKismetSystemLibrary(), UEHelpers.GetKismetMathLibrary()
  local cam = pc.PlayerCameraManager
  local s = cam:GetCameraLocation(); local fwd = kml:GetForwardVector(cam:GetCameraRotation())
  local e = { X = s.X + fwd.X * distance, Y = s.Y + fwd.Y * distance, Z = s.Z + fwd.Z * distance }
  local color = { R = 0, G = 0, B = 0, A = 0 }; local hit = {}
  local was = ksl:LineTraceSingle(pc.Pawn, s, e, 0, false, ignore or {}, 0, hit, true, color, color, 0.0)
  if was then return true, hit, hitActor(hit), s, fwd end
  return false, hit, nil, s, fwd
end

local function isBuildPart(a)
  return a and safe(function() return a:IsA("/Script/Permafrost.BuildPartBase") end) == true
end

-- what kind of part is it? returns id, gridType (either may be nil if the game does not let us read it)
local function partInfo(a)
  local cfg = safe(function() return a.BuildConfigLoaded end)
  if not cfg or not safe(function() return cfg:IsValid() end) then
    cfg = safe(function() return a:GetBuildPartConfig() end)
  end
  local id, grid
  if cfg and safe(function() return cfg:IsValid() end) then
    id = safe(function() return cfg:GetID():ToString() end) or safe(function() return tostring(cfg:GetID()) end)
    grid = safe(function() return cfg:GetGridType() end)
    if grid == nil then grid = safe(function() return a:GetBuildGridType() end) end
  else
    id = safe(function() return a:GetBuildPartName():ToString() end)
    grid = safe(function() return a:GetBuildGridType() end)
  end
  return id, (type(grid) == "number") and grid or nil
end

-- ---------------------------------------------------------------- grab / carry / drop
local grab = nil   -- { actor, origLoc, origRot, yaw, zOffset, id }

local function setLoc(a, loc) return safe(function() a:K2_SetActorLocation(loc, false, {}, true) end) end
local function setRot(a, rot) return safe(function() a:K2_SetActorRotation(rot, false) end) end

local function groundOffset(a, loc)
  -- how high above the floor does the part's origin sit? (so a lamp keeps its feet on the floor when carried)
  local ksl = UEHelpers.GetKismetSystemLibrary(); local pc = UEHelpers.GetPlayerController()
  local hit = {}; local color = { R = 0, G = 0, B = 0, A = 0 }
  local s = { X = loc.X, Y = loc.Y, Z = loc.Z + 30.0 }; local e = { X = loc.X, Y = loc.Y, Z = loc.Z - 400.0 }
  local was = safe(function() return ksl:LineTraceSingle(pc.Pawn, s, e, 0, false, { a }, 0, hit, true, color, color, 0.0) end)
  if was then local z = safe(function() return hit.ImpactPoint.Z end); if z then return math.max(0.0, math.min(300.0, loc.Z - z)) end end
  return 0.0
end

-- ---------------------------------------------------------------- obstruction check
-- The game refuses to place a part where it would overlap something. That check lives in native code we cannot call, so we do the same kind of test:
-- every building part has "BuildCollision" box(es) (the boxes the game's own placement preview uses). We ask the engine which solid components overlap
-- that box (slightly shrunk, and lifted off the floor so standing on the ground does not count). If something does, the part is NOT moved there: it stays
-- at the last free spot, so it can never be dropped inside a wall, another part, a rock or a tree.
-- Object types asked for: 1 WorldStatic, 2 WorldDynamic, 4 PhysicsBody, 5 Vehicle, 6 Destructible and 7..13 (the project's own object channels, which
-- include building parts). Only components that BLOCK the Pawn channel count (trigger volumes do not). Terrain (Landscape) never counts.
local CHECK_OBSTRUCTION = true
local OBJ_TYPES = { 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 }
local BOX_LIFT, BOX_SHRINK = 10.0, 3.0

local function unwrap(v)
  local ok, r = pcall(function() return v:get() end)
  if ok and r ~= nil then return r end
  return v
end

local function partBoxes(actor)
  local list = {}
  local arr = safe(function() return actor.BuildCollisions end)
  local n = arr and (safe(function() return #arr end) or 0) or 0
  for i = 1, n do
    local c = unwrap(arr[i])
    if c and safe(function() return c:IsValid() end) then list[#list + 1] = c end
  end
  return list
end

-- returns nil when the spot is free, otherwise a short text saying what is in the way
local function obstruction(g)
  local ksl = UEHelpers.GetKismetSystemLibrary(); local pc = UEHelpers.GetPlayerController(); local pawn = pc and pc.Pawn
  for _, box in ipairs(g.boxes) do
    local c = box:K2_GetComponentLocation(); local e = box:GetScaledBoxExtent(); local r = box:K2_GetComponentRotation()
    local yaw = math.rad(r.Yaw); local cs, sn = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
    local ex = cs * e.X + sn * e.Y - BOX_SHRINK; local ey = sn * e.X + cs * e.Y - BOX_SHRINK
    local bottom = c.Z - e.Z + BOX_LIFT; local top = c.Z + e.Z - BOX_SHRINK
    if ex > 1 and ey > 1 and top > bottom then
      local out = {}
      ksl:BoxOverlapComponents(pawn, { X = c.X, Y = c.Y, Z = (top + bottom) / 2 }, { X = ex, Y = ey, Z = (top - bottom) / 2 }, OBJ_TYPES, nil, { g.actor, pawn }, out)
      for i = 1, #out do
        local comp = unwrap(out[i])
        if comp and safe(function() return comp:IsValid() end) then
          local owner = safe(function() return comp:GetOwner() end)
          local ownerName = owner and (safe(function() return owner:GetFName():ToString() end) or "?") or "?"
          local clsName = owner and (safe(function() return owner:GetClass():GetFName():ToString() end) or "?") or "?"
          local blocks = safe(function() return comp:GetCollisionResponseToChannel(2) end)   -- 2 = Pawn channel, 2 = block
          local isTerrain = (clsName:find("Landscape") ~= nil) or (ownerName:find("Landscape") ~= nil)
          if g.diag and g.diagCount < 14 then
            g.diagCount = g.diagCount + 1
            log(("  overlap candidate: %s (%s) component %s, blocks pawn = %s, terrain = %s"):format(ownerName, clsName, tostring(safe(function() return comp:GetFName():ToString() end)), tostring(blocks), tostring(isTerrain)))
          end
          if blocks == 2 and not isTerrain and owner ~= g.actor then return ownerName .. " (" .. clsName .. ")" end
        end
      end
    end
  end
  return nil
end

local function startGrab(reason)
  if grab then log("already holding a part"); return end
  local was, hit, actor = trace(TRACE_DISTANCE, nil)
  if not was or not actor then log("start (" .. reason .. "): nothing in front of the crosshair"); return end
  local cls = nameOf(actor)
  if not isBuildPart(actor) then
    local chain, c = {}, safe(function() return actor:GetClass() end)
    for _ = 1, 6 do if not c then break end; chain[#chain + 1] = (safe(function() return c:GetFName():ToString() end) or "?"); c = safe(function() return c:GetSuperStruct() end) end
    log("start: looked at " .. cls .. " (class chain: " .. table.concat(chain, " > ") .. ") - that is not a building part"); return
  end
  local id, grid = partInfo(actor)
  id = id or cls:match("([^%.:]+)$") or "part"
  log(("start: part %s, grid type %s (%s)"):format(tostring(id), tostring(grid), cls))
  if grid ~= nil and not MOVABLE_GRID[grid] then log("refused: structural piece (grid type " .. tostring(grid) .. ")"); return end
  local loc = safe(function() return actor:K2_GetActorLocation() end)
  local rot = safe(function() return actor:K2_GetActorRotation() end)
  if not loc or not rot then log("could not read the part's position - nothing done"); return end
  grab = { age = 0, actor = actor, origLoc = { X = loc.X, Y = loc.Y, Z = loc.Z }, origRot = { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll }, yaw = rot.Yaw, id = id }
  grab.zOffset = groundOffset(actor, loc)
  grab.lastLoc = { X = loc.X, Y = loc.Y, Z = loc.Z }; grab.lastRot = { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll }; grab.lastYaw = rot.Yaw
  log(("holding %s at %.0f,%.0f,%.0f (height above floor %.0f)"):format(tostring(id), loc.X, loc.Y, loc.Z, grab.zOffset))
  grab.boxes = partBoxes(actor); grab.checkOn = CHECK_OBSTRUCTION; grab.diag = true; grab.diagCount = 0
  if grab.checkOn then
    if #grab.boxes == 0 then grab.checkOn = false; log("obstruction check OFF: this part has no BuildCollision box to test")
    else
      local okC, res = pcall(obstruction, grab)
      if not okC then grab.checkOn = false; log("obstruction check OFF: the overlap query failed (" .. tostring(res) .. ")")
      elseif res then grab.checkOn = false; log("obstruction check OFF for this part: its ORIGINAL spot is already reported as blocked by " .. res)
      else log(("obstruction check ON (%d collision box(es)); original spot is free"):format(#grab.boxes)) end
    end
  end
  grab.diag = false
end

local function dropGrab()
  if not grab then return end
  local loc = safe(function() return grab.actor:K2_GetActorLocation() end)
  if loc then log(("put %s down at %.0f,%.0f,%.0f"):format(tostring(grab.id), loc.X, loc.Y, loc.Z)) end
  grab = nil
end

local function cancelGrab()
  if not grab then return end
  setLoc(grab.actor, grab.origLoc); setRot(grab.actor, grab.origRot)
  log("cancelled: " .. tostring(grab.id) .. " is back where it was"); grab = nil
end

local function stepGrab()
  local g = grab; if not g then return end
  g.age = (g.age or 0) + 1
  if not safe(function() return g.actor:IsValid() end) then log("the held part no longer exists"); grab = nil; return end
  local was, hit, actor, s, fwd = trace(MAX_REACH, { g.actor })
  if not s then return end
  local p
  if was then p = safe(function() return { X = hit.ImpactPoint.X, Y = hit.ImpactPoint.Y, Z = hit.ImpactPoint.Z } end) end
  if not p then p = { X = s.X + fwd.X * 400.0, Y = s.Y + fwd.Y * 400.0, Z = s.Z + fwd.Z * 400.0 - g.zOffset } end
  local want = { X = p.X, Y = p.Y, Z = p.Z + g.zOffset }
  local wantRot = { Pitch = g.origRot.Pitch, Yaw = g.yaw, Roll = g.origRot.Roll }
  setLoc(g.actor, want); setRot(g.actor, wantRot)
  if g.checkOn then
    local okC, res = pcall(obstruction, g)
    if not okC then g.checkOn = false; log("obstruction check switched OFF: " .. tostring(res))
    elseif res then
      -- blocked: go back to the last free spot (and undo a blocked turn)
      setLoc(g.actor, g.lastLoc); setRot(g.actor, g.lastRot); g.yaw = g.lastYaw
      if g.blockedBy ~= res then g.blockedBy = res; log("blocked by " .. res .. " - the part stays at the last free spot") end
      return
    else
      g.lastLoc = want; g.lastRot = wantRot; g.lastYaw = g.yaw
      if g.blockedBy then g.blockedBy = nil; log("free again") end
    end
  end
end

LoopAsync(40, function()
  if grab then ExecuteInGameThread(stepGrab) end
  return false
end)

local function toggle(reason)
  ExecuteInGameThread(function()
    local ok, err = pcall(function() if grab then dropGrab() else startGrab(reason) end end)
    if not ok then log("error: " .. tostring(err)); grab = nil end
  end)
end

RegisterKeyBind(Key.F7, function() toggle("F7") end)
-- left mouse button puts the held part down (ignored for the first ~0.6 s so the click that chose "Move" in the wheel does not drop it at once)
RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, function()
  if grab and (grab.age or 0) >= 15 then ExecuteInGameThread(function() pcall(dropGrab) end) end
end)
RegisterKeyBind(Key.F6, function() ExecuteInGameThread(function() pcall(cancelGrab) end) end)
RegisterKeyBind(Key.PAGE_UP, function() if grab then grab.yaw = grab.yaw - ROTATE_STEP end end)
RegisterKeyBind(Key.PAGE_DOWN, function() if grab then grab.yaw = grab.yaw + ROTATE_STEP end end)

-- ---------------------------------------------------------------- the Q wheel
-- The wheel is UW_QuickActions_RadialMenu (a UQuickActionsWidget). Its property AvailableActions is an array of QuickActionData
-- { ActionName : Text, ActionIcon : Object (texture), ActionType : EQuickAction }. Choosing an entry calls UI_ManagerComponent:ExecuteQuickAction(ActionType).
-- EQuickAction: 0 None, 1 Construction, 2 Deconstruction, 3 Repair, 4 SummonDog, 5 SummonSled, 6 Flashlight, 7 FlashlightMode, 8 Emotes.
-- Our entry fills the wheel's empty slot, copies the Repair entry's icon and uses ActionType 1 (so the wheel treats it as available); we recognise it by its name, and when it is
-- chosen we turn the action into None before the game acts on it and start the move instead.
-- Nothing here is guaranteed to work in this game version, so every step is logged.
local wheelIndex = nil      -- 0-based slot of our entry, once added
local moveChosen = false

local function describeActions(w)
  local arr = safe(function() return w.AvailableActions end)
  if not arr then log("wheel: AvailableActions not readable"); return nil end
  local n = safe(function() return #arr end) or -1
  local parts = {}
  for i = 1, math.max(n, 0) do
    local e = arr[i]
    local nm = safe(function() return e.ActionName:ToString() end) or "?"
    local ty = safe(function() return e.ActionType end)
    parts[#parts + 1] = ("%d:%s(type %s)"):format(i - 1, nm, tostring(ty))
  end
  log(("wheel: %d entries -> %s"):format(n, table.concat(parts, ", ")))
  return arr, n
end

local function addWheelEntry(w, why)
  -- The wheel has 8 entries and one of them is an EMPTY slot (no name, type None). Seen in game on 2026-10-18:
  --   0 REPAIR, 1 CONSTRUCTION, 2 DECONSTRUCTION, 3 (empty), 4 Call dog, 5 Emotes, 6 Flashlight Mode, 7 Flashlight.
  -- We fill the empty slot IN PLACE. We never write past the end of the array: an earlier version tried to append a 9th entry and that crashed the game
  -- (access violation inside FQuickActionData::Copy).
  if not wheelEntry.enabled then return end
  local ok, err = pcall(function()
    local arr, n = describeActions(w)
    if not arr or n < 1 then return end
    local free, repairIcon = nil, nil
    for i = 1, n do
      local nm = safe(function() return arr[i].ActionName:ToString() end) or ""
      local ty = safe(function() return arr[i].ActionType end)
      if nm == wheelEntry.name then wheelIndex = i - 1; log("wheel: Move entry already there (slot " .. wheelIndex .. ")"); return end
      if ty == 3 then repairIcon = safe(function() return arr[i].ActionIcon end) end
      if free == nil and nm == "" and ty == 0 then free = i end
    end
    if not free then log("wheel: no empty slot to use - the Q wheel is left alone; use F7"); return end
    local e = arr[free]
    local r1 = pcall(function() e.ActionName = FText(wheelEntry.name) end)
    local r2 = pcall(function() e.ActionType = 1 end)
    local r3 = repairIcon and pcall(function() e.ActionIcon = repairIcon end) or false
    wheelIndex = free - 1
    log(("wheel: filled empty slot %d with '%s' (%s): name %s, type %s, icon %s"):format(wheelIndex, wheelEntry.name, why, tostring(r1), tostring(r2), tostring(r3)))
    describeActions(w)
  end)
  if not ok then log("wheel: error while adding the entry: " .. tostring(err)) end
end
-- hooks: register on the native function AND on the Blueprint class that implements it (a Blueprint override is a different function object)
local hooked = {}
local function classPathOf(obj)
  local full = safe(function() return obj:GetClass():GetFullName() end)
  return full and full:match("^%S+%s+(.+)$")
end
local function hookBoth(basePath, obj, funcName, cb)
  local paths = { basePath }
  local cp = obj and classPathOf(obj); if cp then paths[#paths + 1] = cp .. ":" .. funcName end
  for _, p in ipairs(paths) do
    if not hooked[p] then
      local ok, err = pcall(RegisterHook, p, cb); log("hook " .. p .. " -> " .. (ok and "ok" or tostring(err)))
      if ok then hooked[p] = true end
    end
  end
end

local function onAccept(self)
  local w = self:get()
  local slot = safe(function() return w.SelectedSlot end)
  local selName = safe(function() return w.SelectedAction.ActionName:ToString() end)
  local selType = safe(function() return w.SelectedAction.ActionType end)
  if selName == nil then selName = safe(function() return w.AvailableActions[(slot or -1) + 1].ActionName:ToString() end) end
  log(("wheel: choice accepted: slot %s, name %s, type %s"):format(tostring(slot), tostring(selName), tostring(selType)))
  moveChosen = (selName == wheelEntry.name) or (wheelIndex ~= nil and slot == wheelIndex and selName == nil)
end

-- Which wheel entry was clicked? ExecuteQuickAction only gets the action TYPE, and our entry shares type 1 (Construction) so the wheel treats it as
-- available. The widget remembers the highlighted slot in SelectedSlot; we read it (0-based or 1-based is decided by which reading matches the type).
local function whichEntry(a)
  local w = safe(function() return FindFirstOf("UW_QuickActions_RadialMenu_C") end)
  if not w or not safe(function() return w:IsValid() end) then return nil, "no wheel widget" end
  local slot = safe(function() return w.SelectedSlot end)
  local arr = safe(function() return w.AvailableActions end)
  if slot == nil or not arr then return nil, "SelectedSlot/AvailableActions unreadable" end
  local function entry(i) return safe(function() return arr[i].ActionName:ToString() end), safe(function() return arr[i].ActionType end) end
  local n0, t0 = entry(slot + 1); local n1, t1 = entry(slot)
  local ok0, ok1 = (t0 == a), (t1 == a)
  local name = (ok0 and n0) or (ok1 and n1) or nil
  return name, ("SelectedSlot %s -> 0-based reading '%s'(type %s), 1-based reading '%s'(type %s)"):format(tostring(slot), tostring(n0), tostring(t0), tostring(n1), tostring(t1))
end

local function onExecute(self, action)
  local a = safe(function() return action:get() end)
  local name, why = whichEntry(a)
  log(("wheel: ExecuteQuickAction(%s): %s => entry '%s'"):format(tostring(a), tostring(why), tostring(name)))
  if name == wheelEntry.name then
    moveChosen = false
    safe(function() action:set(0) end)      -- None: the game does nothing
    log("wheel: Move chosen - starting the move")
    ExecuteWithDelay(250, function() toggle("wheel") end)
  end
end

-- The wheel builds its icon and label widgets when it is created, so changing the array afterwards does not change what is drawn.
-- This finds the widgets of the empty slot (its icon is the padlock texture, its label is empty) and puts our icon / name on them. Everything is logged.
local function fixVisuals(why)
  local w = safe(function() return FindFirstOf("UW_QuickActions_RadialMenu_C") end)
  if not w or not safe(function() return w:IsValid() end) then return end
  local arr = safe(function() return w.AvailableActions end)
  local tex = (wheelIndex ~= nil and arr) and safe(function() return arr[wheelIndex + 1].ActionIcon end) or nil
  local icons = safe(function() return FindAllOf("UW_QuickAction_Icon_C") end) or {}
  local fixedI, fixedT = 0, 0
  local seenRes = {}
  for _, ic in ipairs(icons) do
    local res = safe(function() return ic.Image_Icon.Brush.ResourceObject:GetFullName() end)
    seenRes[#seenRes + 1] = tostring(res and res:match("([^%.]+)$") or res)
    if res and res:lower():find("lock") and tex then
      local okB = pcall(function() ic.Image_Icon:SetBrushFromTexture(tex, false) end)
      log(("wheel: icon widget with the padlock found (%s) -> brush replaced: %s"):format(res, tostring(okB)))
      if okB then fixedI = fixedI + 1 end
    end
  end
  log("wheel: icon textures seen: " .. table.concat(seenRes, ", "))
  local texts = safe(function() return FindAllOf("UW_QuickAction_Text_C") end) or {}
  for _, tx in ipairs(texts) do
    local nm = safe(function() return tx.ActionName:ToString() end)
    if nm == "" then
      local ok1 = pcall(function() tx:SetText(FText(wheelEntry.name)) end)
      local ok2 = pcall(function() tx.ActionName = FText(wheelEntry.name) end)
      log(("wheel: empty label widget found -> SetText %s, ActionName %s"):format(tostring(ok1), tostring(ok2)))
      if ok1 or ok2 then fixedT = fixedT + 1 end
    end
  end
  log(("wheel: visuals (%s): %d icon widgets, %d label widgets seen; fixed icons %d, labels %d"):format(why, #icons, #texts, fixedI, fixedT))
end

pcall(function()
  NotifyOnNewObject("/Game/Permafrost/UI/RadialMenu/UW_QuickActions_RadialMenu.UW_QuickActions_RadialMenu_C", function(w)
    log("wheel: widget created")
    ExecuteInGameThread(function()
      addWheelEntry(w, "new widget")
      hookBoth("/Script/Permafrost.QuickActionsWidget:OnRadialAccept", w, "OnRadialAccept", onAccept)
      hookBoth("/Script/Permafrost.QuickActionsWidget:ToggleMenu", w, "ToggleMenu", function() ExecuteWithDelay(300, function() ExecuteInGameThread(function() fixVisuals("menu toggled") end) end) end)
      ExecuteWithDelay(2000, function() ExecuteInGameThread(function() fixVisuals("2 s after creation") end) end)
    end)
  end)
end)

-- ExecuteQuickAction lives on the UI manager component, which exists once a world is loaded
LoopAsync(5000, function()
  ExecuteInGameThread(function()
    if hooked["__exec"] then return end
    local c = safe(function() return FindFirstOf("UI_ManagerComponent") end)
    if c and safe(function() return c:IsValid() end) then
      hookBoth("/Script/Permafrost.UI_ManagerComponent:ExecuteQuickAction", c, "ExecuteQuickAction", onExecute)
      hooked["__exec"] = true
    end
  end)
  return hooked["__exec"] == true
end)

-- the wheel may already exist when this mod loads: add the entry and rebuild its icons
ExecuteWithDelay(9000, function()
  ExecuteInGameThread(function()
    local w = safe(function() return FindFirstOf("UW_QuickActions_RadialMenu_C") end)
    if w and safe(function() return w:IsValid() end) then
      log("wheel: widget already existed at start-up")
      addWheelEntry(w, "existing widget")
      hookBoth("/Script/Permafrost.QuickActionsWidget:OnRadialAccept", w, "OnRadialAccept", onAccept)
      fixVisuals("existing widget")
    else
      log("wheel: no widget yet (it will be extended when it is created)")
    end
  end)
end)

log("loaded. F7 = pick up / put down the building part you look at, Page Up/Down = turn it, F6 = cancel.")
