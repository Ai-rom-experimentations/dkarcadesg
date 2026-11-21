#!/usr/bin/env python3
"""
Generate 12 stage descriptors (4 Classic Arcade + 8 Remix Edition),
stage-order tables (Default Mode 0 plays all 4 original stages 25m -> 50m ->
75m -> 100m right from Level 1; Mode 1 plays US Set-1 tournament order;
Mode 2 plays 8-Stage Remix Tour), and 4 live Attract-Mode Demo scripts.

50m (Pie Factory) matches dkong.asm:$3B5D & pie-factory.tmx:
  - Top conveyor with sliding Kong
  - Left & right telescoping top ladders (LF_TELESCOPE)
  - Dual split conveyors feeding inward into the central Oil Vat + XXX patch
  - Three split solid ledges with two jumpable gaps + 2 middle ladders
  - Lower full-width conveyor + 4 bottom ladders + bottom girder

75m (Elevators) matches dkong.asm:$3BE5 & elevators.tmx:
  - Left 3-tier ladder tower + Umbrella ledge
  - Rising Left Elevator & Descending Middle Elevator cables + pulleys
  - Central twin-ladder island with Hat
  - Full lower-right, mid-right, and upper-right Purse stepping-stone network
  - Bouncing Jack-Springs dropping down col 22 shaft + lethal bottom girder

Output: src/levels.asm
"""
import os

MAX_PLATS    = 22
MAX_LADDERS  = 16
MAX_RIVETS   = 8
MAX_ITEMS    = 6

LT_GIRDERS   = 0
LT_PIES      = 1
LT_ELEVATORS = 2
LT_RIVETS    = 3

PF_NORMAL    = 0
PF_CONV_R    = 1
PF_CONV_L    = 2

LF_NORMAL    = 0
LF_BROKEN    = 1
LF_DECOR     = 2
LF_TELESCOPE = 3

T_HAMMER     = 14
T_ITEM_HAT   = 16
T_ITEM_PURSE = 17
T_ITEM_UMB   = 18

TRK_STAGE1   = 0    # TRK_BGM_BARRELS
TRK_STAGE2   = 1    # TRK_BGM_PIEFACTORY
TRK_STAGE3   = 2    # TRK_BGM_ELEVATORS
TRK_STAGE4   = 3    # TRK_BGM_RIVETS


def encode_level(lv):
    out = bytearray()
    out.append(lv['ltype'])
    out.append(lv['gfxbank'])
    out.append(lv['bgm'])
    out.append(lv['height_idx'])
    out.extend(lv['mario'])
    out.extend(lv['dk'])
    out.extend(lv['pauline'])
    out.extend(lv.get('oil', (0xFF, 0)))
    out.extend(lv.get('stack', (0xFF, 0)))
    out.extend(lv.get('elev_cols', (0xFF, 0xFF)))
    out.append(lv.get('barrel_int', 110))
    out.append(lv.get('max_fires', 3))
    out.extend(lv.get('bonus', (0x50, 0x00)))

    plats = lv['plats'][:MAX_PLATS]
    out.append(len(plats))
    for p in plats + [(0, 0, 0, 0)] * (MAX_PLATS - len(plats)):
        out.extend([p[0] & 0xFF, p[1] & 0xFF, p[2] & 0xFF, p[3] & 0xFF])

    lads = lv['ladders'][:MAX_LADDERS]
    out.append(len(lads))
    for l in lads + [(0, 0, 0, 0)] * (MAX_LADDERS - len(lads)):
        out.extend([l[0] & 0xFF, l[1] & 0xFF, l[2] & 0xFF, l[3] & 0xFF])

    rivs = lv.get('rivets', [])[:MAX_RIVETS]
    out.append(len(rivs))
    for r in rivs + [(0, 0)] * (MAX_RIVETS - len(rivs)):
        out.extend([r[0] & 0xFF, r[1] & 0xFF])

    items = lv.get('items', [])[:MAX_ITEMS]
    out.append(len(items))
    for it in items + [(0, 0, 0)] * (MAX_ITEMS - len(items)):
        out.extend([it[0] & 0xFF, it[1] & 0xFF, it[2] & 0xFF])

    return bytes(out)


# ============================================================================
# 4 ORIGINAL ARCADE STAGES (25m Barrels, 50m Pie Factory, 75m Elevators, 100m Rivets)
# ============================================================================

