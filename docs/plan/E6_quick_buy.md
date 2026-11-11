# E6: Quick Buy tab on the LOADOUT screen, and loyalty prices

Request: "Add a Quick Buy tab to the loadout screen showing loadout cards with a name, price, item preview,
total stat summary, and a lock icon with the unlock requirement if I don't qualify. Loadouts are data files
listing items, attachments, ammo and meds, each sourced from a specific trader. Unlock rules combine trader
loyalty levels and number of completed tasks (and optional specific quests). Final price = sum of the items at my
current trader prices, minus a 10% bundle discount, so it gets cheaper as loyalty rises. Buying equips everything
straight onto my character, packs mags with the included ammo, and moves anything I was wearing into my stash
(warn me if it doesn't fit). If a trader is out of stock on an item, swap in the closest available alternative
and show what changed before I confirm. Add a 'Save current gear as quick-buy' option that turns my loadout into
a custom card priced from trader stock. Include the 6 loadouts from the table and 4 more, including one
faction-specific option each for BEAR and USEC." The table never arrived: all ten cards are designed here, and
DESIGN.md must say so.

This was built and reviewed once and lost before it was committed. Everything the reviews found is folded in
below as a requirement.

## 1. Loyalty prices

- Each trader in `data/traders/traders.json` gets `"buy_discount": [0, 0.03, 0.06, 0.09]` (LL1-4), checked by
  `TraderTable.problems()`. Mole has none (his worn gear is already priced by his level and karma).
- One `Trading.price(trader, offer)` is used by everything that shows or charges a trader price: the BUY tab,
  `buy()`, `buy_block_reason()`, quick buy, the trader panel. Barters are unaffected.
- No resale profit, ever: `Trading.resale_floor(item)` = what the best-paying trader pays for the item at their
  top loyalty (dollars at the exchange's sell rate) plus a margin (`"resale_floor": 0.03` in
  `data/config/trading.json`); every discounted price (loyalty and the quick-buy bundle) is held at or above it,
  per line. The no-resale test checks the least any offer can ever cost (top loyalty and the bundle price)
  against every trader's buy price, whole and stripped into parts.
- BUY rows show the discount ("39,770 ₽ · −3% at your loyalty (was 41,000 ₽)"); each trader's panel says "Buy
  prices: 3% off at your LL2 (6% at LL3, 9% at LL4)"; the loyalty table in DESIGN §10 lists the shares.

## 2. Card data

- One card per file in `data/quick_buy/<id>.json`, rules in `data/config/quick_buy.json`, loader
  `QuickBuyTable` (`scripts/data/`) with `problems()` run when the items load. A card: id, name, description,
  optional `faction` ("bear"/"usec": only that faction sees it), `unlock` {"loyalty": {trader: level}, "tasks": n
  completed quests, "quests": [ids]}, and the kit: per slot the item and its source trader, gun parts by slot
  path (each with its trader), rounds (item, trader, count: at least two magazines' worth per gun), meds and
  other carried items (item, trader, count).
- `problems()` checks: items exist and fit their slot; parts fit, in order; each item is sold by its named
  trader at a level the card's unlock reaches (a card using The Broker lists his unlock quest); task counts are
  reachable with the quests that exist; rounds match a gun on the card; gear and part entries have count 1; the
  packs a card needs fit within a limited offer's stock per restock; the whole kit fits on an empty character.
- Ten cards with original names and coherent kits, cheap ones cheap, unlocks from nothing to LL4 plus many
  tasks: a pistol-and-bandages run, a shotgun brawler, an SMG room clearer, an AK all-rounder, a marksman
  (SVD or Mosin), a class 5 heavy assault kit, a medic/support kit, a suppressed stealth kit (add a money offer
  for a suppressor if none exists), a BEAR-only kit (Eastern gun, armor, rig and backpack) and a USEC-only kit
  (Western gear, dollars where the item is The Broker's). DESIGN gets a table of the ten: kit, unlock, price at
  unlock and at LL4, kept in step with the data by a test.

## 3. QUICK BUY tab

- LOADOUT becomes tabbed: LOADOUT | QUICK BUY (Q/E, LB/RB). The tab keys go through `_unhandled_input` and do
  nothing while a text box is being typed in, the filter bar has focus, an item is being dragged, or the examine
  panel, the modding screen, a container window or any dialog is open.
- A grid of cards: name, faction or CUSTOM tag, description, icons of the main pieces, the stats of the would-be
  loadout from `LoadoutStats` (armor class per zone, weight, the gun's ergonomics and recoil, capacity), the
  price after loyalty prices and the bundle discount with the full price struck through and "−10%" ("+ $n" when
  dollars are involved, and their rouble cost), "n substitutions · n left out" when it needs any. A locked card
  shows a padlock and what is still missing with progress ("Bulat LL3 · 12 tasks completed (6 so far) · Quest:
  …"), BUY disabled. Cards and the money line refresh when stock changes or a trader restocks.
- BUY opens a confirm dialog (modal: focus stays inside, container windows stay beneath its shade) listing every
  line with its trader and price, swaps and left-outs in amber, where rounds and meds go, what goes to the stash,
  and every reason it can't be bought (not just the first). CONFIRM: pays roubles and dollars, takes stock once
  per offer across the card's lines, counts each line toward its trader's money spent (dollars at the exchange
  rate), puts what is worn and carried into the stash with its contents (the secure container stays on,
  untouched), equips the kit, fits parts at their slot paths (displaced default parts to the stash), loads each
  magazine to capacity and puts spare rounds in rig, pockets, then backpack in full stacks, meds in pockets then
  rig. Nothing bought is found in raid (`FoundInRaid.Source.QUICK_BUY`). It is tried on copies first: if what is
  worn or a displaced part has no room in the stash, nothing is paid and the dialog says so. If prices or stock
  changed since the dialog opened, it shows the card again instead of buying. A double click can't buy twice.
  Saves after.
- Fast enough on a full 10×70 stash: the dialog under 100 ms, CONFIRM under 200 ms (no full stash copy for the
  trial; reuse the dialog's plan; cache built cards).

## 4. Out of stock: the closest alternative

- When a line's offer is sold out (counting what the card itself takes), above the player's loyalty, from a
  locked trader, or gone, the closest available offer of the same kind stands in: same weapon class and slot for
  guns, the gun's caliber for rounds, a part of the same kind that fits the gun, the same med type, armor for
  armor, a plain rig for a plain rig. Closest by value and key stats (weights in the config); the same item
  from another trader first; roubles preferred over dollars on a tie, with dollars valued at the exchange's buy
  rate (145).
- A swap is never a downgrade in function: a magazine keeps at least the original's capacity (else the gun's own
  magazine stays), a sight keeps its type, rounds don't drop penetration by more than a tunable share while an
  alternative exists. A gun swapped to another caliber takes its own rounds' caliber with it, and each gun on a
  card keeps its own rounds. With nothing to stand in, the line is left out and not charged (a gun left out takes
  its parts and rounds with it).

## 5. Save current gear as quick-buy

- A named custom card from what is worn and carried: each item mapped to the cheapest offer the player qualifies
  for (else the cheapest anyone sells), parts the gun doesn't come with by slot path, rounds by kind. What no
  trader sells is left out, named when saving and kept on the card ("Not for sale, left out: …"); a card with no
  gun sells no rounds. Up to 5, deletable, saved in the profile (`quick_buys`, save version 15, cleaned on load),
  always unlocked, bought by the same rules.

## 6. Docs and tests

DESIGN §10 (loyalty prices), §16.6 (tabs, a Quick Buy section with the card table and the missing-table note),
§15, README. Suite `tests/quickbuy_test.gd`: loader problems (crafted bad cards for each rule), faction cards,
unlock rules, price = Σ line prices − 10% with the floor and dropping as loyalty rises (every card), buying with
a realistic worn kit (everything old in the stash intact, nothing lost or created, secure container untouched,
magazines and stacks in bounds, stock, money spent, not FIR), paying in dollars and being a dollar short, a full
stash (nothing paid), each substitution rule, nothing to stand in, custom cards (round trip through a save, five
at most, left-outs kept), the tab keys while typing, the dialog's focus, the timing bounds; trading checks for
`Trading.price()` on every path and the no-resale sweep.
