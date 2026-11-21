#!/usr/bin/env python3
"""
Compile authentic 1981 Donkey Kong music patterns and i8035 sound-MCU
mathematical SFX routines (directly from dkong-snd.asm) into src/snddata.asm
for the Sega SG-1000 SN76489AN PSG.

Key hardware-accurate & SG-1000-advantaged techniques:
  - Exact i8035 $600-$619 12-note pitch table & $65D octave shifter
  - Mode 2 (Plucked BGM Bass, dkong-snd.asm $54C-$57B): 5-frame punchy note
    gate + $13F upward pitch-scoop attack + crisp silence between beats
  - Mode 1 (RC-Decay Cutscenes, dkong-snd.asm $15E-$17F): $13F attack chirp +
    exponential RC envelope + subtle 1-LSB warm vibrato shimmer
  - Exact i8035 register-level simulations for:
      * Mario Death ($003-$03A alternating-fifths chromatic spin -> Pattern $09)
      * Hammer Smash ($0C6-$0EE ascending geometric-fifths fanfare + noise crack)
      * Jack-Spring Boing ($0A8-$0C4 x1.25 dual-wrap sweep)
      * Kong / Spring Fall ($5BA-$5E3 descending sweep)
      * Scored Points (Pattern $08: 09 B0 B2 B4 12 BA B6)
  - SN76489 Tone-2-Clocked Periodic Noise ($E3 / f_tone2 / 16) sub-octave
    synthesis for Kong's 3-Part Gorilla Roar (FE 85 FE 85 FE, $518-$51C)
"""
import os

# Original arcade i8035 frequency table ($600-$619, 13 entries; index 5 is rest)
ARCADE_FREQ_RAW = [
    0x2800, 0x2A61, 0x2CE6, 0x2F91, 0x3266, 0xFFFF,
    0x3565, 0x3892, 0x3BEF, 0x3F75, 0x4346, 0x4746, 0x4B83,
]


def note_byte_to_period(note_byte):
    """Decode arcade note byte ($80-$FF) into SN76489 10-bit period (0 = rest)."""
    idx = note_byte & 0x0F
    octv = (note_byte >> 4) & 0x03
    if idx >= len(ARCADE_FREQ_RAW):
        return 0
    raw = ARCADE_FREQ_RAW[idx]
    if raw == 0xFFFF or raw == 0:
        return 0
    val = raw >> (4 - octv)
    hz = val / 5.5704
    period = int(round(3579545.0 / (32.0 * hz)))
    return max(1, min(1023, period))


def hz_to_period(hz):
    if hz <= 0:
        return 0
    return max(1, min(1023, int(round(3579545.0 / (32.0 * hz)))))


PERIOD_TABLE = [note_byte_to_period(0x80 | code) for code in range(64)]


# Envelope modes:
#   0 = non-decay legato/staccato (MUS_CLIMB, MUS_DEATH_TAIL)
#   1 = $15E-$17F attack chirp + RC decay + warm vibrato (Cutscenes)
#   2 = $54C-$57B 5-frame plucked bass + $13F upward pitch scoop (Gameplay BGMs)
ENV_SUSTAIN = 0
ENV_DECAY   = 1
ENV_PLUCK   = 2