# Stage 1 (25m): Girders / Barrels (dkong.asm $3AE4 / barrels.tmx)
STAGE_25M = {
    'ltype': LT_GIRDERS,
    'gfxbank': 0,
    'bgm': TRK_STAGE1,
    'height_idx': 0,
    'mario': (5, 22),
    'dk': (5, 7),
    'pauline': (13, 4),
    'oil': (2, 20),
    'stack': (1, 5),
    'barrel_int': 110,
    'max_fires': 3,
    'bonus': (0x50, 0x00),
    'plats': [
        (12, 17, 4, PF_NORMAL),
        (0, 29, 7, PF_NORMAL),
        (2, 31, 10, PF_NORMAL),
        (0, 29, 13, PF_NORMAL),
        (2, 31, 16, PF_NORMAL),
        (0, 29, 19, PF_NORMAL),
        (0, 31, 22, PF_NORMAL),
    ],
    'ladders': [
        (9, 2, 7, LF_DECOR),
        (11, 2, 7, LF_DECOR),
        (16, 4, 7, LF_NORMAL),
        (26, 7, 10, LF_NORMAL),
        (13, 7, 10, LF_BROKEN),
        (5, 10, 13, LF_NORMAL),
        (18, 10, 13, LF_NORMAL),
        (26, 13, 16, LF_NORMAL),
        (10, 13, 16, LF_BROKEN),
        (5, 16, 19, LF_NORMAL),
        (20, 16, 19, LF_BROKEN),
        (26, 19, 22, LF_NORMAL),
    ],
    'items': [
        (4, 9, T_HAMMER),
        (16, 18, T_HAMMER),
        (22, 9, T_ITEM_HAT),
        (28, 15, T_ITEM_PURSE),
    ],
}

# Stage 2 (50m): Pie Factory / Conveyors (exact dkong.asm $3B5D & pie-factory.tmx!)
STAGE_50M = {
    'ltype': LT_PIES,
    'gfxbank': 1,
    'bgm': TRK_STAGE2,
    'height_idx': 1,
    'mario': (5, 22),
    'dk': (15, 7),
    'pauline': (13, 4),
    'oil': (15, 13),            # 2x2 Oil Vat at cols 15..16, rows 13..14 (flames at row 12!)
    'barrel_int': 112,
    'max_fires': 3,
    'bonus': (0x50, 0x00),
    'plats': [
        (12, 18, 4, PF_NORMAL),     # $3BB7: girder where Pauline sits
        (1, 30, 7, PF_CONV_R),      # $3BBC: top conveyor girder (Kong slides here)
        (0, 13, 11, PF_CONV_R),     # $3BC6: top-left split conveyor feeding into Oil Vat
        (18, 31, 11, PF_CONV_L),    # $3BC1: top-right split conveyor feeding into Oil Vat
        (2, 6, 15, PF_NORMAL),      # $3BD5: left center ledge (has Hammer)
        (9, 22, 15, PF_NORMAL),     # $3BCB: middle center ledge (supports Oil Vat + XXX)
        (25, 29, 15, PF_NORMAL),    # $3BD0: right center ledge
        (1, 30, 19, PF_CONV_R),     # $3BDA: main lower conveyor girder (has Hammer)
        (1, 30, 22, PF_NORMAL),     # $3BDF: bottom level girder
    ],
    'ladders': [
        (9, 2, 7, LF_DECOR),        # $3B7B: Kong's left ladder
        (11, 2, 7, LF_DECOR),       # $3B6C: Kong's right ladder
        (17, 4, 7, LF_NORMAL),      # $3BB2: ladder leading to Pauline
        (3, 7, 11, LF_TELESCOPE),   # $3B8F: top telescoping ladder (left side)
        (28, 7, 11, LF_TELESCOPE),  # $3B94: top telescoping ladder (right side)
        (4, 11, 15, LF_NORMAL),     # $3B99: ladder on left platform with Hammer
        (11, 11, 15, LF_NORMAL),    # $3B71: center ladder left of Oil Vat fire
        (20, 11, 15, LF_NORMAL),    # $3B85: center ladder right of Oil Vat fire
        (27, 11, 15, LF_NORMAL),    # $3B9E: ladder on right platform with Umbrella
        (10, 15, 19, LF_NORMAL),    # $3B80: ladder under the Hat
        (21, 15, 19, LF_NORMAL),    # $3BA3: ladder to right of lower Hammer
        (4, 19, 22, LF_NORMAL),     # $3BA8: bottom level ladder #1 of 4
        (11, 19, 22, LF_NORMAL),    # $3B76: bottom level ladder #2 of 4
        (20, 19, 22, LF_NORMAL),    # $3B8A: bottom level ladder #3 of 4
        (27, 19, 22, LF_NORMAL),    # $3BAD: bottom level ladder #4 of 4
    ],
    'items': [
        (3, 14, T_HAMMER),          # Left ledge Hammer ($3BD5)
        (16, 18, T_HAMMER),         # Lower conveyor Hammer ($3BDA)
        (10, 14, T_ITEM_HAT),       # Hat above $3B80 ladder
        (29, 10, T_ITEM_UMB),       # Umbrella on right conveyor beside telescoping ladder
        (28, 21, T_ITEM_PURSE),     # Purse on bottom right
    ],
}

