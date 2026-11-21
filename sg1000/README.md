# Donkey Kong — Sega SG-1000 (48 KB Cartridge Edition)

A ground-up Z80 assembly port of **Donkey Kong** for the **Sega SG-1000** targeting the maximum unbanked **48 KB (`$0000–$BFFF`, 49,152 bytes)** cartridge configuration (`sg1000/dkong.sg`).

---

## Highlights & 48 KB Cartridge Utilization

| Subsystem | Details |
| --- | --- |
| **Target Hardware** | Sega SG-1000 (3.58 MHz Z80A, **1 KB Work RAM** `$C000–$C3FF`, TMS9918ANL 16 KB VRAM, SN76489AN PSG, `$DC/$DD` joypad, `$0066` NMI Pause) |
| **ROM Footprint** | **49,152 bytes (`48.00 KB`)** raw headerless `.sg` image (`$0000–$A4E8` = **42.2 KB** active code, graphics, stages & audio; `$BFC0–$BFFF` cartridge signature; no SMS `"TMR SEGA"` header at `$7FF0`) |
| **12 Playable Stages** | **4 Classic Arcade Stages** (`25m Girders`, `50m Pie Factory`, `75m Elevators`, `100m Rivets`) + **8 Remix Tour Stages** (`Crossover`, `Spiral`, `The Pits`, `Rampy`, `DK'94 Span`, `Factory Overdrive`, `Skyscraper Shafts`, `Rivet Citadel`) inspired by `hacking/level examples/*.tmx` |
| **8 Stage Tile Banks** | Dedicated TMS9918A Mode-2 (`Graphics II`, `2` colors per `8×1` row) pattern + color banks (`STAGE0..STAGE7`) giving each Classic & Remix stage its own palette and girder style |
| **8 Full-Screen 3-Bank Mode-2 Screens** | Custom multi-bank (`R3=$FF, R4=$03`, up to 558 unique colored tiles per screen) pixel-art screens: **Title**, **How High Can You Get?**, **Stage-Clear Broken Heart**, **100m Victory Finale**, **Cast & Item Showcase**, **Hall of Fame**, **Game Over**, and **Sound + Stage Lab** |
| **132-Pattern Layered Sprite Atlas** | Layered multi-color sprites (3-color Mario with red cap, tan face overlay & blue overalls; 2-color Donkey Kong with chestnut fur & tan face/grin overlay; 2-color Pauline with golden hair & pink gown), 4-frame rotating death animation, hammer swing overlays, floating score popups (`100`/`300`/`500`/`800`/`1UP`), `"HELP!"` bubble, and coprime (`+5 mod 12`) scanline flicker rotation |
| **Arcade Opening & Intermission Cutscenes** | Full arcade **Opening Cutscene** (Kong climbs twin center ladders carrying Pauline, ripping out rungs behind him, then leaps across stomping 4 times to warp the girders), `"HOW HIGH CAN YOU GET ?"` height tower, **Broken-Heart Escape**, and **100m Tower Collapse + Finale** |
| **SN76489AN 4-Channel Audio** | Pitch-accurate periods (`64..974`) converted directly from `dkong-snd.asm` (`i8035` `$600` pitch table & `$300–$532` pattern playlists): **15 multi-voice music tracks** + **16 swept/noise SFX** |
| **4 Game Modes + Attract Cycle** | **1P US Arcade** (authentic `$3A65` `2→3→4→5` stage progression), **1P JP Arcade** (`25m→50m→75m→100m`), **1P Remix 8-Tour** (all 8 Remix stages), **Sound + Stage Lab** (interactive jukebox & stage warp), plus 4-page **Attract Mode** cycling live gameplay demos across all 4 stage types |

---

## Controls

| SG-1000 Input | In-Game Action | Menus / Sound + Stage Lab |
| --- | --- | --- |
| **D-Pad Left / Right** | Run Left / Right | Change Initial (`A–Z`) / Adjust Stage, Loop, Music, SFX |
| **D-Pad Up / Down** | Climb Ladders | Select Mode / Move Cursor |
| **Button 1** | Jump (hold direction for running jump) | Confirm / Audition Track or SFX / Launch Stage |
| **Button 2** | Jump (secondary button) | Return to Title Menu (from Sound + Stage Lab) |
| **Console Pause (`NMI $0066`)** | Toggle `"PAUSED"` + mute PSG | — |

---

## Building from Source

Requires [`sjasmplus`](https://github.com/z00m128/sjasmplus) and Python 3:

```bash
cd sg1000
make assets   # Regenerate src/gfxdata.asm, src/levels.asm, src/snddata.asm
make          # Assemble 48 KB cartridge -> sg1000/dkong.sg (49,152 bytes)
```

To run automated headless verification using the bundled Z80 + TMS9918A + SN76489 emulator (`tools/emu.py`):

```bash
python3 tools/emu.py dkong.sg --frames 300 --screenshot title.png
```

---

## Memory & VRAM Architecture

### 1 KB Work RAM (`$C000–$C3FF`)
- `$C000–$C07F` (`128 B`): `SPRBUF` — 32-sprite shadow SAT (`$D0` terminated)
- `$C080–$C097` (`24 B`): `PLAYER` — 8.3 fixed-point jump physics, ladder state, animation
- `$C098–$C0A7` (`16 B`): `DK` — Donkey Kong state, pose, patrol/throw timers
- `$C0A8–$C0D7` (`48 B`): `GAME` — BCD score/high-score/bonus, loop, mode, RNG, jukebox state
- `$C0D8–$C137` (`96 B`): `SOLID` — `32×24` 1-bit O(1) collision bitmap (`4 bytes/row`)
- `$C138–$C197` (`96 B`): `ENEMIES` — 12 active obstacle slots (`8 B` each: barrels, blue barrels, fireballs, springs, cement pies)
- `$C198–$C1AF` (`24 B`): `ELEV` — 4 wrapping elevator cars (`6 B` each)
- `$C1B0–$C1BF` (`16 B`): `ITEMS_TAKEN` + `RIVETS_PULLED`
- `$C1C0–$C287` (`200 B`): `LEVELBUF` — active stage descriptor (`182 B`)
- `$C288–$C2AF` (`40 B`): `HISCORES` (Top-5 BCD scores + 3 initials) & `NAMEENTRY`
- `$C2B0–$C307` (`88 B`): `MUSIC` (2-voice SN76489 sequencer + SFX driver) & `SCRATCH`
- `$C308–$C3FF` (`248 B`): Hardware Z80 stack (`SP = $C400`)

### 16 KB TMS9918A VRAM (Zero-Overlap Mode 2)
- `$0000–$17FF`: Pattern Generator Table (single-bank during stages; all 3 banks on full-screen artwork)
- `$1800–$1AFF`: Name Table (`32×24`)
- `$1F80–$1FFF`: Sprite Attribute Table (`32×4` bytes)
- `$2000–$37FF`: Color Table (`2` colors per `8×1` pixel row)
- `$3800–$3FFF`: Sprite Pattern Generator (`132` `8×8` patterns)
