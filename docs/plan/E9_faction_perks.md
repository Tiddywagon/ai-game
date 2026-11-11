# E9: Faction perks

From notes: BEAR and USEC get a faction-only trader discount and a faction quest line (starting gear by faction
is already built).

- **Discount**: the faction's trader (BEAR: Bulat, USEC: Tinker; `GameState.FACTION_TRADER`) sells to that
  faction a few percent cheaper (tunable in `data/config/factions.json`), on top of loyalty prices, through
  `Trading.price()`, never below the resale floor; shown on the trader's panel and BUY rows.
- **Quest line**: 5 quests per faction from the faction's trader, visible only to that faction, chained, with
  objectives the game already supports (kills of the other faction's PMCs, hand-ins, extracts, exploration) and
  rewards that fit: money, reputation, a faction-themed weapon or armor, and at the end a faction-only barter or
  quick-buy card. Quest counts used elsewhere (quick-buy unlocks) count only quests the player can see.
- DESIGN §3, §10, §11, README; suite `tests/faction_perks_test.gd` (discount on every price path and its floor,
  quests hidden from the other faction, the chain, rewards, save round trip).
