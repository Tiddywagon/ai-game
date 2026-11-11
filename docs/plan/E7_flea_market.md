# E7: Flea market (unlocks at player level 15)

From notes: a flea market at level 15 with AI listings, prices that drift, the player's own listings that sell
depending on how fair the price is, and banned items. Details below are designed here.

- **Data**: `data/config/flea.json` (unlock level, refresh period, listing counts by rarity, price spread, drift
  bounds and speed, fees, listing slots, sale-time curve, banned ids / categories / tags), loader with
  `problems()`.
- **Market price**: an item's worth × a per-item multiplier that drifts over real time (a seeded bounded random
  walk per time bucket, e.g. ×0.8-×1.4, the same for everyone on the same clock) plus the player's own pressure
  (buying an item nudges it up, selling nudges it down, decaying over hours; saved).
- **AI listings**: per refresh (real time, also while the game is closed), a seeded set of listings: item (guns
  and armor with a condition, guns sometimes with extra parts), count, price = market price × a spread, a made-up
  seller name and rating, time left. Rarer items are listed less often; Legendary almost never. Buying pays
  roubles, the item arrives in the stash, never found in raid. No listing is ever cheaper than the best trader
  buy price plus the resale margin.
- **Own listings**: only found-in-raid items from the stash, a fee up front (a share of the asking price,
  growing when the price is above market), slots by level (3 at level 15, +1 per 5 levels). Whether and when it
  sells depends on fairness: at or under market it sells within minutes, a little over takes longer, far over
  doesn't sell and comes back when the listing expires. Progress continues while the game is closed; money and
  expired items are collected from the market screen (and a notice in the main menu).
- **Banned**: quest items, keys and keycards, secure containers, boss uniques, the top armor-piercing rounds
  and anything the config lists: they can't be listed and never appear.
- **Screen**: FLEA MARKET from the main menu and the TRADERS screen (locked with "Level 15" before that): BROWSE
  (search, category and rarity filters, sort by price / time left / value for money, price trend arrow and the
  trader price beside it), SELL (stash beside a listing form with the market price, the fee and an estimate of
  how fast it sells), MY LISTINGS (time left, sold → COLLECT).
- Save version bump (listings, pressure, the market clock), DESIGN §10/§14/§16, README, suite
  `tests/flea_test.gd` (unlock, seeded listings repeat, drift bounds, floor against trader prices, buy, list with
  fee and slots, sale timing by fairness incl. offline, expiry return, banned items, save round trip, screen).