# Exact pattern bytes from dkong-snd.asm ($300-$4CB)
RAW_PATTERNS = {
    # Pattern $01 ($301): 25m Barrels BGM
    'BGM_BARRELS': (True, ENV_PLUCK, [
        0x2A, 0x80, 0x1C, 0x84, 0x0E, 0x88, 0x8A, 0x88, 0x00
    ]),
    # Pattern $02 ($30A): 50m Pie Factory BGM (exact 6-byte ROM pattern!)
    'BGM_PIEFACTORY': (True, ENV_PLUCK, [
        0x16, 0x84, 0x0B, 0x84, 0x84, 0x00
    ]),
    # Bonus Lab Synth for 75m (Note: actual Stage 3 uses TRK_NONE per $50A=$00!)
    'BGM_ELEVATORS': (True, ENV_PLUCK, [
        0x14, 0x82, 0x0A, 0x85, 0x89, 0x14, 0x87, 0x0A, 0x85, 0x84, 0x00
    ]),
    # Pattern $04 ($311): 100m Rivets BGM
    'BGM_RIVETS': (True, ENV_PLUCK, [
        0x18, 0x84, 0x0C, 0x80, 0x80, 0x00
    ]),
    # Pattern $05 ($317): Running Out of Time!
    'BGM_HURRY': (True, ENV_PLUCK, [
        0x10, 0xB8, 0xB4, 0xB0, 0x00
    ]),
    # Pattern $06 ($31C): Hammer Time!
    'BGM_HAMMER': (True, ENV_PLUCK, [
        0x12, 0x90, 0x09, 0x90, 0x90, 0x12, 0x90, 0x90, 0x94, 0x90, 0x94, 0x90, 0x94,
        0x09, 0x94, 0x94, 0x12, 0x94, 0x94, 0x98, 0x94, 0x98, 0x94, 0x00
    ]),
    # Pattern $10 ($3EB): How High Can You Get?
    'MUS_HOWHIGH': (False, ENV_DECAY, [
        0x1B, 0xE2, 0x88, 0x09, 0xA4, 0x12, 0x82, 0xA8, 0x12, 0x88, 0xA4, 0xE2, 0x82, 0xA4,
        0x12, 0xE0, 0x80, 0x09, 0x82, 0x83, 0x86, 0x88, 0x8A, 0x8C, 0x24, 0xD0, 0x88, 0x00
    ]),
    # Pattern $0A ($348): DK Climbing Ladders (Opening Cutscene)
    'MUS_CLIMB': (False, ENV_SUSTAIN, [
        0x40, 0xCA, 0x82, 0x18, 0xCC, 0x84, 0x30, 0xD0, 0x86, 0xCA, 0x82,
        0x08, 0xDA, 0x89, 0xD9, 0x89, 0xDA, 0x89, 0xD9, 0x89,
        0xDA, 0x89, 0xD9, 0x89, 0xDA, 0x89, 0xD9, 0x89,
        0x40, 0xDA, 0x8A, 0x00
    ]),
    # Pattern $14 ($49F): Completed Non-Rivet Stage
    'MUS_STAGE_CLEAR': (False, ENV_DECAY, [
        0x0A, 0xE8, 0xA4, 0xEA, 0xA6, 0x14, 0xEC, 0xA8, 0x28, 0xE8, 0xA4,
        0x0A, 0xE8, 0xA4, 0xEA, 0xA6, 0x14, 0xEC, 0xA8, 0x28, 0xE8, 0xA4, 0x00
    ]),
    # Pattern $11 ($407): Rescued Pauline (Odd Loop)
    'MUS_VICTORY_ODD': (False, ENV_DECAY, [
        0x20, 0x80, 0xDC, 0x98, 0xE0, 0x9A, 0xE2, 0x9C, 0x20, 0x90, 0xE4, 0x88,
        0x10, 0xE3, 0x90, 0xA4, 0x20, 0x88, 0xDA, 0x8A, 0xEA, 0x84, 0x10, 0xE8, 0x8A, 0xA4,
        0x20, 0x84, 0xE2, 0x82, 0xE2, 0x87, 0x16, 0xE8, 0x88, 0x0A, 0xA3,
        0x10, 0xE4, 0x82, 0xA0, 0x15, 0xC8, 0x80, 0x2B, 0xCA, 0x83, 0x40, 0xCB, 0x80, 0x00
    ]),
    # Pattern $13 ($461): Rescued Pauline (Even Loop)
    'MUS_VICTORY_EVEN': (False, ENV_DECAY, [
        0x10, 0xE8, 0xA4, 0xE8, 0xA4, 0xE6, 0xA2, 0xE6, 0xA2, 0xE4, 0xA0, 0xE4, 0xA0,
        0xE2, 0x9C, 0xE2, 0x9C, 0x20, 0xE0, 0x90, 0x10, 0x88, 0x08, 0xA0, 0xA2,
        0x20, 0xE4, 0x90, 0xE0, 0x88, 0x20, 0xE2, 0x92, 0x10, 0x8A, 0x08, 0xA2, 0xA4,
        0x20, 0xE6, 0x92, 0xE2, 0x8A, 0x20, 0xE8, 0x88, 0x10, 0x82, 0xA8, 0xEA, 0x88,
        0xA8, 0xE6, 0x82, 0xA4, 0xE8, 0x80, 0x2B, 0x83, 0x40, 0x80, 0x00
    ]),
    # Pattern $15 ($4B6): DK Is About to Fall (100m Collapse)
    'MUS_DK_FALL_INTRO': (False, ENV_DECAY, [
        0x0A, 0xE0, 0x98, 0xE0, 0x98, 0x3C, 0xE0, 0x98,
        0x12, 0x88, 0x84, 0x88, 0x84, 0x88, 0x84, 0x88, 0x84, 0x00
    ]),
    # Pattern $09 ($33D): Melodic Tail of Death Music
    'MUS_DEATH_TAIL': (False, ENV_SUSTAIN, [
        0x0E, 0xA4, 0x1C, 0xE8, 0x90, 0xD8, 0x88, 0x38, 0xE0, 0x80, 0x00
    ]),
    # Pattern $0C ($37A): Nintendo's Hidden Mischievous Cutscene Music
    'MUS_ATTRACT': (True, ENV_DECAY, [
        0x24, 0x88, 0x82, 0x88, 0x82, 0x12, 0xD8, 0x88, 0xD6, 0x88, 0xD8, 0x82, 0xD6, 0x82,
        0xD6, 0x88, 0x88, 0xD6, 0x82, 0x82, 0x24, 0xDA, 0x87, 0xD9, 0x83, 0xDA, 0x87, 0xD7,
        0x83, 0x09, 0xD8, 0x88, 0xD7, 0x88, 0xD8, 0x88, 0xD7, 0x88, 0xD8, 0x82, 0xD7, 0x82,
        0xD8, 0x82, 0xD7, 0x82, 0x48, 0xD8, 0x88, 0x00
    ]),
    # Pattern $0F ($3AE): Nintendo's Hidden Happy Cutscene Music
    'MUS_NAMEENTRY': (True, ENV_DECAY, [
        0x20, 0xE8, 0x88, 0x82, 0xE2, 0x88, 0x10, 0x82, 0xA4, 0x20, 0xDC, 0x88, 0x82, 0x84,
        0x18, 0xE0, 0x87, 0x08, 0xA2, 0x20, 0xE4, 0x88, 0xE7, 0x82, 0xE8, 0x88, 0xEA, 0x82,
        0x20, 0xEA, 0x88, 0xEC, 0x82, 0x88, 0x82, 0xEC, 0x88, 0x82, 0xF0, 0x90, 0x88, 0xEC,
        0x88, 0x82, 0x10, 0x84, 0xAA, 0xE8, 0x8C, 0xAA, 0x20, 0xE7, 0x92, 0x8A, 0x10, 0x84,
        0xA4, 0xE2, 0x8C, 0xA4, 0x00
    ]),
}


