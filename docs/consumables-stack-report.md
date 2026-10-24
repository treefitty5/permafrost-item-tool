# Consumables: how they stack (from the game data)

Made by Build-StackReport.ps1 from the game's own data files (86 consumable assets). Re-run it after a game update.

## How to read this

- **Game stack** is the limit in the item data. **Stackable flag**: the game only stacks an item when its data says so; where the flag is *missing* the item takes one slot per piece although a limit is listed (Panacea and both splints).
- **Uses durability**: the item carries a condition. A stack shares ONE condition, so the first aid kits only stack with the mod's "single use" setting.
- The condition shown in the item list for foods (10) is the item's own condition field, not a durability; the game already stacks those to 20.
- **Safety rule (tested with kits):** the stack limit belongs to the item data. With the StackSizes mod off, the game trims every stack above its own limit down on the next save and the extra items are gone. Anything raised with the mod needs the same DANGER warning and backup as the kits.
- Sizes above 20 were never tried in the game (stacks of 5, 10 and the game's own 20 were).

**Summary:** 4 durability, 16 flag missing, 66 stackable.

## Not stackable today (stack limit listed, flag missing) (16)

| Item | Save id | Game stack | Folder |
|---|---|---|---|
| Makeshift Splint | MakeshiftSplint | 5 | Medication |
| Medical Splint | MedicalSplint | 5 | Medication |
| Panacea | Panacea | 5 | Medication |
| Energy & Warming Dish | DishE2W1 | 20 | PredefinedRecipeOutput |
| Energy & Warming Dish | DishE1W2 | 20 | PredefinedRecipeOutput |
| Energy & Warming Dish | DishD1E1W1 | 20 | PredefinedRecipeOutput |
| Energy Dish | DishE2 | 20 | PredefinedRecipeOutput |
| Energy Dish | DishD2E1 | 20 | PredefinedRecipeOutput |
| Energy Dish | DishE3 | 20 | PredefinedRecipeOutput |
| Energy Dish | DishD1E2 | 20 | PredefinedRecipeOutput |
| Health & Energy Dish | DishE2H1 | 20 | PredefinedRecipeOutput |
| Health & Energy Dish | DishD1E1H1 | 20 | PredefinedRecipeOutput |
| Health & Energy Dish | DishE1H2 | 20 | PredefinedRecipeOutput |
| Healthy Dish | DishD1H2 | 20 | PredefinedRecipeOutput |
| Ultra Dish (H/W/E) | DishHWEx2 | 20 | PredefinedRecipeOutput |
| Warming Dish | DishD1W2 | 20 | PredefinedRecipeOutput |

- Not stackable in the game (the data has a stack limit of 5 but no stackable flag, so every piece takes its own slot). The mod can mark it stackable. No durability.
- Dish variants (loot and recipe outputs): same missing flag, limit 20. Not checked in the game whether they stack; the mod could mark them stackable.

## Items with a durability (4)

| Item | Save id | Game stack | Folder |
|---|---|---|---|
| Car Medkit | CarMedkit | 1 | Medication |
| Medkit AFAK | MedkitAFAK | 1 | Medication |
| Medkit IFAK | MedkitIFAK | 1 | Medication |
| Medkit MFAK | MedkitMFAK | 1 | Medication |

- Has a durability (condition): a stack would share one condition. Needs the mod's 'single use' to stack without wasting items (that is how the first aid kits work).

## Already stackable (66)

| Item | Save id | Game stack | Folder |
|---|---|---|---|
| Alcohol | Alcohol | 20 | Consumables |
| Bag of Chips | BagOfChips | 20 | Consumables |
| Bag of MRE | BagOfMre | 20 | Consumables |
| Beef Jerky | BeefJerky | 20 | Consumables |
| Beer | Beer | 20 | Consumables |
| Can of Ham | CanOfHam | 20 | Consumables |
| Can of Pasta | CanOfPasta | 20 | Consumables |
| Can of Soda | CanOfSoda | 20 | Consumables |
| Can of Soup | CanOfSoup | 20 | Consumables |
| Can of Tomatoes | CanOfTomatoes | 20 | Consumables |
| Can of Tuna | CanOfTuna | 20 | Consumables |
| Canned Beans | CanOfBeans | 20 | Consumables |
| Canned Dog Food | CannedDogFood | 20 | Consumables |
| Cheesecake | Cheesecake | 20 | Consumables |
| Chocolate Bar | ChocolateBar | 20 | Consumables |
| Coffee Beans | CoffeeBeans | 20 | Consumables |
| Dried Fish | DriedFish | 20 | Consumables |
| Dried Fruit | DriedFruits | 20 | Consumables |
| Dried Mushrooms | DriedMushrooms | 20 | Consumables |
| Edible Root | EdibleRoot | 20 | Consumables |
| Energy Drink | EnergyDrink | 20 | Consumables |
| Frozen Fruit | FrozenFruits | 20 | Consumables |
| Frozen Pizza | FrozenPizza | 20 | Consumables |
| Frozen Veggies | FrozenVeggies | 20 | Consumables |
| Granola Bar | GranolaBar | 20 | Consumables |
| Honey | Honey | 20 | Consumables |
| Ice Cream | IceCreamBar | 20 | Consumables |
| Ice Cream Box | IceCreamBox | 20 | Consumables |
| Instant Oatmeal | InstantOatmeal | 20 | Consumables |
| Juice | Juice | 20 | Consumables |
| Meat | RawMeat | 20 | Consumables |
| Methyl Alcohol | MethylAlcohol | 20 | Consumables |
| Moonshine | Moonshine | 20 | Consumables |
| Mushrooms | Mushrooms | 20 | Consumables |
| Nut Mix | NutMix | 20 | Consumables |
| Pepper | Pepper | 20 | Consumables |
| Small Bottle of Vodka | VodkaSmall | 20 | Consumables |
| Sugar | Sugar | 20 | Consumables |
| Vodka | Vodka | 20 | Consumables |
| Whiskey | Whiskey | 20 | Consumables |
| Wine | Wine | 20 | Consumables |
| Dish | Dish | 20 | Dish |
| Energy & Warming Dish | DishEW | 20 | Dish |
| Energy Dish | DishE | 20 | Dish |
| Health & Energy Dish | DishHE | 20 | Dish |
| Health & Warming Dish | DishHW | 20 | Dish |
| Healthy Dish | DishH | 20 | Dish |
| Ultra Dish (H/W/E) | DishHWE | 20 | Dish |
| Warming Dish | DishW | 20 | Dish |
| Cooked Beans | CookedCanOfBeans | 20 | HeatedCannedFood |
| Cooked Dog Food | CookedCanOfDogFood | 20 | HeatedCannedFood |
| Cooked Fruits | CookedFruits | 20 | HeatedCannedFood |
| Cooked Oatmeal | CookedOatmeal | 20 | HeatedCannedFood |
| Cooked Pasta | CookedCanOfPasta | 20 | HeatedCannedFood |
| Cooked Pizza | CookedPizza | 20 | HeatedCannedFood |
| Cooked Soup | CookedCanOfSoup | 20 | HeatedCannedFood |
| Cooked Tomatoes | CookedCanOfTomatoes | 20 | HeatedCannedFood |
| Cooked Veggies | CookedVeggies | 20 | HeatedCannedFood |
| Bandage | Bandage | 5 | Medication |
| Herbs | Herbs | 30 | Medication |
| Makeshift Bandage | MakeshiftBandage | 5 | Medication |
| Military Bandage | MilitaryBandage | 5 | Medication |
| Painkillers | Painkillers | 5 | Medication |
| Surgical Spirit | SurgicalSpirit | 10 | Medication |
| Improvised Coffee | Coffee | 20 | PredefinedRecipeOutput |
| Improvised Tea | Tea | 20 | PredefinedRecipeOutput |

- Stacks to 20 in the game. The limit can be raised with the StackSizes mod; no durability, so a stack wastes nothing.
- Stacks to 5 in the game. The limit can be raised with the StackSizes mod; no durability, so a stack wastes nothing.
- Stacks to 30 in the game. The limit can be raised with the StackSizes mod; no durability, so a stack wastes nothing.
- Stacks to 10 in the game. The limit can be raised with the StackSizes mod; no durability, so a stack wastes nothing.

## Stackable items with a limit below 20 (the most useful to raise)

- Bandage (Bandage): 5
- Makeshift Bandage (MakeshiftBandage): 5
- Military Bandage (MilitaryBandage): 5
- Painkillers (Painkillers): 5
- Surgical Spirit (SurgicalSpirit): 10

