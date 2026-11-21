#!/usr/bin/env python3
"""Render a screenshot PNG as ASCII art (any non-background pixel in a block)."""
import sys
from PIL import Image

CHARS = ' .:-=+*#%@'


def main(path):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    px = im.load()
    # background = most common colour
    from collections import Counter
    bg = Counter(im.getdata()).most_common(1)[0][0]
    for ty in range(h // 8):
        line = ''
        for tx in range(w // 8):
            best = 0
            for y in range(8):
                for x in range(8):
                    c = px[tx * 8 + x, ty * 8 + y]
                    if c == bg:
                        continue
                    # crude brightness
                    b = (c[0] * 3 + c[1] * 5 + c[2] * 2) // 10
                    if b > best:
                        best = b
            line += CHARS[min(len(CHARS) - 1, best * len(CHARS) // 256)]
        print(line)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/shot.png')