# Stage 3 (75m): Elevators / Springs (exact dkong.asm $3BE5 & elevators.tmx!)
STAGE_75M = {
    'ltype': LT_ELEVATORS,
    'gfxbank': 2,
    'bgm': TRK_STAGE3,
    'height_idx': 2,
    'mario': (2, 20),               # $3C80: girder where Mario starts (above lethal row 23!)
    'dk': (3, 7),
    'pauline': (13, 4),
    'elev_cols': (5, 13),           # Left rising shaft (cols 5..6) & Mid descending shaft (cols 13..14)
    'barrel_int': 88,
    'max_fires': 2,
    'bonus': (0x50, 0x00),
    'plats': [
        (11, 18, 4, PF_NORMAL),     # $3C21: girder Pauline is on
        (1, 21, 7, PF_NORMAL),      # $3C26: Kong's girder (continuous!)
        # Left tower (cols 1..3)
        (1, 3, 11, PF_NORMAL),      # $3C34: girder that holds the Umbrella
        (1, 3, 16, PF_NORMAL),      # $3C62: girder just above Mario start
        (1, 3, 20, PF_NORMAL),      # $3C80: girder where Mario starts
        # Central ladder section between elevators (cols 8..11)
        (8, 11, 11, PF_NORMAL),     # $3C3F: top central island girder (holds Hat)
        (8, 11, 19, PF_NORMAL),     # $3C6C: bottom central island girder
        # Lower-right ascending stepping stones (rows 20 -> 18)
        (16, 18, 20, PF_NORMAL),    # $3C7B: floating girder where right elevator gets off
        (20, 22, 19, PF_NORMAL),    # $3C76: stepping stone #1
        (24, 26, 18, PF_NORMAL),    # $3C71: stepping stone #2
        (28, 30, 18, PF_NORMAL),    # $3C67: far bottom-right girder
        # Mid-right stepping stones (rows 15 -> 14 -> 11)
        (28, 30, 15, PF_NORMAL),    # $3C5D: far-right mid girder
        (24, 26, 15, PF_NORMAL),    # $3C58: mid stepping stone #1
        (20, 22, 14, PF_NORMAL),    # $3C53: mid stepping stone #2
        (16, 18, 14, PF_NORMAL),    # $3C4E: bottom girder right of top-right elevator
        (16, 18, 11, PF_NORMAL),    # $3C3A: top girder right of top-right elevator
        # Upper-right Purse tower & final stepping stones to Kong's level
        (24, 30, 12, PF_NORMAL),    # $3C39: girder under the Purse girder
        (28, 30, 9, PF_NORMAL),     # $3C2B: girder where Purse is
        (24, 26, 9, PF_NORMAL),     # $3C30: stepping stone left of Purse
        (20, 22, 10, PF_NORMAL),    # $3C35: girder holding ladder up to Kong's level
        # Lethal bottom girder ($3C85)
        (0, 31, 23, PF_NORMAL),     # $3C85: long bottom girder (lethal if Mario drops this low!)
    ],
    'ladders': [
        (9, 2, 7, LF_DECOR),        # $3BEF: Kong's ladder (left)
        (11, 2, 7, LF_DECOR),       # $3BE5: Kong's ladder (right)
        (17, 4, 7, LF_NORMAL),      # $3C12: ladder leading up to Pauline
        (3, 11, 16, LF_NORMAL),     # $3C17: long ladder on left side
        (2, 16, 20, LF_NORMAL),     # $3C1C: bottom-left ladder
        (8, 11, 19, LF_NORMAL),     # $3BF4: center ladder left
        (11, 11, 19, LF_NORMAL),    # $3BEA: center ladder right
        (29, 15, 18, LF_NORMAL),    # $3BFE: far bottom-right ladder
        (17, 11, 14, LF_NORMAL),    # $3C0D: ladder right of top-right elevator
        (25, 12, 15, LF_NORMAL),    # $3C03: ladder leading to Purse (lower level)
        (29, 9, 12, LF_NORMAL),     # $3BF9: far top-right ladder leading to Purse
        (21, 7, 10, LF_NORMAL),     # $3C08: ladder leading to Kong's level
    ],
    'items': [
        (1, 10, T_ITEM_UMB),        # Umbrella on top-left ledge ($3C34)
        (9, 10, T_ITEM_HAT),        # Hat on central island ($3C3F)
        (29, 8, T_ITEM_PURSE),      # Purse on top-right ledge ($3C2B)
    ],
}

