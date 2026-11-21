# Donkey Kong — Sega SG-1000 (48 KB Cartridge Edition)

A ground-up Z80 assembly port of **Donkey Kong** for the **Sega SG-1000** targeting the maximum unbanked **48 KB (`$0000–$BFFF`, 49,152 bytes)** cartridge configuration (`sg1000/dkong.sg`).

---

## Highlights & 48 KB Cartridge Utilization

| Subsystem | Details |
| --- | --- |
| **Target Hardware** | Sega SG-1000 (3.58 MHz Z80A, **1 KB Work RAM** `$C000–$C3FF`, TMS9918ANL 16 KB VRAM, SN76489AN PSG, `$DC/$DD` joypad, `$0066` NMI Pause) |
| **ROM Footprint** | **49,152 bytes (`48.00 KB`)** raw headerless `.sg` image (`$0000–$AF48` = **44.9 KB** active code, graphics, stages & audio; `$BFC0–$BFFF` cartridge signature; no SMS `"TMR SEGA"` header at `$7FF0`) |
| **12 Playable Stages** | **4 Authentic Original Arcade Stages** (`25m Barrels` `$3AE4` with sub-pixel sloped girders `T_SLOPE_0..3` & wild vertical 1st barrel oil-drum ignition, `50m Pie Factory` `$3B5D` with telescoping top ladders + dual split conveyors feeding the central Oil Vat + `XXX` furnace, `75m Elevators` `$3BE5` with silent shaft per `dkong-snd.asm:$50A=$00` + rising/descending cable elevators + 21-girder stepping-stone network + bouncing Jack-Springs + top-pulley crush & lethal bottom girder, `100m Rivets` `$3C8B` with circle-perforated royal-blue girders & walk/jump rivet pulls) + **8 Remix Tour Stages** |
| **8 Stage Tile Banks + Framed `[BONUS]` HUD** | Dedicated TMS9918A Mode-2 (`Graphics II`, `2` colors per `8×1` row) pattern + color banks (`STAGE0..STAGE7`) with authentic 1981 arcade palettes (`25m` magenta/crimson girders + white/cyan ladders, `50m` golden-ochre/red girders + warm conveyors + cyan ladders, `75m` red/salmon girders + yellow ladders + cyan cables, `100m` royal-blue circle girders + yellow rivets), red `1UP`/`HIGH` headers, and framed cyan `[BONUS]` scoreboard box |
| **8 Full-Screen 3-Bank Mode-2 Screens** | Custom multi-bank (`R3=$FF, R4=$03`, up to 558 unique colored tiles per screen) pixel-art screens: **Title**, **How High Can You Get?**, **Stage-Clear Broken Heart**, **100m Victory Finale**, **Cast & Item Showcase**, **Hall of Fame**, **Game Over**, and **Sound + Stage Lab** |
| **163-Pattern Layered Sprite Atlas & `24×24` Boss Kong** | Flicker-free **`24×24` Multi-Color Donkey Kong** (`3×3` `8×8` chestnut fur grid + tan face & muscular chest overlays = `<= 4` sprites/scanline, plus golden-amber held barrel in pose 3), 3-color Mario (red cap/shirt, tan face overlay, blue overalls), 2-color Pauline with 50% duty-cycle `"HELP!"` callout, 4-frame rotating death animation, hammer swing overlays, floating score popups (`100`/`300`/`500`/`800`/`1UP`), and coprime (`+5 mod 12`) scanline flicker rotation |
| **Arcade Opening & Intermission Cutscenes** | Full arcade **Opening Cutscene** (`24×24` Kong climbs twin center ladders carrying Pauline, ripping out rungs behind him, then hops 4 times progressively bending each girder tier from flat into crooked `T_SLOPE_0..3` before his 3-part Gorilla Roar), `"HOW HIGH CAN YOU GET ?"` height tower, **Heart -> Shattered Broken-Heart + Kong Climb-Off Escape**, and **100m Tower Collapse + Odd/Even Victory Finale** |
| **SN76489AN 4-Channel `i8035` Audio** | Pitch-accurate periods (`64..974`) & register math derived directly from `dkong-snd.asm`: **15 multi-voice music tracks** with `ENV_PLUCK` (`$54C-$57B` 5-frame plucked bass gate + `$13F` upward pitch scoop) & `ENV_DECAY` (`$15E-$17F` RC decay + warm vibrato) + **16 `i8035`-simulated SFX** including Tone-2-clocked Periodic Noise (`$03`, `f_tone2/16`) 3-part Gorilla Roar, `$009-$03A -> TRK_MUS_DEATH_TAIL` Death sweep, Smash (`$0C6-$0EE`), Spring (`$0A8-$0C4`), Fall/Drop (`$5BA-$5E3`), and `Pattern $08` Score arpeggio |
| **Arcade Physics & Enemy AI** | Committed airborne horizontal velocity (`P_VX`, no mid-air reversal), lethal `>= 18 px` fall-height death, sub-pixel `0..+3 px` sloped girder tracking for Mario/Barrels/Fireballs, Mario-position-aware Blue/Brown Barrel ladder pursuit, horizontal `P_X` + vertical ladder pursuit & conveyor drift on Fireballs, and trailing-heel walk/jump Rivet pulls |
| **4 Game Modes + Attract Cycle** | **1P Arcade 4-Stage** (default — plays all 4 original stages `25m → 50m Pie Factory → 75m Elevators → 100m Rivets` right from `L=01`), **1P US Tournament** (authentic `$3A65` `2→3→4→5` stage progression), **1P Remix 8-Tour** (all 8 Remix stages), **Sound + Stage Lab** (interactive jukebox & stage warp), plus 4-page **Attract Mode** cycling live gameplay demos across all 4 stage types |

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
python3 tools/emu.py dkong.sg --frames 300 --shot title.png
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
- `$C1C0–$C297` (`216 B`): `LEVELBUF` — active stage descriptor (`210 B`)
- `$C298–$C2BF` (`40 B`): `HISCORES` (Top-5 BCD scores + 3 initials) & `NAMEENTRY`
- `$C2C0–$C317` (`88 B`): `MUSIC` (2-voice SN76489 sequencer + SFX driver) & `SCRATCH`
- `$C318–$C3FF` (`232 B`): Hardware Z80 stack (`SP = $C400`)

### 16 KB TMS9918A VRAM (Zero-Overlap Mode 2)
- `$0000–$17FF`: Pattern Generator Table (single-bank during stages; all 3 banks on full-screen artwork)
- `$1800–$1AFF`: Name Table (`32×24`)
- `$1F80–$1FFF`: Sprite Attribute Table (`32×4` bytes)
- `$2000–$37FF`: Color Table (`2` colors per `8×1` pixel row)
- `$3800–$3FFF`: Sprite Pattern Generator (`163` `8×8` patterns)