def decode_arcade_pattern(loop_flag, env_mode, raw):
    out = [env_mode]
    i = 0
    cur_dur = 16
    while i < len(raw):
        b = raw[i]
        i += 1
        if b == 0x00:
            break
        if (b & 0x80) == 0:
            cur_dur = b
            continue
        ch_a = (b & 0x3F) + 1
        if PERIOD_TABLE[ch_a - 1] == 0:
            ch_a = 0
        ch_b = 0
        if b & 0x40:
            nb = raw[i]
            i += 1
            ch_b = (nb & 0x3F) + 1
            if PERIOD_TABLE[ch_b - 1] == 0:
                ch_b = 0
        frames = max(3, int(round(cur_dur * 0.62)))
        out.extend([frames, ch_a, ch_b])
    out.append(0xFE if loop_flag else 0xFF)
    return out


def sfx_step(frames, hz2=0, vol2=15, noise_ctrl=None, vol_noise=15):
    p = hz_to_period(hz2) if hz2 > 0 else 0
    if hz2 <= 0:
        vol2 = 15
    b1 = (vol2 & 0x0F) | ((vol_noise & 0x0F) << 4)
    b2 = p & 0xFF
    b3 = ((p >> 8) & 0x03)
    if noise_ctrl is not None:
        b3 |= ((noise_ctrl & 0x07) << 2) | 0x80
    return [frames, b1, b2, b3]


