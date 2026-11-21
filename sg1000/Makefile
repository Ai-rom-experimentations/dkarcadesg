SJASMPLUS ?= sjasmplus
PYTHON    ?= python3

ROM       := dkong.sg
GEN_ASM   := src/gfxdata.asm src/levels.asm src/snddata.asm
SRC_ASM   := src/main.asm src/game.asm src/sound.asm $(GEN_ASM)

.PHONY: all assets test clean

all: $(ROM)

assets: $(GEN_ASM)

src/gfxdata.asm: tools/gfxgen.py
	$(PYTHON) tools/gfxgen.py

src/levels.asm: tools/levelgen.py
	$(PYTHON) tools/levelgen.py

src/snddata.asm: tools/sndgen.py
	$(PYTHON) tools/sndgen.py

$(ROM): $(SRC_ASM)
	$(SJASMPLUS) --raw=$(ROM) src/main.asm

test: $(ROM)
	$(PYTHON) tools/emu.py $(ROM) --frames 180 --screenshot /tmp/sg_test.png

clean:
	rm -f $(ROM) *.lst
