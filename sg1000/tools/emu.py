#!/usr/bin/env python3
"""
Minimal Sega SG-1000 emulator (TMS9918A + SN76489 + Z80) used to test the
Donkey Kong port.  It is intended for headless development: it runs the ROM,
renders frames to PNG and can replay scripted controller input.

Requires:  pip install z80 pillow
"""
import argparse
import os
import sys

from z80 import Z80Machine
from PIL import Image

CYCLES_PER_FRAME = 59739          # 3.579545 MHz / 60 Hz
SCREEN_W, SCREEN_H = 256, 192

# SG-1000 TMS9918A palette (RGB 0-255)
PALETTE = [
    (0, 0, 0),          # 0 transparent
    (0, 0, 0),          # 1 black
    (33, 200, 66),      # 2 medium green
    (94, 220, 120),     # 3 light green
    (84, 85, 237),      # 4 dark blue
    (125, 118, 252),    # 5 light blue
    (212, 82, 77),      # 6 dark red
    (66, 235, 245),     # 7 cyan
    (252, 85, 84),      # 8 medium red
    (255, 121, 120),    # 9 light red
    (212, 193, 84),     # 10 dark yellow
    (230, 206, 128),    # 11 light yellow
    (33, 176, 59),      # 12 dark green
    (201, 91, 186),     # 13 magenta
    (204, 204, 204),    # 14 gray
    (255, 255, 255),    # 15 white
]