# Stage 4 (100m): Rivets (dkong.asm $3C8B / rivets.tmx)
STAGE_100M = {
    'ltype': LT_RIVETS,
    'gfxbank': 3,
    'bgm': TRK_STAGE4,
    'height_idx': 3,
    'mario': (2, 22),
    'dk': (15, 7),
    'pauline': (15, 4),
    'barrel_int': 130,
    'max_fires': 4,
    'bonus': (0x50, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (4, 27, 7, PF_NORMAL),
        (3, 28, 11, PF_NORMAL),
        (2, 29, 15, PF_NORMAL),
        (1, 30, 19, PF_NORMAL),
        (0, 31, 22, PF_NORMAL),
    ],
    'ladders': [
        (4, 7, 11, LF_NORMAL),
        (15, 7, 11, LF_NORMAL),
        (27, 7, 11, LF_NORMAL),
        (3, 11, 15, LF_NORMAL),
        (11, 11, 15, LF_NORMAL),
        (20, 11, 15, LF_NORMAL),
        (28, 11, 15, LF_NORMAL),
        (2, 15, 19, LF_NORMAL),
        (9, 15, 19, LF_NORMAL),
        (22, 15, 19, LF_NORMAL),
        (29, 15, 19, LF_NORMAL),
        (1, 19, 22, LF_NORMAL),
        (15, 19, 22, LF_NORMAL),
        (30, 19, 22, LF_NORMAL),
    ],
    'rivets': [
        (8, 7), (23, 7),
        (8, 11), (23, 11),
        (8, 15), (23, 15),
        (8, 19), (23, 19),
    ],
    'items': [
        (15, 6, T_HAMMER),
        (2, 14, T_HAMMER),
        (26, 10, T_ITEM_UMB),
        (5, 18, T_ITEM_HAT),
        (26, 18, T_ITEM_PURSE),
    ],
}

# ============================================================================
# 8 REMIX EDITION STAGES (honoring hacking/level examples/*.tmx + 8 banks)
# ============================================================================
STAGE_REMIX_1 = {
    'ltype': LT_GIRDERS,
    'gfxbank': 4,
    'bgm': TRK_STAGE1,
    'height_idx': 0,
    'mario': (3, 22),
    'dk': (4, 7),
    'pauline': (14, 4),
    'oil': (15, 20),
    'stack': (1, 5),
    'barrel_int': 96,
    'max_fires': 3,
    'bonus': (0x60, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (0, 31, 7, PF_NORMAL),
        (1, 30, 10, PF_NORMAL),
        (0, 31, 13, PF_NORMAL),
        (1, 30, 16, PF_NORMAL),
        (0, 31, 19, PF_NORMAL),
        (0, 31, 22, PF_NORMAL),
    ],
    'ladders': [
        (9, 2, 7, LF_DECOR),
        (17, 4, 7, LF_NORMAL),
        (22, 7, 10, LF_NORMAL),
        (10, 7, 10, LF_BROKEN),
        (12, 10, 13, LF_NORMAL),
        (15, 10, 13, LF_BROKEN),
        (21, 10, 13, LF_NORMAL),
        (9, 13, 16, LF_NORMAL),
        (19, 13, 16, LF_NORMAL),
        (2, 16, 19, LF_NORMAL),
        (15, 16, 19, LF_BROKEN),
        (29, 16, 19, LF_NORMAL),
        (9, 19, 22, LF_NORMAL),
        (22, 19, 22, LF_NORMAL),
    ],
    'items': [
        (6, 9, T_HAMMER),
        (25, 15, T_HAMMER),
        (3, 12, T_ITEM_UMB),
        (28, 9, T_ITEM_PURSE),
    ],
}

