AtlasDumpMod - how catalog\pristine-world.bin was made (developer notes; players do not need this)
==========================================================================================

What it is
  A UE4SS Lua mod that flies the player along a route of stops in a THROWAWAY world, waits for the area to stream in, and writes the
  class, full name, position and save id (GetActorGuidForSaveAndLoad) of every actor that has one to AtlasDump.log. Build-Pristine.ps1
  then takes the world save that this flight produced (every visited cell has a record for every object) and writes
  catalog\pristine-world.bin: the untouched ore / breakable / world-item records the World reset uses when a world has no backup.

Use (experimental UE4SS build 3.0.1 needed, see README section 16)
  1. Copy main.lua to  <game>\Permafrost\Binaries\Win64\ue4ss\Mods\AtlasDump\Scripts\main.lua  and add  AtlasDump : 1  to mods.txt.
  2. Put a route.lua next to the Scripts folder:  return { { name = "S1", x = -61288, y = -92643, z = 5057, wait = 18000 }, ... }
     x / y = where to hover (cm), z = highest known object there (the mod hovers 25 m above it), wait = ms to wait at the stop.
     Stops every 100 m cover a cell fully (the game only streams about 80-100 m around you, even from low).
  3. Start a NEW world (never a world you care about: moving the player loads areas and the game saves them), load it, press Ctrl+F2.
     Ctrl+F3 aborts, Ctrl+F4 forgets the progress. Progress is saved after every stop.
  4. Close the game, put the player back on the ground in the save (Set-Teleport in PlayerCore.ps1): the game AUTOSAVES mid-flight,
     so the save otherwise keeps the position of the last stop (e.g. 400 m up) and the character dies on load.
  5. pwsh -Command "& .\Build-Pristine.ps1 -Base <flown save.pfs> -Extra <other saves of the same map> -ExtraDir <Backups folder>"

Lessons (each one cost a crash or a bad run)
  * UE4SS's Lua registry is not thread-safe: never call ExecuteWithDelay from a delayed callback while other timers run. The mod uses ONE
    one-second timer chain that hops to the game thread.
  * Only write to the player's own AttributeSets (health, stamina, energy, hunger, body warmth). Other creatures' sets are freed as you fly on.
  * Free the ~5000 actor wrappers of every scan at once (collectgarbage) while the actors are still alive.
  * A line trace "to the ground" from high up hit a flat plane at z 24387 everywhere: take the ground height from known object positions.
  * Some objects (cars, trash cans, loose items, trees) only exist in some worlds (random per world) and are not in the flight: the shipped map
    fills the gaps with records from older saves of other worlds (only where no object of that class already stands within 3 m).
Second flight (2026-10-24): route-v8-75m.lua
  297 stops, 75 m apart, over the revealed map of a played world (its FogOfWarRevealer_Voxels = 50 m squares, plus a one-square border) and a few extra stops
  for known objects farther out. Made by Build-Route-v8.ps1 (needs a played world's save and the first flight's log for ground heights; heights from the
  player's own clothing attachments and other flight artefacts are filtered out). Flown in a NEW throwaway world; the game gave that world the slot name of
  an existing world and overwrote it, so BACK UP the played world's save and its DifficultySettings\<world>.diff before creating a new world.
  The vitals keeper now refills every second. Result: pristine-world.bin 2675 -> 2761 records (487 -> 491 cells), loot-pool.json 1148 -> 1568 rolls.
