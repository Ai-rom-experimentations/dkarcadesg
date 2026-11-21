#!/usr/bin/env python3
"""
Compile arcade Donkey Kong music patterns (from dkong-snd.asm $300-$4CB and
pitch table $600-$619) plus multi-frame SN76489 sound-effect envelopes into
src/snddata.asm for the Sega SG-1000 port.
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


# Build compact 64-entry period lookup table indexed by (octv << 4) | idx (0..63)
PERIOD_TABLE = []
for code in range(64):
    PERIOD_TABLE.append(note_byte_to_period(0x80 | code))


# Exact pattern bytes from dkong-snd.asm ($300-$4CB)
RAW_PATTERNS = {
    # Looping gameplay BGMs (no decay, crisp staccato articulation)
    'BGM_BARRELS': (True, False, [
        0x2A, 0x80, 0x1C, 0x84, 0x0E, 0x88, 0x8A, 0x88, 0x00
    ]),
    'BGM_PIEFACTORY': (True, False, [
        0x16, 0x84, 0x0B, 0x84, 0x84, 0x16, 0x86, 0x0B, 0x86, 0x84, 0x00
    ]),
    'BGM_ELEVATORS': (True, False, [
        0x14, 0x82, 0x0A, 0x85, 0x89, 0x14, 0x87, 0x0A, 0x85, 0x84, 0x00
    ]),
    'BGM_RIVETS': (True, False, [
        0x18, 0x84, 0x0C, 0x80, 0x80, 0x00
    ]),
    'BGM_HURRY': (True, False, [
        0x10, 0xB8, 0xB4, 0xB0, 0x00
    ]),
    'BGM_HAMMER': (True, False, [
        0x12, 0x90, 0x09, 0x90, 0x90, 0x12, 0x90, 0x90, 0x94, 0x90, 0x94, 0x90, 0x94,
        0x09, 0x94, 0x94, 0x12, 0x94, 0x94, 0x98, 0x94, 0x98, 0x94, 0x00
    ]),
    # Cutscenes & jingles from dkong-snd.asm
    'MUS_HOWHIGH': (False, True, [
        0x1B, 0xE2, 0x88, 0x09, 0xA4, 0x12, 0x82, 0xA8, 0x12, 0x88, 0xA4, 0xE2, 0x82, 0xA4,
        0x12, 0xE0, 0x80, 0x09, 0x82, 0x83, 0x86, 0x88, 0x8A, 0x8C, 0x24, 0xD0, 0x88, 0x00
    ]),
    'MUS_CLIMB': (False, False, [
        0x40, 0xCA, 0x82, 0x18, 0xCC, 0x84, 0x30, 0xD0, 0x86, 0xCA, 0x82,
        0x08, 0xDA, 0x89, 0xD9, 0x89, 0xDA, 0x89, 0xD9, 0x89,
        0xDA, 0x89, 0xD9, 0x89, 0xDA, 0x89, 0xD9, 0x89,
        0x40, 0xDA, 0x8A, 0x00
    ]),
    'MUS_STAGE_CLEAR': (False, True, [
        0x0A, 0xE8, 0xA4, 0xEA, 0xA6, 0x14, 0xEC, 0xA8, 0x28, 0xE8, 0xA4,
        0x0A, 0xE8, 0xA4, 0xEA, 0xA6, 0x14, 0xEC, 0xA8, 0x28, 0xE8, 0xA4, 0x00
    ]),
    'MUS_VICTORY_ODD': (False, True, [
        0x20, 0x80, 0xDC, 0x98, 0xE0, 0x9A, 0xE2, 0x9C, 0x20, 0x90, 0xE4, 0x88,
        0x10, 0xE3, 0x90, 0xA4, 0x20, 0x88, 0xDA, 0x8A, 0xEA, 0x84, 0x10, 0xE8, 0x8A, 0xA4,
        0x20, 0x84, 0xE2, 0x82, 0xE2, 0x87, 0x16, 0xE8, 0x88, 0x0A, 0xA3,
        0x10, 0xE4, 0x82, 0xA0, 0x15, 0xC8, 0x80, 0x2B, 0xCA, 0x83, 0x40, 0xCB, 0x80, 0x00
    ]),
    'MUS_VICTORY_EVEN': (False, True, [
        0x10, 0xE8, 0xA4, 0xE8, 0xA4, 0xE6, 0xA2, 0xE6, 0xA2, 0xE4, 0xA0, 0xE4, 0xA0,
        0xE2, 0x9C, 0xE2, 0x9C, 0x20, 0xE0, 0x90, 0x10, 0x88, 0x08, 0xA0, 0xA2,
        0x20, 0xE4, 0x90, 0xE0, 0x88, 0x20, 0xE2, 0x92, 0x10, 0x8A, 0x08, 0xA2, 0xA4,
        0x20, 0xE6, 0x92, 0xE2, 0x8A, 0x20, 0xE8, 0x88, 0x10, 0x82, 0xA8, 0xEA, 0x88,
        0xA8, 0xE6, 0x82, 0xA4, 0xE8, 0x80, 0x2B, 0x83, 0x40, 0x80, 0x00
    ]),
    'MUS_DK_FALL_INTRO': (False, True, [
        0x0A, 0xE0, 0x98, 0xE0, 0x98, 0x3C, 0xE0, 0x98,
        0x12, 0x88, 0x84, 0x88, 0x84, 0x88, 0x84, 0x88, 0x84, 0x00
    ]),
    'MUS_DEATH_TAIL': (False, False, [
        0x0E, 0xA4, 0x1C, 0xE8, 0x90, 0xD8, 0x88, 0x38, 0xE0, 0x80, 0x00
    ]),
    # Nintendo's two hidden cutscene songs from the original sound ROM!
    'MUS_ATTRACT': (True, True, [
        0x24, 0x88, 0x82, 0x88, 0x82, 0x12, 0xD8, 0x88, 0xD6, 0x88, 0xD8, 0x82, 0xD6, 0x82,
        0xD6, 0x88, 0x88, 0xD6, 0x82, 0x82, 0x24, 0xDA, 0x87, 0xD9, 0x83, 0xDA, 0x87, 0xD7,
        0x83, 0x09, 0xD8, 0x88, 0xD7, 0x88, 0xD8, 0x88, 0xD7, 0x88, 0xD8, 0x82, 0xD7, 0x82,
        0xD8, 0x82, 0xD7, 0x82, 0x48, 0xD8, 0x88, 0x00
    ]),
    'MUS_NAMEENTRY': (True, True, [
        0x20, 0xE8, 0x88, 0x82, 0xE2, 0x88, 0x10, 0x82, 0xA4, 0x20, 0xDC, 0x88, 0x82, 0x84,
        0x18, 0xE0, 0x87, 0x08, 0xA2, 0x20, 0xE4, 0x88, 0xE7, 0x82, 0xE8, 0x88, 0xEA, 0x82,
        0x20, 0xEA, 0x88, 0xEC, 0x82, 0x88, 0x82, 0xEC, 0x88, 0x82, 0xF0, 0x90, 0x88, 0xEC,
        0x88, 0x82, 0x10, 0x84, 0xAA, 0xE8, 0x8C, 0xAA, 0x20, 0xE7, 0x92, 0x8A, 0x10, 0x84,
        0xA4, 0xE2, 0x8C, 0xA4, 0x00
    ]),
}


def decode_arcade_pattern(loop_flag, decay_flag, raw):
    """
    Convert arcade pattern bytes into compact 3-byte event triples:
      DB frames, ch0_note (0=rest, else 1..64 -> PERIOD_TABLE[n-1]), ch1_note
    Terminated by:
      DB $FE (loop to start) or DB $FF (stop)
    Header byte before events:
      DB decay_flag (1 = envelope decay, 0 = sustain with 2-frame staccato gap)
    """
    out = [1 if decay_flag else 0]
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
        # Note for ch A
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
        # Arcade timer runs ~97.6 Hz -> * 60 / 97.6 ~= * 0.62
        frames = max(3, int(round(cur_dur * 0.62)))
        out.extend([frames, ch_a, ch_b])
    out.append(0xFE if loop_flag else 0xFF)
    return out


# Multi-frame SFX format (played on Tone Ch2 + Noise Ch3):
# Repeated steps of:
#   DB frames, vol2|(vol3<<4), period_lo, period_hi|noise_ctrl_flag
# Specifically, each step is 4 bytes:
#   byte 0: duration in frames (1..60), or $00 to end SFX
#   byte 1: ch2 attenuation (0..15, 15=silent)
#   byte 2: low byte of 10-bit ch2 period
#   byte 3: (high 2 bits of ch2 period) | (noise_atten << 4) | ((noise_mode & 3) << 2) | (noise_white << 7)
# Wait: even simpler & super clean 4-byte step:
#   byte 0: frames (0 = end; $FE = end & trigger MUS_DEATH_TAIL)
#   byte 1: ch2_vol (0..15; 15 = off) | (noise_vol << 4)  (note: 15 = silent for both!)
#   byte 2: ch2_period & $FF
#   byte 3: ((ch2_period >> 8) & 3) | ((noise_ctrl & 7) << 2) | ($80 if set_noise_ctrl else 0)
def sfx_step(frames, hz2=0, vol2=15, noise_ctrl=None, vol_noise=15):
    p = hz_to_period(hz2) if hz2 > 0 else 0
    if hz2 <= 0:
        vol2 = 15
    b1 = (vol2 & 0x0F) | ((vol_noise & 0x0F) << 4)
    b2 = p & 0xFF
    b3 = (p >> 8) & 0x03
    if noise_ctrl is not None:
        b3 |= ((noise_ctrl & 0x07) << 2) | 0x80
    return [frames, b1, b2, b3]


SFX_LIST = {
    # Classic rising-arcing Mario jump boing
    'SFX_JUMP': (
        sfx_step(2, 260, 1) +
        sfx_step(2, 330, 1) +
        sfx_step(2, 420, 1) +
        sfx_step(3, 520, 2) +
        sfx_step(3, 600, 2) +
        sfx_step(3, 540, 4) +
        sfx_step(3, 460, 7) +
        [0]
    ),
    # Crisp subtle walking footsteps
    'SFX_STEP1': (
        sfx_step(2, 190, 7, noise_ctrl=0x04, vol_noise=10) +
        [0]
    ),
    'SFX_STEP2': (
        sfx_step(2, 230, 7, noise_ctrl=0x04, vol_noise=10) +
        [0]
    ),
    # Ladder climb rung tick
    'SFX_CLIMB': (
        sfx_step(2, 350, 6) +
        sfx_step(1, 260, 9) +
        [0]
    ),
    # Arcade Pattern $08: "Scored Points" 6-note chime (09 B0 B2 B4 12 BA B6)
    'SFX_SCORE': (
        sfx_step(4, 919, 1) +
        sfx_step(4, 1032, 1) +
        sfx_step(4, 1158, 1) +
        sfx_step(7, 1546, 1) +
        sfx_step(9, 1227, 2) +
        sfx_step(5, 1227, 6) +
        [0]
    ),
    # Hammer barrel/fireball smash: heavy white-noise crunch + bass impact
    'SFX_SMASH': (
        sfx_step(3, 140, 0, noise_ctrl=0x06, vol_noise=0) +
        sfx_step(3, 115, 1, noise_ctrl=0x05, vol_noise=1) +
        sfx_step(4, 180, 2, noise_ctrl=0x06, vol_noise=2) +
        sfx_step(5, 120, 4, noise_ctrl=0x06, vol_noise=4) +
        sfx_step(5, 0, 15, noise_ctrl=0x06, vol_noise=8) +
        [0]
    ),
    # Bonus item pickup sparkle
    'SFX_ITEM': (
        sfx_step(3, 587, 1) +
        sfx_step(3, 784, 1) +
        sfx_step(3, 988, 1) +
        sfx_step(4, 1175, 1) +
        sfx_step(6, 1568, 2) +
        sfx_step(4, 1568, 6) +
        [0]
    ),
    # Rivet pulled out metallic pop
    'SFX_RIVET': (
        sfx_step(3, 523, 1) +
        sfx_step(3, 659, 1) +
        sfx_step(3, 784, 1) +
        sfx_step(6, 1046, 1) +
        sfx_step(4, 1046, 5) +
        [0]
    ),
    # Spring bounce & heavy shaft drop crash (75m)
    'SFX_SPRING': (
        sfx_step(2, 220, 2) +
        sfx_step(2, 340, 2) +
        sfx_step(3, 510, 3) +
        sfx_step(3, 380, 5) +
        [0]
    ),
    'SFX_SPRING_DROP': (
        sfx_step(3, 480, 3) +
        sfx_step(3, 340, 3) +
        sfx_step(3, 220, 3) +
        sfx_step(5, 120, 2, noise_ctrl=0x06, vol_noise=2) +
        [0]
    ),
    # Barrel release / oil ignite
    'SFX_THROW': (
        sfx_step(2, 180, 4, noise_ctrl=0x05, vol_noise=6) +
        sfx_step(3, 140, 6) +
        [0]
    ),
    # Kong roar / chest pound
    'SFX_ROAR': (
        sfx_step(6, 125, 1, noise_ctrl=0x06, vol_noise=1) +
        sfx_step(4, 0, 15) +
        sfx_step(6, 118, 1, noise_ctrl=0x06, vol_noise=1) +
        sfx_step(4, 0, 15) +
        sfx_step(10, 112, 1, noise_ctrl=0x06, vol_noise=1) +
        [0]
    ),
    # Bonus countdown tick
    'SFX_TICK': (
        sfx_step(2, 1100, 3) +
        [0]
    ),
    # Extra life 1-UP fanfare
    'SFX_1UP': (
        sfx_step(4, 659, 1) +
        sfx_step(4, 784, 1) +
        sfx_step(4, 1319, 1) +
        sfx_step(4, 1047, 1) +
        sfx_step(4, 1175, 1) +
        sfx_step(10, 1568, 1) +
        sfx_step(5, 1568, 6) +
        [0]
    ),
    # Pause chime
    'SFX_PAUSE': (
        sfx_step(4, 880, 2) +
        sfx_step(4, 660, 2) +
        sfx_step(6, 1320, 2) +
        [0]
    ),
    # Arcade death descending whirl ($003-$044) -> triggers MUS_DEATH_TAIL ($FE)
    'SFX_DIE': (
        sfx_step(3, 880, 1) +
        sfx_step(3, 830, 1) +
        sfx_step(3, 784, 1) +
        sfx_step(3, 740, 1) +
        sfx_step(3, 698, 1) +
        sfx_step(3, 659, 1) +
        sfx_step(3, 622, 1) +
        sfx_step(3, 587, 1) +
        sfx_step(3, 523, 1) +
        sfx_step(3, 466, 1) +
        sfx_step(4, 415, 2) +
        sfx_step(4, 370, 2) +
        sfx_step(6, 0, 15) +
        [0xFE]
    ),
}


def emit(path):
    lines = ['; Generated by tools/sndgen.py from dkong-snd.asm - do not edit by hand', '']
    lines.append('ARCADE_PERIOD_TABLE:')
    for i in range(0, 64, 8):
        lines.append('    DW ' + ', '.join(str(v) for v in PERIOD_TABLE[i:i + 8]))
    lines.append('')

    track_names = list(RAW_PATTERNS.keys())
    for idx, name in enumerate(track_names):
        lines.append(f'TRK_{name} equ {idx}')
    lines.append('TRK_NONE equ $FF')
    lines.append('')

    lines.append('MUSIC_TRACK_TABLE:')
    for name in track_names:
        lines.append(f'    DW {name}_DATA')
    lines.append('')

    total_bytes = 128 + len(track_names) * 2
    for name in track_names:
        loop_f, decay_f, raw = RAW_PATTERNS[name]
        data = decode_arcade_pattern(loop_f, decay_f, raw)
        total_bytes += len(data)
        lines.append(f'{name}_DATA:')
        for i in range(0, len(data), 16):
            lines.append('    DB ' + ','.join('$%02X' % b for b in data[i:i + 16]))
        lines.append('')

    for name, data in SFX_LIST.items():
        total_bytes += len(data)
        lines.append(f'{name}_DATA:')
        for i in range(0, len(data), 16):
            lines.append('    DB ' + ','.join('$%02X' % b for b in data[i:i + 16]))
        lines.append('')

    with open(path, 'w') as f:
        f.write('\n'.join(lines))
    print(f'wrote {path}: {len(track_names)} tracks, {len(SFX_LIST)} sfx ({total_bytes} bytes)')


if __name__ == '__main__':
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'snddata.asm')
    emit(out)