STAGE_REMIX_2 = {
    'ltype': LT_GIRDERS,
    'gfxbank': 5,
    'bgm': TRK_STAGE2,
    'height_idx': 1,
    'mario': (3, 22),
    'dk': (4, 7),
    'pauline': (14, 4),
    'oil': (28, 20),
    'stack': (1, 5),
    'barrel_int': 98,
    'max_fires': 3,
    'bonus': (0x60, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (0, 27, 7, PF_NORMAL),
        (0, 12, 10, PF_NORMAL),
        (15, 31, 11, PF_NORMAL),
        (0, 16, 14, PF_NORMAL),
        (19, 31, 15, PF_NORMAL),
        (0, 20, 18, PF_NORMAL),
        (22, 31, 19, PF_NORMAL),
        (0, 31, 22, PF_NORMAL),
    ],
    'ladders': [
        (17, 4, 7, LF_NORMAL),
        (25, 7, 11, LF_NORMAL),
        (10, 7, 10, LF_NORMAL),
        (16, 11, 14, LF_NORMAL),
        (4, 10, 14, LF_BROKEN),
        (19, 15, 18, LF_NORMAL),
        (8, 14, 18, LF_NORMAL),
        (28, 15, 19, LF_NORMAL),
        (16, 18, 22, LF_NORMAL),
        (25, 19, 22, LF_NORMAL),
        (4, 18, 22, LF_BROKEN),
    ],
    'items': [
        (6, 9, T_HAMMER),
        (25, 14, T_HAMMER),
        (2, 13, T_ITEM_HAT),
        (29, 18, T_ITEM_UMB),
    ],
}

STAGE_REMIX_3 = {
    'ltype': LT_ELEVATORS,
    'gfxbank': 6,
    'bgm': TRK_STAGE3,
    'height_idx': 2,
    'mario': (2, 22),
    'dk': (3, 7),
    'pauline': (14, 4),
    'elev_cols': (8, 18),
    'barrel_int': 84,
    'max_fires': 2,
    'bonus': (0x60, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (0, 21, 7, PF_NORMAL),
        (24, 30, 11, PF_NORMAL),
        (1, 6, 12, PF_NORMAL),
        (11, 16, 11, PF_NORMAL),
        (1, 6, 16, PF_NORMAL),
        (11, 16, 15, PF_NORMAL),
        (21, 26, 15, PF_NORMAL),
        (0, 6, 22, PF_NORMAL),
        (11, 16, 19, PF_NORMAL),
        (21, 31, 19, PF_NORMAL),
        (21, 31, 22, PF_NORMAL),
        (0, 31, 23, PF_NORMAL),
    ],
    'ladders': [
        (18, 4, 7, LF_NORMAL),
        (21, 7, 11, LF_NORMAL),
        (13, 11, 15, LF_NORMAL),
        (4, 12, 16, LF_NORMAL),
        (25, 11, 15, LF_NORMAL),
        (15, 15, 19, LF_NORMAL),
        (23, 15, 19, LF_NORMAL),
        (3, 16, 22, LF_NORMAL),
        (28, 19, 22, LF_NORMAL),
    ],
    'items': [
        (13, 10, T_ITEM_UMB),
        (27, 10, T_ITEM_HAT),
        (25, 21, T_ITEM_PURSE),
    ],
}

STAGE_REMIX_4 = {
    'ltype': LT_GIRDERS,
    'gfxbank': 0,
    'bgm': TRK_STAGE1,
    'height_idx': 1,
    'mario': (2, 22),
    'dk': (4, 7),
    'pauline': (14, 4),
    'oil': (2, 15),
    'stack': (1, 5),
    'barrel_int': 94,
    'max_fires': 3,
    'bonus': (0x60, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (0, 29, 7, PF_NORMAL),
        (2, 31, 11, PF_NORMAL),
        (0, 29, 14, PF_NORMAL),
        (0, 31, 17, PF_NORMAL),
        (22, 31, 19, PF_NORMAL),
        (14, 25, 20, PF_NORMAL),
        (7, 17, 21, PF_NORMAL),
        (0, 10, 22, PF_NORMAL),
    ],
    'ladders': [
        (17, 4, 7, LF_NORMAL),
        (26, 7, 11, LF_NORMAL),
        (12, 7, 11, LF_BROKEN),
        (5, 11, 14, LF_NORMAL),
        (20, 11, 14, LF_NORMAL),
        (27, 14, 17, LF_NORMAL),
        (11, 14, 17, LF_BROKEN),
        (29, 17, 19, LF_NORMAL),
    ],
    'items': [
        (16, 10, T_HAMMER),
        (7, 16, T_HAMMER),
        (25, 18, T_ITEM_PURSE),
        (3, 10, T_ITEM_HAT),
    ],
}

