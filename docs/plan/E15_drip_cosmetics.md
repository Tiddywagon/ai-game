# E15: Drip economy, the cosmetic slot machine and skins (after E14)

Request: "Add a cosmetic currency called Drip and a slot machine in the hideout. Earn Drip from extracting (more
for bigger loot value), kills, completing quests and daily tasks, and leveling up. One spin costs Drip (e.g. 100
per spin, discount for a 10-spin). The slot machine has 3 animated reels with sound, lights and a near-miss
tease; the result rolls a cosmetic skin using the odds in the table above, with a pity counter that guarantees
at least an Epic every 80 spins without one. Cosmetics are purely visual, never stat changes: weapon skins (per
weapon or universal), armor and helmet skins, backpack and rig skins, character outfits per faction (BEAR and
USEC), knife skins, and stickers/charms. Each skin has a wear value (Factory New to Battle-Scarred) that changes
how it looks, rolled on the drop. Duplicates convert into Drip. Add a Cosmetics tab to the loadout screen where
I preview and apply skins to my gear and weapons on a rotating 3D model; skins stay on the item and are lost if
I lose the item in raid, except for 'bound' skins that I can reapply from my collection. Add a collection
screen showing all skins, owned/missing, and rarity. Add seasonal skin collections that rotate in the slot
machine. Put all odds, prices and rewards in config files."

The odds table did not come through: the odds are designed here (DESIGN.md must say so). Drip already exists
(earned from trick shots and some quests; `GameState.drip`); this step makes it a full currency. The Oddities
figure set (E10) gives one free spin per day on this machine.

## Part a: data and logic

- **Earning Drip** (`data/config/drip.json`): per extract (a base plus brackets by the loot value brought out),
  per kill (Scav, PMC, boss), per quest completed, per daily and weekly task, per level gained; trick shots as
  now. PMC raids and Scav runs both pay for extracts; practice pays nothing. The raid summary shows Drip earned.
- **Skins** in `data/cosmetics/*.json` (loader with `problems()`): id, name, rarity, kind (weapon, armor, helmet,
  backpack, rig, outfit, knife, sticker, charm), what it fits (one weapon id, a weapon class, or universal; armor
  / helmet / rig / backpack by item or universal; outfits by faction), its collection, whether it is bound, and
  its look as parameters (base and accent colours, a pattern: solid, camo, stripes, hex, splatter, gradient,
  glow) drawn by one material/shader with a wear parameter. Enough for a real pool: about 90 skins in a core
  collection and three seasonal collections of about 12 each, across every kind, Legendary ones rare.
- **Wear**: a float rolled on the drop, named in five bands (Factory New, Minimal Wear, Field-Tested, Well-Worn,
  Battle-Scarred); the bands and their odds in the config; wear scratches and dulls the look, nothing else.
- **Never stats**: a skin changes no number anywhere (a test compares every stat of skinned and plain items).
- **The roll** (`data/config/slots.json`): rarity odds (designed here: Common 52%, Uncommon 27%, Rare 13%, Ultra
  Rare 5%, Epic 2.4%, Legendary 0.6%), then a skin of that rarity from the core collection and the season in
  rotation; a pity counter gives at least an Epic on the 80th spin without one (saved, reset by any Epic or
  Legendary); spin price 100 Drip, ten for 900; the result is decided and saved before the reels move, so a
  reload can't re-roll.
- **Owning and duplicates**: the collection holds one of each skin. Rolling one you hold (in the collection or on
  an item you own) converts to Drip by rarity (config); if its wear is better than yours, yours takes the better
  wear first.
- **Applying**: a skin goes from the collection onto one item that it fits and stays on it (saved in the item,
  shown on its icon, in the stash, on the character and in raids). Taking it off returns it to the collection.
  Losing the item in a raid loses the skin, except bound skins (outfits, and whatever the config marks: Epic and
  Legendary by default), which go back to the collection. Selling, bartering, handing in or listing a skinned
  item returns the skin first. Outfits apply to the character per faction and are never lost.
- **Seasons**: collections with a rotation in the config (one season at a time in the machine, changing every
  few weeks of real time on a fixed calendar, coming round again later); the machine shows the season and the
  time left.
- Save version bump (collection, wear, pity, spins, free-spin day, skins on items); old saves start empty and
  keep their Drip.

## Part b: screens and visuals

- **Slot machine in the hideout**: a machine on the hideout plan, available from the start; its screen has three
  reels that spin and stop one after another with sounds (spin, stop, win stings by rarity: generated
  placeholder audio), a ring of lights that chase and flash by rarity, and a near-miss tease (two high symbols
  land and the third slides just past) on some lower results, never changing the result. SPIN, SPIN ×10 (results
  shown as a row, skippable), FREE SPIN when the Oddities bonus has one, the pity counter ("Epic or better
  within 23 spins"), the odds on a button, the result card with the skin on a rotating model, its wear and
  whether it was a duplicate (and the Drip paid back).
- **COSMETICS tab** on LOADOUT (LOADOUT | QUICK BUY | COSMETICS): pick a worn or stashed item or the character,
  see it on a rotating 3D model (drag to turn, zoom), the skins that fit it with rarity and wear, PREVIEW, APPLY,
  REMOVE; stickers and charms on their own slots where the item has them.
- **Skins collection screen**: every skin by collection and kind, owned in colour with wear, missing as
  silhouettes, rarity, bound mark, where it's applied, season availability, progress per collection.
- **In the world**: skinned guns, armor, helmets, rigs, backpacks, knives and outfits show their colours and
  pattern on the placeholder models (player and bodies), and on item icons.
- DESIGN (a new Cosmetics and Drip section with the odds, prices, bands, earn rates and a skin table generated
  from the data, the missing-table note), §9, §14, §15, §16, §18; README. Suite `tests/cosmetics_test.gd`: loader
  problems, earn rates through real events, odds over many seeded spins, pity at 80, the ten-spin price, no
  re-roll on reload, duplicates and better wear, apply / remove / fits, lost with the item unless bound, returned
  before a sale, no stat ever changes, seasons by date, the free daily spin, save round trip; the three screens
  through their controls with screenshots looked at.
