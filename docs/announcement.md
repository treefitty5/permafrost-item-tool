# Permafrost Item Tool: announcement and quick guide

I'm loving Permafrost, and I wanted a deeper look at what's actually going on under the hood: what every item does, where it can be found, how recipes, loot and quests are put together. So I built a tool, and it's free and open source.

**Permafrost Item Tool** (single-player only). **Download the ZIP, double-click one file, done:** no exporting, no mappings, no setup. It finds your saves by itself.

![Overview window](screenshot-overview.png)

* **Overview:** a read-only report of your save: play time, vitals, skills, inventory, recipes known, quests, buildings, explored area, companion, backups. Nothing in it changes the save.
* **Item catalog:** every item with its in-game name, description, stack size, condition, damage, frost protection, value, ammo and where to find it, with drop chances.
* **Add items** to your save (backpack or hotbar) with stack and backpack-space checks. A backup is made before every change, and one click restores it.
* **Player tools:** vitals, skills and skill points, known recipes, teleport (places or exact coordinates), read-only quest view.
* **Game data browser:** reward pools, quests (with a spoiler guard, on by default), recipes, loot tables, building parts, effects, difficulty, animals, NPCs and more.
* **Recipe tweaks:** change ingredient amounts, how many you craft and crafting time, live in game through a small UE4SS mod. Your save is never touched.
* **World reset:** put chopped trees, mined boulders and ores, picked-up items, harvested bushes and looted containers back (the game never respawns them), per world, with a backup first.
* **Build move:** pick up a placed building from the Q wheel and put it down elsewhere, live in game. Storage can be stacked and put on walls.

**Pictures:** the item and recipe pictures are the game's artwork, so they are not in the download. One button (**Pictures...**) builds them from your own installed game in about 20 seconds; it needs a small free decompression library once and asks before downloading it.

**Needs:** Windows and PowerShell 7 (the launcher offers to install it). UE4SS is only needed for the two in-game mods (Recipe tweaks, Build move).

**How it was made:** I built this together with Claude, Anthropic's AI assistant. I set the goals and tested everything in game on my own save; the AI wrote the code and decoded the data. The source is fully open here, so you can read what it does before running it.

**Please read:** unofficial fan tool, not affiliated with the developers or publisher. Modding isn't officially supported, so use it at your own risk and please don't report problems to the developers: open an issue in this repository instead. Single-player only. Close the game before applying changes and back up your saves.

## Quick start

1. Download the latest ZIP from the [Releases page](https://github.com/treefitty5/permafrost-item-tool/releases/latest) and unzip it somewhere you own (not in the game folder).
2. **Close the game**, then double-click `Run Permafrost Item Tool.cmd`. If PowerShell 7 is missing, say **Y** when the launcher offers to install it.
3. It opens your most recent world. **Browse...** lists all your worlds; **Overview...** shows everything it can read from the save.

If Windows says "protected your PC", click **More info → Run anyway**: it's plain scripts you can read in Notepad. No installer, no .exe. The [README](../README.md) has every detail.

## Recipe tweaks (in game)

Needs UE4SS (README section 4). In the tool: **Recipe tweaks... → Install / update mod** (once, then restart the game). Edit ingredient amounts, amount crafted or time, and press **Save to game**. Changes apply by themselves within a few seconds while you play: close and reopen the bench to see them. **Reset ALL recipes** and Save puts everything back. Your save file is never changed, so this works with the game running.

## World reset

In the tool: **World reset...** (game closed). Pick the world, tick what to put back (trees, boulders and ores, items, container loot, bushes, optionally other breakables), optionally limit it to N metres around you (try 150 first), then **Reset the world now...**. It previews, asks you to confirm, backs up your save and verifies the result. Destroyed ores and picked-up items are restored from your earlier backups and from your other worlds on the same map, so keep the `Backups` folder.

## Build move (in game)

Needs UE4SS. In the tool: **Build move... → Install** (once, then restart the game). In the game look at a placed part, press **Q** and choose **Move**; it follows your crosshair and a **left click** puts it down. The same object is moved (health and contents stay, no materials used). There is no collision check on purpose: you can stack chests and barrels and put storage on walls.

## After a game update

The tool ships data for one game version (the Overview warns when the installed build differs). After a patch, check for a new release; if there is none yet you can rebuild the data from your own game files (README section 9, about 30 minutes the first time).

## Safety

* Single-player saves only.
* Close the game before using "Apply to save"; keep Steam Cloud off for Permafrost while experimenting.
* Every change is backed up automatically (the `Backups` folder), and Restore is one click.
* The tool refuses to write if its own checks fail, rather than guessing.

Feedback, bug reports and ideas are very welcome: open an issue. Stay frosty!