STAGE_REMIX_5 = {
    'ltype': LT_GIRDERS,
    'gfxbank': 4,
    'bgm': TRK_STAGE1,
    'height_idx': 2,
    'mario': (3, 22),
    'dk': (4, 7),
    'pauline': (14, 4),
    'oil': (28, 20),
    'stack': (1, 5),
    'barrel_int': 92,
    'max_fires': 3,
    'bonus': (0x70, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (0, 25, 7, PF_NORMAL),
        (16, 25, 11, PF_NORMAL),
        (0, 31, 15, PF_NORMAL),
        (0, 11, 19, PF_NORMAL),
        (14, 19, 19, PF_NORMAL),
        (22, 31, 19, PF_NORMAL),
        (0, 31, 22, PF_NORMAL),
    ],
    'ladders': [
        (17, 4, 7, LF_NORMAL),
        (9, 7, 15, LF_NORMAL),
        (22, 7, 11, LF_NORMAL),
        (19, 11, 15, LF_NORMAL),
        (2, 15, 19, LF_NORMAL),
        (7, 15, 19, LF_NORMAL),
        (30, 15, 19, LF_NORMAL),
        (4, 19, 22, LF_NORMAL),
        (25, 19, 22, LF_NORMAL),
    ],
    'items': [
        (18, 10, T_HAMMER),
        (16, 18, T_HAMMER),
        (24, 6, T_ITEM_UMB),
        (28, 18, T_ITEM_PURSE),
    ],
}

STAGE_REMIX_6 = {
    'ltype': LT_PIES,
    'gfxbank': 5,
    'bgm': TRK_STAGE2,
    'height_idx': 1,
    'mario': (15, 22),
    'dk': (15, 7),
    'pauline': (14, 4),
    'oil': (15, 13),
    'barrel_int': 102,
    'max_fires': 4,
    'bonus': (0x70, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (1, 30, 7, PF_CONV_L),
        (0, 13, 11, PF_CONV_R),
        (18, 31, 11, PF_CONV_L),
        (1, 12, 15, PF_CONV_L),
        (19, 30, 15, PF_CONV_R),
        (14, 17, 15, PF_NORMAL),
        (1, 30, 19, PF_CONV_L),
        (0, 31, 22, PF_NORMAL),
    ],
    'ladders': [
        (15, 4, 7, LF_NORMAL),
        (3, 7, 11, LF_TELESCOPE),
        (28, 7, 11, LF_TELESCOPE),
        (10, 11, 15, LF_NORMAL),
        (21, 11, 15, LF_NORMAL),
        (3, 15, 19, LF_NORMAL),
        (11, 15, 19, LF_NORMAL),
        (20, 15, 19, LF_NORMAL),
        (28, 15, 19, LF_NORMAL),
        (6, 19, 22, LF_NORMAL),
        (25, 19, 22, LF_NORMAL),
    ],
    'items': [
        (8, 10, T_HAMMER),
        (23, 14, T_HAMMER),
        (2, 18, T_ITEM_HAT),
        (29, 18, T_ITEM_PURSE),
    ],
}

STAGE_REMIX_7 = {
    'ltype': LT_ELEVATORS,
    'gfxbank': 6,
    'bgm': TRK_STAGE3,
    'height_idx': 2,
    'mario': (2, 20),
    'dk': (3, 7),
    'pauline': (14, 4),
    'elev_cols': (6, 15),
    'barrel_int': 80,
    'max_fires': 2,
    'bonus': (0x70, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (1, 21, 7, PF_NORMAL),
        (1, 4, 11, PF_NORMAL),
        (1, 4, 16, PF_NORMAL),
        (1, 4, 20, PF_NORMAL),
        (9, 13, 11, PF_NORMAL),
        (9, 13, 19, PF_NORMAL),
        (18, 20, 20, PF_NORMAL),
        (22, 24, 19, PF_NORMAL),
        (26, 30, 18, PF_NORMAL),
        (26, 30, 14, PF_NORMAL),
        (22, 24, 13, PF_NORMAL),
        (18, 20, 12, PF_NORMAL),
        (20, 23, 10, PF_NORMAL),
        (0, 31, 23, PF_NORMAL),
    ],
    'ladders': [
        (17, 4, 7, LF_NORMAL),
        (4, 11, 16, LF_NORMAL),
        (2, 16, 20, LF_NORMAL),
        (10, 11, 19, LF_NORMAL),
        (12, 11, 19, LF_NORMAL),
        (29, 14, 18, LF_NORMAL),
        (21, 7, 10, LF_NORMAL),
    ],
    'items': [
        (2, 10, T_ITEM_UMB),
        (11, 10, T_ITEM_HAT),
        (28, 13, T_ITEM_PURSE),
    ],
}