class VDP:
    def __init__(self):
        self.vram = bytearray(0x4000)
        self.reg = [0] * 8
        self.status = 0
        self.addr = 0
        self.code = 0
        self.buf = 0
        self.first = True
        self.mode = 0
        self.frame = 0

    def mode_text(self):
        return {0: 'graphics1', 1: 'text', 2: 'graphics2', 3: 'multicolor',
                4: 'sms'}.get(self.mode, 'mode%d' % self.mode)

    def write_control(self, d):
        if self.first:
            self.first = False
            self.addr = (self.addr & 0x3F00) | (d & 0xFF)
        else:
            self.first = True
            self.code = (d >> 6) & 3
            self.addr = ((d & 0x3F) << 8) | (self.addr & 0x00FF)
            if (d & 0xC0) == 0x80:
                reg = d & 0x0F
                if reg < 8:
                    self.reg[reg] = self.addr & 0xFF
                    if reg in (0, 1):
                        self.mode = self.calc_mode()

    def calc_mode(self):
        if self.reg[0] & 0x04:
            return 4
        if self.reg[1] & 0x10:
            return 1
        if self.reg[1] & 0x08:
            return 3
        if self.reg[0] & 0x02:
            return 2
        return 0

    def write_data(self, d):
        self.first = True
        self.buf = d
        if self.code == 3:
            pass                                # CRAM not used in TMS modes
        else:
            self.vram[self.addr & 0x3FFF] = d
        self.addr = (self.addr + 1) & 0x3FFF

    def read_data(self):
        self.first = True
        v = self.buf
        self.buf = self.vram[self.addr & 0x3FFF]
        self.addr = (self.addr + 1) & 0x3FFF
        return v

    def read_status(self):
        self.first = True
        v = self.status
        self.status = 0
        return v

    def set_vblank(self):
        self.status |= 0x80

    # ------------------------------------------------------------------
    def render(self):
        img = bytearray(SCREEN_W * SCREEN_H * 3)
        backdrop = self.reg[7] & 0x0F
        if backdrop == 0:
            backdrop = 1
        for i in range(SCREEN_W * SCREEN_H):
            img[i * 3:i * 3 + 3] = PALETTE[backdrop]
        if not (self.reg[1] & 0x40):
            return bytes(img)                   # display disabled

        if self.mode == 0:
            self._render_g1(img)
        elif self.mode == 2:
            self._render_g2(img)
        elif self.mode == 1:
            self._render_text(img)
        elif self.mode == 3:
            self._render_multi(img)
        self._render_sprites(img)
        return bytes(img)

    def _put(self, img, x, y, color):
        if 0 <= x < SCREEN_W and 0 <= y < SCREEN_H:
            o = (y * SCREEN_W + x) * 3
            img[o:o + 3] = PALETTE[color & 15]

    def _render_g1(self, img):
        nt = self.reg[2] << 10
        ct = self.reg[3] << 6
        pt = self.reg[4] << 11
        backdrop = self.reg[7] & 0x0F or 1
        for ty in range(24):
            row = ty << 5
            for tx in range(32):
                name = self.vram[nt + row + tx]
                c = self.vram[ct + (name >> 3)]
                fg = c >> 4 or backdrop
                bg = (c & 15) or backdrop
                x0 = tx << 3
                for dy in range(8):
                    py = (ty << 3) + dy
                    line = self.vram[(pt + (name << 3) + dy) & 0x3FFF]
                    for b in range(8):
                        self._put(img, x0 + b, py, fg if (line & (0x80 >> b)) else bg)

    def _render_g2(self, img):
        nt = self.reg[2] << 10
        ct = (self.reg[3] << 6) & 0x2000
        pt = (self.reg[4] << 11) & 0x2000
        region_mask = ((self.reg[4] & 0x03) << 8) | 0xFF
        color_mask = ((self.reg[3] & 0x7F) << 3) | 0x07
        backdrop = self.reg[7] & 0x0F or 1
        for ty in range(24):
            row = ty << 5
            region = (ty & 0x18) << 5
            for tx in range(32):
                name = self.vram[nt + row + tx] + region
                x0 = tx << 3
                pbase = pt + ((name & region_mask) << 3)
                cbase = ct + ((name & color_mask) << 3)
                for dy in range(8):
                    py = (ty << 3) + dy
                    line = self.vram[(pbase + dy) & 0x3FFF]
                    c = self.vram[(cbase + dy) & 0x3FFF]
                    fg = c >> 4 or backdrop
                    bg = (c & 15) or backdrop
                    for b in range(8):
                        self._put(img, x0 + b, py, fg if (line & (0x80 >> b)) else bg)

    def _render_text(self, img):
        nt = self.reg[2] << 10
        pt = self.reg[4] << 11
        fg = self.reg[7] >> 4 or 1
        bg = self.reg[7] & 15 or 1
        for ty in range(24):
            row = ty * 40
            for tx in range(40):
                name = self.vram[nt + row + tx]
                x0 = 8 + tx * 6
                for dy in range(8):
                    py = (ty << 3) + dy
                    line = self.vram[(pt + (name << 3) + dy) & 0x3FFF]
                    for b in range(6):
                        self._put(img, x0 + b, py, fg if (line & (0x80 >> b)) else bg)

    def _render_multi(self, img):
        nt = self.reg[2] << 10
        pt = (self.reg[4] << 11) & 0x2000
        backdrop = self.reg[7] & 0x0F or 1
        for ty in range(24):
            row = ty << 5
            for tx in range(32):
                name = self.vram[nt + row + tx]
                x0 = tx << 3
                for dy in range(8):
                    py = (ty << 3) + dy
                    off = pt + (name << 3) + ((ty & 3) << 1) + (1 if (dy & 4) else 0)
                    c = self.vram[off & 0x3FFF]
                    left = c >> 4 or backdrop
                    right = (c & 15) or backdrop
                    for b in range(4):
                        self._put(img, x0 + b, py, left)
                        self._put(img, x0 + 4 + b, py, right)

    def _render_sprites(self, img):
        size = 16 if (self.reg[1] & 0x02) else 8
        zoom = 1 if (self.reg[1] & 0x01) else 0
        draw_size = size * (2 if zoom else 1)
        sa = (self.reg[5] & 0x7F) << 7
        sp = (self.reg[6] & 0x07) << 11
        maxs = 31
        for s in range(32):
            if self.vram[sa + (s << 2)] == 0xD0:
                maxs = s - 1
                break
        # TMS9918A: max 4 sprites per scanline, lower sprite index has priority
        line_counts = [0] * SCREEN_H
        drawn = bytearray(SCREEN_W * SCREEN_H)
        for s in range(maxs + 1):
            o = sa + (s << 2)
            y = (self.vram[o] + 1) & 0xFF
            if y >= 0xE0:
                y -= 0x100
            if y >= SCREEN_H or (y + draw_size) <= 0:
                continue
            color = self.vram[o + 3] & 0x0F
            x = self.vram[o + 1] - (32 if (self.vram[o + 3] & 0x80) else 0)
            tile = self.vram[o + 2] & (0xFC if size == 16 else 0xFF)
            for ty in range(draw_size):
                py = y + ty
                if not (0 <= py < SCREEN_H):
                    continue
                if line_counts[py] >= 4:
                    continue
                line_counts[py] += 1
                if color == 0:
                    continue
                sy = ty >> (1 if zoom else 0)
                if size == 16:
                    base = sp + (tile << 3)
                    for half in range(2):
                        pat = self.vram[(base + half * 16 + sy) & 0x3FFF]
                        x0 = x + (half * 8 * (2 if zoom else 1))
                        for b in range(8):
                            if pat & (0x80 >> b):
                                for zx in range(2 if zoom else 1):
                                    px = x0 + b * (2 if zoom else 1) + zx
                                    if 0 <= px < SCREEN_W and not drawn[py * SCREEN_W + px]:
                                        drawn[py * SCREEN_W + px] = 1
                                        self._put(img, px, py, color)
                else:
                    pat = self.vram[(sp + (tile << 3) + (sy & 7)) & 0x3FFF]
                    for b in range(8):
                        if pat & (0x80 >> b):
                            for zx in range(2 if zoom else 1):
                                px = x + b * (2 if zoom else 1) + zx
                                if 0 <= px < SCREEN_W and not drawn[py * SCREEN_W + px]:
                                    drawn[py * SCREEN_W + px] = 1
                                    self._put(img, px, py, color)


