# BuffGlow

A World of Warcraft Classic addon that reminds you about missing long-duration buffs with a soft, pulsing glow.

- **Your portrait glows** when you're missing a long buff you can cast on yourself.
- **Your target glows** when you click a friendly player who is missing a buff you can give them. The glow shows on their nameplate and on the target frame portrait.
- **Each buff has its own colour**, matched to its icon. If several buffs are missing, the glow blends from one colour to the next on each pulse. For example, a Priest missing Fortitude and Inner Fire sees white, then gold.

## Supported buffs

| Class | Buffs |
|---|---|
| Mage | Arcane Intellect / Brilliance, Frost / Ice / Mage / Molten Armor |
| Priest | Power Word: Fortitude, Inner Fire, Divine Spirit, Shadow Protection (off by default) |
| Druid | Mark / Gift of the Wild, Thorns, Omen of Clarity |
| Warlock | Demon Skin / Demon Armor / Fel Armor |
| Paladin | A Blessing cast by you (including Greater Blessings), Righteous Fury (off by default) |
| Shaman | Lightning / Water Shield |

Buffs only trigger once you've learned the spell. Self-only buffs, such as Inner Fire and the armors, never trigger the target glow.

## Installation

Copy the `BuffGlow` folder into your AddOns folder, for example:

```
World of Warcraft\_classic_era_\Interface\AddOns\BuffGlow
```

Then restart the game and make sure BuffGlow is ticked in the AddOns list.

To see target glows on nameplates, turn on friendly player nameplates (Shift+V by default).

## Options

Open **Esc > Options > AddOns > BuffGlow**, or type `/bglow config`. The options are:

- Which buffs to watch
- Whether the target glow is on
- Portrait glow size
- How much of each pulse is spent blending between buff colours
- Pulse speed
- A test button

### Slash commands

| Command | What it does |
|---|---|
| `/bglow config` | Open the options panel |
| `/bglow list` | Show your class's buffs and whether each is on |
| `/bglow toggle <key>` | Turn one buff on or off (keys come from `list`) |
| `/bglow target` | Turn target glows on or off |
| `/bglow glowsize <n>` | Portrait glow size, 1 to 3 (default 1.45) |
| `/bglow fade <n>` | Colour blend between buffs, 0 to 1 (default 0.6) |
| `/bglow speed <n>` | Seconds per pulse, 0.5 to 4 (default 1.6) |
| `/bglow test` | Show the glow for 5 seconds |

Settings are saved per character.

## License

MIT. See [LICENSE](LICENSE).