def sfx_step_period(frames, period2=0, vol2=15, noise_ctrl=None, vol_noise=15):
    p = max(1, min(1023, period2)) if period2 > 0 else 0
    b1 = (vol2 & 0x0F) | ((vol_noise & 0x0F) << 4)
    b2 = p & 0xFF
    b3 = ((p >> 8) & 0x03)
    if noise_ctrl is not None:
        b3 |= ((noise_ctrl & 0x07) << 2) | 0x80
    return [frames, b1, b2, b3]


def gen_i8035_death_sfx():
    """Exact register simulation of dkong-snd.asm $009-$03A + $100 + $123."""
    steps = []
    r2 = 0x40
    # Loop 1 (2 iterations)
    for _ in range(2):
        r2 = (r2 + ((r2 >> 2) & 0x3F)) & 0xFF
        r3 = r2
        steps += sfx_step(2, (r3 * 64) / 5.5704, 1) + sfx_step(1, 0, 15)
        r3 = (r3 + (r3 >> 1)) & 0xFF
        steps += sfx_step(2, (r3 * 64) / 5.5704, 1) + sfx_step(1, 0, 15)
    # Loop 2 (while r2 >= $28, sampled every 2nd pair so total death fits 96f)
    k = 0
    while True:
        sub = ((r2 >> 4) & 0x0F)
        r2 = (r2 - sub - 1) & 0xFF
        if r2 < 0x28:
            break
        k += 1
        if k % 2 == 1:
            r3 = r2
            steps += sfx_step(2, (r3 * 64) / 5.5704, 1) + sfx_step(1, 0, 15)
            r3 = (r3 + (r3 >> 1)) & 0xFF
            steps += sfx_step(2, (r3 * 64) / 5.5704, 2) + sfx_step(1, 0, 15)
    steps.append(0xFE)  # chain into TRK_MUS_DEATH_TAIL (Pattern $09)!
    return steps


def gen_i8035_smash_sfx():
    """Exact register simulation of dkong-snd.asm $0C6-$0EE + $131 + noise snap."""
    steps = []
    r2 = 0x08
    first = True
    while True:
        r3 = r2
        hz_lo = (r3 * 64) / 5.5704
        if first:
            steps += sfx_step(2, hz_lo, 0, noise_ctrl=0x06, vol_noise=0)
            first = False
        else:
            steps += sfx_step(1, hz_lo, 1)
        if r2 + (r2 >> 1) >= 256:
            break
        r3_hi = r2 + (r2 >> 1)
        hz_hi = (r3_hi * 64) / 5.5704
        steps += sfx_step(2, hz_hi, 1, noise_ctrl=0x06, vol_noise=5 if r2 < 20 else 15)
        steps += sfx_step(1, hz_lo, 2)
        r2 = (r2 + (r2 >> 2)) & 0xFF
        if r2 >= 96:
            break
    steps.append(0)
    return steps


def gen_i8035_spring_sfx():
    """Exact register simulation of dkong-snd.asm $0A8-$0C4 + $115."""
    steps = []
    r3 = 0x20
    for pass_idx in range(2):
        while True:
            hz = max(115.0, (r3 * 32) / 5.5704)
            steps += sfx_step(1, hz, 2 if pass_idx == 0 else 4)
            nxt = r3 + ((r3 >> 2) & 0x3F)
            r3 = nxt & 0xFF
            if nxt >= 256:
                break
    steps.append(0)
    return steps


def gen_i8035_fall_sfx():
    """Exact descending fall from dkong-snd.asm $5BA-$5E3 + metallic crash."""
    steps = []
    r3 = 0xF0
    k = 0
    while r3 >= 0x24:
        dec = ((r3 >> 2) & 0x03) or 1
        r3 -= dec * 3
        k += 1
        if k % 2 == 1 and r3 > 0x20:
            hz = max(115.0, (r3 * 32) / 5.5704)
            steps += sfx_step(1, hz, 2)
    # Heavy girder crash at bottom of shaft!
    steps += sfx_step(4, 120, 1, noise_ctrl=0x07, vol_noise=0)
    steps += sfx_step(5, 110, 4, noise_ctrl=0x06, vol_noise=3)
    steps += sfx_step(5, 0, 15, noise_ctrl=0x06, vol_noise=8)
    steps.append(0)
    return steps