class PSG:
    """Very small SN76489 model: keeps the latched register for inspection."""
    def __init__(self):
        self.reg = [0] * 8
        self.latch = 0

    def write(self, d):
        if d & 0x80:
            self.latch = (d >> 4) & 7
            self.reg[self.latch] = (self.reg[self.latch] & 0x3F0) | (d & 0x0F)
        else:
            self.reg[self.latch] = (self.reg[self.latch] & 0x00F) | ((d & 0x3F) << 4)


class SG1000:
    def __init__(self, rom, trace=False):
        self.rom = rom
        self.z80 = Z80Machine()
        self.vdp = VDP()
        self.psg = PSG()
        self.trace = trace
        self.frame_count = 0
        self.input_p1 = 0x3F      # bits: 0 up,1 down,2 left,3 right,4 btn1,5 btn2
        self.input_p2 = 0x3F
        self._load()

    def _load(self):
        m = self.z80.memory
        for i, b in enumerate(self.rom):
            m[i] = b
        # RAM is already zeroed; mirror handling is done in read/write hooks

    def _rd(self, addr):
        return self.z80.memory[addr & 0xFFFF]

    def _wr(self, addr, v):
        if addr >= 0xC000:
            self.z80.memory[0xC000 + (addr & 0x3FF)] = v

    def set_input(self, p1=None, p2=None):
        if p1 is not None:
            self.input_p1 = p1 & 0x3F
        if p2 is not None:
            self.input_p2 = p2 & 0x3F

    def _in(self, port):
        p = port & 0xFF
        if p == 0xDC:
            return (self.input_p1 & 0x3F) | ((self.input_p2 & 3) << 6)
        if p == 0xDD:
            return ((self.input_p2 >> 2) & 0x0F) | 0xF0
        if 0x80 <= p <= 0xBF:
            if p & 1:
                return self.vdp.read_status()
            return self.vdp.read_data()
        return 0xFF

    def _out(self, port, v):
        p = port & 0xFF
        if 0x40 <= p <= 0x7F:
            self.psg.write(v)
        elif 0x80 <= p <= 0xBF:
            if p & 1:
                self.vdp.write_control(v)
            else:
                self.vdp.write_data(v)

    def run_frame(self):
        z = self.z80
        z.set_input_callback(self._in)
        z.set_output_callback(self._out)
        z.set_read_callback(self._rd)
        z.set_write_callback(self._wr)
        # z.run() also stops at the library's internal end-of-frame event
        # (every 100000 ticks), so loop until the frame budget is consumed.
        budget = CYCLES_PER_FRAME
        while budget > 0:
            ft0 = z.frame_tick
            z.ticks_to_stop = budget
            z.run()
            ft1 = z.frame_tick
            if ft1 < ft0:
                used = (100000 - ft0) + ft1
            else:
                used = ft1 - ft0
            if used <= 0:
                break
            budget -= used
        self.vdp.set_vblank()
        self.frame_count += 1

    def screenshot(self):
        return self.vdp.render()


def load_input_script(path):
    """One line per frame: hex byte of active (pressed) P1 bits."""
    script = []
    if not path:
        return script
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            script.append(int(line, 16))
    return script


def main(argv=None):
    ap = argparse.ArgumentParser(description='SG-1000 test emulator')
    ap.add_argument('rom')
    ap.add_argument('--frames', type=int, default=60)
    ap.add_argument('--shot', default=None, help='write PNG screenshot after N frames')
    ap.add_argument('--shot-each', type=int, default=0, help='write a PNG every N frames')
    ap.add_argument('--input', default=None, help='scripted P1 input file')
    ap.add_argument('--outdir', default='.')
    ap.add_argument('--trace', action='store_true')
    ap.add_argument('--state', action='store_true', help='print CPU state at the end')
    args = ap.parse_args(argv)

    with open(args.rom, 'rb') as f:
        rom = f.read()
    emu = SG1000(rom, trace=args.trace)
    script = load_input_script(args.input)

    os.makedirs(args.outdir, exist_ok=True)
    for i in range(args.frames):
        if i < len(script):
            # script bits are active-high
            emu.set_input(p1=(~script[i]) & 0x3F)
        emu.run_frame()
        if args.shot_each and (i + 1) % args.shot_each == 0:
            img = Image.frombytes('RGB', (SCREEN_W, SCREEN_H), emu.screenshot())
            img.save(os.path.join(args.outdir, 'frame%04d.png' % (i + 1)))

    img = Image.frombytes('RGB', (SCREEN_W, SCREEN_H), emu.screenshot())
    if args.shot:
        img.save(args.shot)
    else:
        img.save(os.path.join(args.outdir, 'final.png'))
    if args.state:
        z = emu.z80
        print('PC=%04x SP=%04x AF=%04x BC=%04x DE=%04x HL=%04x IX=%04x IY=%04x' %
              (z.pc, z.sp, z.af, z.bc, z.de, z.hl, z.ix, z.iy))
        print('mode=%s vdpregs=%s' % (emu.vdp.mode_text(),
              ' '.join('%02x' % r for r in emu.vdp.reg)))
    print('ran %d frames' % args.frames)
    return 0


if __name__ == '__main__':
    sys.exit(main())