STAGE_REMIX_8 = {
    'ltype': LT_RIVETS,
    'gfxbank': 7,
    'bgm': TRK_STAGE4,
    'height_idx': 3,
    'mario': (15, 22),
    'dk': (15, 7),
    'pauline': (15, 4),
    'barrel_int': 110,
    'max_fires': 5,
    'bonus': (0x80, 0x00),
    'plats': [
        (12, 19, 4, PF_NORMAL),
        (3, 28, 7, PF_NORMAL),
        (2, 14, 11, PF_NORMAL),
        (17, 29, 11, PF_NORMAL),
        (2, 29, 15, PF_NORMAL),
        (1, 14, 19, PF_NORMAL),
        (17, 30, 19, PF_NORMAL),
        (0, 31, 22, PF_NORMAL),
    ],
    'ladders': [
        (4, 7, 11, LF_NORMAL),
        (13, 7, 11, LF_NORMAL),
        (18, 7, 11, LF_NORMAL),
        (27, 7, 11, LF_NORMAL),
        (3, 11, 15, LF_NORMAL),
        (11, 11, 15, LF_NORMAL),
        (20, 11, 15, LF_NORMAL),
        (28, 11, 15, LF_NORMAL),
        (2, 15, 19, LF_NORMAL),
        (12, 15, 19, LF_NORMAL),
        (19, 15, 19, LF_NORMAL),
        (29, 15, 19, LF_NORMAL),
        (3, 19, 22, LF_NORMAL),
        (13, 19, 22, LF_NORMAL),
        (18, 19, 22, LF_NORMAL),
        (28, 19, 22, LF_NORMAL),
    ],
    'rivets': [
        (8, 7), (23, 7),
        (8, 11), (23, 11),
        (8, 15), (23, 15),
        (8, 19), (23, 19),
    ],
    'items': [
        (15, 6, T_HAMMER),
        (15, 14, T_HAMMER),
        (2, 10, T_ITEM_HAT),
        (29, 10, T_ITEM_PURSE),
        (15, 21, T_ITEM_UMB),
    ],
}

STAGES = [
    ('STAGE_25M',     STAGE_25M),
    ('STAGE_50M',     STAGE_50M),
    ('STAGE_75M',     STAGE_75M),
    ('STAGE_100M',    STAGE_100M),
    ('STAGE_REMIX_1', STAGE_REMIX_1),
    ('STAGE_REMIX_2', STAGE_REMIX_2),
    ('STAGE_REMIX_3', STAGE_REMIX_3),
    ('STAGE_REMIX_4', STAGE_REMIX_4),
    ('STAGE_REMIX_5', STAGE_REMIX_5),
    ('STAGE_REMIX_6', STAGE_REMIX_6),
    ('STAGE_REMIX_7', STAGE_REMIX_7),
    ('STAGE_REMIX_8', STAGE_REMIX_8),
]