def gen_gorilla_roar_sfx():
    """
    SN76489 Hardware Advantage: Noise mode $03 = Periodic Noise clocked by
    Tone 2 (f_out = f_tone2 / 16 -> ~28..45 Hz chest-rattling gorilla growl!)
    alternated with White Noise ($07) breath rasp for 3 distinct roars,
    matching dkong-snd.asm $518-$51C & $52D-$531 (FE 85 FE 85 FE)!
    """
    steps = []
    for roar_i in range(3):
        base_p = 540 + roar_i * 40
        steps += sfx_step_period(3, base_p,      2, noise_ctrl=0x03, vol_noise=0)
        steps += sfx_step_period(4, base_p + 70, 2, noise_ctrl=0x07, vol_noise=1)
        steps += sfx_step_period(4, base_p + 130, 3, noise_ctrl=0x03, vol_noise=1)
        steps += sfx_step_period(3, base_p + 190, 6, noise_ctrl=0x07, vol_noise=4)
        if roar_i < 2:
            steps += sfx_step(4, 0, 15, noise_ctrl=0x03, vol_noise=15)
    steps.append(0)
    return steps


# Pattern $08 ($335): 09 B0 B2 B4 12 BA B6 00
def gen_score_chime_sfx():
    p_b0 = PERIOD_TABLE[0x30]
    p_b2 = PERIOD_TABLE[0x32]
    p_b4 = PERIOD_TABLE[0x34]
    p_ba = PERIOD_TABLE[0x3A]
    p_b6 = PERIOD_TABLE[0x36]
    return (
        sfx_step_period(5, p_b0, 1) +
        sfx_step_period(5, p_b2, 1) +
        sfx_step_period(5, p_b4, 1) +
        sfx_step_period(9, p_ba, 1) +
        sfx_step_period(7, p_b6, 1) +
        sfx_step_period(5, p_b6, 4) +
        sfx_step_period(4, p_b6, 8) +
        [0]
    )


SFX_LIST = {
    # Discrete analog Jumpman circuit: upward sweep + resonant crest + RC tail
    'SFX_JUMP': (
        sfx_step(2, 235, 1) +
        sfx_step(2, 315, 1) +
        sfx_step(2, 415, 1) +
        sfx_step(2, 525, 1) +
        sfx_step(3, 610, 2) +
        sfx_step(3, 575, 3) +
        sfx_step(3, 510, 5) +
        sfx_step(3, 440, 8) +
        [0]
    ),
    # Characteristic 1981 analog FM chirp footsteps (alternating A/B)
    'SFX_STEP1': (
        sfx_step(1, 240, 6) +
        sfx_step(1, 330, 5) +
        sfx_step(1, 195, 8) +
        [0]
    ),
    'SFX_STEP2': (
        sfx_step(1, 285, 6) +
        sfx_step(1, 390, 5) +
        sfx_step(1, 225, 8) +
        [0]
    ),
    # Crisp ladder-rung analog tick
    'SFX_CLIMB': (
        sfx_step(1, 380, 5) +
        sfx_step(1, 280, 7) +
        [0]
    ),
    # Exact Pattern $08 ($335) "Scored Points" 5-note chime
    'SFX_SCORE': gen_score_chime_sfx(),
    # Exact i8035 $0C6-$0EE Hammer Hit ascending-fifths fanfare + noise crack
    'SFX_SMASH': gen_i8035_smash_sfx(),
    # Bonus item pickup chime
    'SFX_ITEM': (
        sfx_step(3, 587, 1) +
        sfx_step(3, 784, 1) +
        sfx_step(3, 988, 1) +
        sfx_step(4, 1175, 1) +
        sfx_step(6, 1568, 2) +
        sfx_step(4, 1568, 6) +
        [0]
    ),
    # Rivet pulled ($50D / Pattern $08 variant)
    'SFX_RIVET': gen_score_chime_sfx(),
    # Exact i8035 $0A8-$0C4 Spring Boing
    'SFX_SPRING': gen_i8035_spring_sfx(),
    # Exact i8035 $5BA-$5E3 Spring / Kong Fall + Crash
    'SFX_SPRING_DROP': gen_i8035_fall_sfx(),
    # Barrel release / Oil drum ignition
    'SFX_THROW': (
        sfx_step(2, 185, 5, noise_ctrl=0x05, vol_noise=6) +
        sfx_step(2, 145, 7, noise_ctrl=0x06, vol_noise=9) +
        [0]
    ),
    # 3-Part Tone-2-Clocked Periodic-Noise Sub-Octave Gorilla Roar!
    'SFX_ROAR': gen_gorilla_roar_sfx(),
    # Menu / Bonus countdown tick
    'SFX_TICK': (
        sfx_step(1, 880, 4) +
        sfx_step(1, 1175, 7) +
        [0]
    ),
    # Extra life 7,000-pt fanfare
    'SFX_1UP': (
        sfx_step(4, 523, 1) +
        sfx_step(4, 659, 1) +
        sfx_step(4, 784, 1) +
        sfx_step(4, 1046, 1) +
        sfx_step(4, 784, 2) +
        sfx_step(8, 1046, 1) +
        sfx_step(6, 1046, 5) +
        [0]
    ),
    # Pause chime
    'SFX_PAUSE': (
        sfx_step(4, 659, 2) +
        sfx_step(4, 523, 2) +
        sfx_step(4, 659, 2) +
        sfx_step(6, 784, 3) +
        [0]
    ),
    # Exact i8035 $009-$03A Mario Death Spin -> chains into Pattern $09!
    'SFX_DIE': gen_i8035_death_sfx(),
}


