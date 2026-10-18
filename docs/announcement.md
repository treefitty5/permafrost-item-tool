# Permafrost Item Tool: announcement and quick guide

I'm loving Permafrost, and I wanted a deeper look at what's actually going on under the hood: what every item does, where it can be found, how recipes, loot and quests are put together. So I built a tool, and it's free and open source.

**Permafrost Item Tool** (single-player only)

* **Item catalog:** every item with its in-game name, description, stack size, condition, damage, frost protection, value, ammo and where to find it, with drop chances.
* **Add items** to your save (backpack or hotbar) with stack and backpack-space checks. A backup is made before every change, and one click restores it.
* **Player tools:** vitals, skills and skill points, known recipes, teleport, read-only quest view.
* **Game data browser:** reward pools, quests (with a spoiler guard, on by default), recipes, loot tables, building parts, recordings, effects, difficulty, animals, NPCs and more.
* **Recipe tweaks:** change ingredient amounts, how many you craft and crafting time, live in game through a small UE4SS mod. Your save is never touched.
* **World reset:** put chopped trees, mined boulders and ores, picked-up items and looted containers back (the game never respawns them), per world, with a backup first.
* **Build move:** pick up a placed building from the Q wheel and put it down elsewhere, live in game. Storage can be stacked and put on walls.

Everything it shows is read from the game's own files on your PC. The repository contains no game files, art or data: you build it from your own copy (steps below).

**Needs:** Windows, PowerShell 7, FModel, UE4SS (experimental build).

**How it was made:** I built this together with Claude, Anthropic's AI assistant. I set the goals and tested everything in game on my own save; the AI wrote the code and decoded the data. The source is fully open here, so you can read what it does before running it.

**Please read:** unofficial fan tool, not affiliated with the developers or publisher. Modding isn't officially supported, so use it at your own risk and please don't report problems to the developers: open an issue in this repository instead. Single-player only. Close the game before applying changes and back up your saves.

## Setup, step by step

One-time; the [README](../README.md) has every detail.

1. **Install PowerShell 7** (free): in a terminal run `winget install Microsoft.PowerShell`.
2. **Get the tool:** **Code → Download ZIP** on the repository page, unzip somewhere you own (not in the game folder).
3. **Make a mappings file (one time):**
   * Install UE4SS, **experimental build** (older ones don't work with Permafrost).
   * Copy the folder `UE4SSMods\DumpUsmapNative` from the tool into `...\Binaries\Win64\ue4ss\Mods\`.
   * Add `DumpUsmapNative : 1` to `Mods\mods.txt` (above the "Built-in keybinds" line).
   * Start the game and press **F9** once. A `.usmap` file appears in the `ue4ss` folder.
4. **Export the game files with FModel:**
   * Add the game (`...\Permafrost\Content\Paks`, UE 5.4) and load your `.usmap` as the local mapping.
   * Right-click `Permafrost\Content\Permafrost\Blueprints` and export it twice: raw (.uasset) and JSON. Export `Assets\Items` raw too (item pictures only, optional).
5. **Build the data:** in the tool folder run `pwsh -NoProfile -File .\Build-Everything.ps1` (about a minute).
6. **Close the game**, then double-click `Run Permafrost Item Tool.cmd`.

If Windows says "protected your PC", click **More info → Run anyway**: it's plain scripts you can read in Notepad. No installer, no .exe.

## Recipe tweaks (in game)

In the tool: **Recipe tweaks... → Install / update mod** (once, then restart the game). Edit ingredient amounts, amount crafted or time, and press **Save to game**. Changes apply by themselves within a few seconds while you play: close and reopen the bench to see them. **Reset ALL recipes** and Save puts everything back. Your save file is never changed, so this works with the game running.

## World reset

In the tool: **World reset...** (game closed). Pick the world, tick what to put back (trees, boulders and ores, items, container loot, optionally other breakables), optionally limit it to N metres around you (try 150 first), then **Reset the world now...**. It previews, asks you to confirm, backs up your save and verifies the result. Destroyed ores and picked-up items are restored from your earlier backups, so keep the `Backups` folder. Bushes are not covered.

## Build move (in game)

In the tool: **Build move... -> Install** (once, then restart the game). In the game look at a placed part, press **Q** and choose **Move**; it follows your crosshair and a **left click** puts it down. The same object is moved (health and contents stay, no materials used). There is no collision check on purpose: you can stack chests and barrels and put storage on walls.

## After a game update

The tool's data comes from the game files, so after a patch: update the game, re-export `Blueprints` in FModel, and re-run `Build-Everything.ps1`. The README has the full checklist, including what to do if UE4SS or the mappings need refreshing.

## Safety

* Single-player saves only.
* Close the game before using "Apply to save"; keep Steam Cloud off for Permafrost while experimenting.
* Every change is backed up automatically (the `Backups` folder), and Restore is one click.
* The tool refuses to write if its own checks fail, rather than guessing.

Feedback, bug reports and ideas are very welcome: open an issue. Stay frosty!