def emit_asm(path):
    sample = encode_level(STAGE_25M)
    l_size = len(sample)

    p_off = 20
    l_off = p_off + 1 + MAX_PLATS * 4
    r_off = l_off + 1 + MAX_LADDERS * 4
    i_off = r_off + 1 + MAX_RIVETS * 2
    assert i_off + 1 + MAX_ITEMS * 3 == l_size

    lines = [
        '; Generated by tools/levelgen.py - do not edit by hand',
        '',
        f'PF_NORMAL    equ {PF_NORMAL}',
        f'PF_CONV_R    equ {PF_CONV_R}',
        f'PF_CONV_L    equ {PF_CONV_L}',
        f'LF_NORMAL    equ {LF_NORMAL}',
        f'LF_BROKEN    equ {LF_BROKEN}',
        f'LF_DECOR     equ {LF_DECOR}',
        f'LF_TELESCOPE equ {LF_TELESCOPE}',
        f'MAX_PLATS    equ {MAX_PLATS}',
        f'MAX_LADDERS  equ {MAX_LADDERS}',
        f'MAX_RIVETS   equ {MAX_RIVETS}',
        f'MAX_ITEMS    equ {MAX_ITEMS}',
        '',
        'L_TYPE       equ 0',
        'L_GFXBANK    equ 1',
        'L_BGM        equ 2',
        'L_HEIGHT_IDX equ 3',
        'L_MARIOX     equ 4',
        'L_MARIOY     equ 5',
        'L_DKX        equ 6',
        'L_DKY        equ 7',
        'L_PAUXX      equ 8',
        'L_PAUYY      equ 9',
        'L_OILX       equ 10',
        'L_OILY       equ 11',
        'L_STACKX     equ 12',
        'L_STACKY     equ 13',
        'L_ELEVC0     equ 14',
        'L_ELEVC1     equ 15',
        'L_BARREL     equ 16',
        'L_MAX_FIRES  equ 17',
        'L_BONUS      equ 18',
        f'L_NPLAT      equ {p_off}',
        f'L_PLAT       equ {p_off + 1}',
        f'L_NLADDER    equ {l_off}',
        f'L_LADDERS    equ {l_off + 1}',
        f'L_NRIVET     equ {r_off}',
        f'L_RIVETS     equ {r_off + 1}',
        f'L_NITEMS     equ {i_off}',
        f'L_ITEMS      equ {i_off + 1}',
        f'L_SIZE       equ {l_size}',
        f'STAGE_COUNT  equ {len(STAGES)}',
        '',
        'STAGE_TABLE:',
    ]
    for name, _ in STAGES:
        lines.append(f'    DW {name}')
    lines.append('')

    lines.append('; Mode 0 (Default!): Complete 4-Stage Original Arcade (25m -> 50m Pie Factory -> 75m Elevators -> 100m Rivets)')
    lines.append('PROG_ORIG:  DB 0, 1, 2, 3, $FF')
    lines.append('')
    lines.append('; Mode 1: US Set-1 Tournament Progression (dkong.asm $3A65: L1=2, L2=3, L3=4, L4+=5 stages)')
    lines.append('PROG_US_L1: DB 0, 3, $FF')
    lines.append('PROG_US_L2: DB 0, 2, 3, $FF')
    lines.append('PROG_US_L3: DB 0, 1, 2, 3, $FF')
    lines.append('PROG_US_L4: DB 0, 1, 0, 2, 3, $FF')
    lines.append('PROG_US_L5: DB 0, 1, 0, 2, 3, $FF')
    lines.append('PROG_US_TABLE:')
    lines.append('    DW PROG_US_L1, PROG_US_L2, PROG_US_L3, PROG_US_L4, PROG_US_L5')
    lines.append('')
    lines.append('; Mode 2: 8-Stage Remix Tour')
    lines.append('PROG_REMIX: DB 4, 5, 6, 7, 8, 9, 10, 11, $FF')
    lines.append('')

    lines.append('; 4 Multi-Stage Attract Demo Replays (cycles 25m -> 50m -> 75m -> 100m)')
    lines.append('DEMO_STAGE_TABLE:')
    lines.append('    DB 0, 1, 2, 3')
    lines.append('DEMO_SCRIPT_TABLE:')
    lines.append('    DW DEMO_25M, DEMO_50M, DEMO_75M, DEMO_100M')
    lines.append('DEMO_25M:')
    lines.append('    DB 85, $08, 2, $18, 86, $08, 28, $01, 48, $04, 2, $14, 90, $04, 28, $01, 70, $08, 0, 0')
    lines.append('DEMO_50M:')
    lines.append('    DB 50, $08, 28, $01, 74, $08, 32, $01, 2, $14, 30, $04, 32, $01, 56, $04, 0, 0')
    lines.append('DEMO_75M:')
    lines.append('    DB 34, $01, 8, $08, 42, $01, 2, $18, 26, $08, 36, $00, 2, $18, 24, $08, 0, 0')
    lines.append('DEMO_100M:')
    lines.append('    DB 12, $04, 28, $01, 60, $08, 2, $18, 52, $08, 34, $01, 55, $04, 2, $14, 48, $04, 0, 0')
    lines.append('')

    for name, lv in STAGES:
        b = encode_level(lv)
        assert len(b) == l_size
        lines.append(f'{name}:')
        for i in range(0, len(b), 16):
            lines.append('    DB ' + ','.join('$%02X' % x for x in b[i:i + 16]))
        lines.append('')

    with open(path, 'w') as f:
        f.write('\n'.join(lines))
    print(f'wrote {path}: {len(STAGES)} stages, {l_size} bytes/stage ({len(STAGES) * l_size} bytes)')


if __name__ == '__main__':
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'levels.asm')
    emit_asm(out)