def emit_asm(path):
    lines = [
        '; Generated by tools/sndgen.py from dkong-snd.asm - do not edit by hand',
        '',
        'ENV_SUSTAIN equ 0',
        'ENV_DECAY   equ 1',
        'ENV_PLUCK   equ 2',
        '',
        '; 64-entry SN76489 10-bit period table for arcade notes $80-$BF',
        'ARCADE_PERIOD_TABLE:',
    ]
    for row in range(0, 64, 8):
        vals = ', '.join('$%04X' % PERIOD_TABLE[row + k] for k in range(8))
        lines.append(f'    DW {vals}')
    lines.append('')

    track_names = list(RAW_PATTERNS.keys())
    for idx, name in enumerate(track_names):
        lines.append(f'TRK_{name} equ {idx}')
    lines.append('TRK_NONE equ $FF')
    lines.append('')

    lines.append('MUSIC_TRACK_TABLE:')
    for name in track_names:
        lines.append(f'    DW MUS_DATA_{name}')
    lines.append('')

    total_bytes = 128
    for name in track_names:
        loop_f, env_m, raw = RAW_PATTERNS[name]
        data = decode_arcade_pattern(loop_f, env_m, raw)
        total_bytes += len(data)
        lines.append(f'MUS_DATA_{name}:')
        for i in range(0, len(data), 16):
            chunk = ', '.join('$%02X' % x for x in data[i:i + 16])
            lines.append(f'    DB {chunk}')
    lines.append('')

    sfx_names = list(SFX_LIST.keys())
    for idx, name in enumerate(sfx_names):
        lines.append(f'{name}_ID equ {idx + 1}')
    lines.append('')
    lines.append('SFX_TABLE:')
    for name in sfx_names:
        lines.append(f'    DW {name}_DATA')
    lines.append('')

    for name in sfx_names:
        data = SFX_LIST[name]
        total_bytes += len(data)
        lines.append(f'{name}_DATA:')
        for i in range(0, len(data), 16):
            chunk = ', '.join('$%02X' % x for x in data[i:i + 16])
            lines.append(f'    DB {chunk}')
    lines.append('')

    with open(path, 'w') as f:
        f.write('\n'.join(lines))
    print(f'wrote {path} ({total_bytes} bytes of music/SFX tables)')


if __name__ == '__main__':
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'snddata.asm')
    emit_asm(out)
