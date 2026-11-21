; ============================================================================
;  DONKEY KONG - Sega SG-1000 48 KB Cartridge Port
;  Assemble:  sjasmplus --raw=build/dkong.sg src/main.asm
; ============================================================================

        ORG $0000

; ----------------------------------------------------------------------------
; Hardware I/O Ports (SG-1000 / SC-3000 / Mark III compatible)
; ----------------------------------------------------------------------------
VDP_DATA        equ $BE
VDP_CTRL        equ $BF
PSG             equ $7F
JOY1            equ $DC
JOY2            equ $DD

R0_MODE         equ 0
R1_CTRL         equ 1
R2_NAME         equ 2
R3_COLOR        equ 3
R4_PATTERN      equ 4
R5_SPRATTR      equ 5
R6_SPRPAT       equ 6
R7_BACKDROP     equ 7

VRAM_PATTERN    equ $0000
VRAM_NAME       equ $1800
VRAM_SPRATTR    equ $1F80
VRAM_COLOR      equ $2000
VRAM_SPRPAT     equ $3800

NAME_COLS       equ 32
SCREEN_W        equ 256
SCREEN_H        equ 192

; ----------------------------------------------------------------------------
; Work RAM Map (1 KB at $C000-$C3FF)
; ----------------------------------------------------------------------------
SPRBUF          equ $C000       ; 128B ($C000-$C07F): 32 sprites * 4
PLAYER          equ $C080       ;  24B ($C080-$C097)
DK              equ $C098       ;  16B ($C098-$C0A7)
GAME            equ $C0A8       ;  48B ($C0A8-$C0D7)
SOLID           equ $C0D8       ;  96B ($C0D8-$C137): 24 rows * 4B
ENEMIES         equ $C138       ;  96B ($C138-$C197): 12 slots * 8B
ELEV            equ $C198       ;  24B ($C198-$C1AF): 4 cars * 6B
ITEMS_TAKEN     equ $C1B0       ;   8B ($C1B0-$C1B7)
RIVETS_PULLED   equ $C1B8       ;   8B ($C1B8-$C1BF)
LEVELBUF        equ $C1C0       ; 200B ($C1C0-$C287): L_SIZE=195
HISCORES        equ $C288       ;  30B ($C288-$C2A5): 5 entries * 6B
NAMEENTRY       equ $C2A6       ;  10B ($C2A6-$C2AF)
MUSIC           equ $C2B0       ;  24B ($C2B0-$C2C7)
SCRATCH         equ $C2C8       ;  64B ($C2C8-$C307)
RAM_CLEAR_END   equ $C3A0
STACK_TOP       equ $C400

; Player fields (PLAYER + offset)
P_X             equ 0
P_Y             equ 1
P_YSUB          equ 2
P_VY            equ 3           ; signed 1/8 px per frame
P_STATE         equ 4
P_FLAGS         equ 5
P_ANIM          equ 6
P_LAD_COL       equ 7
P_LAD_TOP       equ 8
P_LAD_BOT       equ 9
P_STEP_T        equ 10
P_JUMP_CNT      equ 11

PS_STAND        equ 0
PS_RUN          equ 1
PS_JUMP         equ 2
PS_CLIMB        equ 3
PS_DEAD         equ 4
PS_WIN          equ 5

PF_GROUNDED     equ 0
PF_LEFT         equ 1           ; 0 = facing right, 1 = facing left

; DK fields (DK + offset)
D_X             equ 0
D_Y             equ 1
D_POSE          equ 2
D_FRAME         equ 3
D_TIMER         equ 4
D_DIR           equ 5

; Game fields (GAME + offset)
G_STATE         equ 0
G_MODE          equ 1           ; 0=US, 1=Japan Arcade, 2=Remix
G_LOOP          equ 2           ; difficulty loop (0=L01, 1=L02, ...)
G_STAGE_SEQ     equ 3           ; index within current level progression
G_STAGE_ID      equ 4           ; 0..7 stage index in STAGE_TABLE
G_LEVELTYPE     equ 5
G_BONUS         equ 6           ; 2 BCD bytes (6=hi, 7=lo)
G_BONUS_T       equ 8
G_FRAME         equ 9
G_LIVES         equ 10
G_SCORE0        equ 11          ; 3 BCD bytes (6 digits)
G_SCORE1        equ 12
G_SCORE2        equ 13
G_HS0           equ 14          ; Top score mirror (3 BCD bytes)
G_HS1           equ 15
G_HS2           equ 16
G_STATE_T       equ 17          ; state / cutscene timer
G_PHASE         equ 18          ; cutscene sub-phase
G_SPAWN_INT     equ 19
G_PAUSE         equ 20
G_HAMMER_TIME   equ 21
G_RIVETS        equ 22
G_1UP_AWARDED   equ 23
G_CONV_DIR      equ 24          ; 0 or 1 (reverses periodically)
G_CONV_T        equ 25
G_OIL_LIT       equ 26
G_FIRE_CNT      equ 27
G_POP_X         equ 28
G_POP_Y         equ 29
G_POP_PAT       equ 30
G_POP_T         equ 31
G_FLICKER       equ 32
G_ATTRACT_PAGE  equ 33
G_ATTRACT_T     equ 34          ; 2 bytes (34..35)
G_DEMO_PTR      equ 36          ; 2 bytes (36..37)
G_DEMO_T        equ 38
G_DEMO_MASK     equ 39
G_PAUSE_PREV    equ 40
G_RNG           equ 41
G_DEMO_IDX      equ 42
G_JB_CUR        equ 43
G_JB_TRK        equ 44
G_JB_SFX        equ 45

; Game states
GS_TITLE        equ 0
GS_HOWHIGH      equ 1
GS_PLAY         equ 2
GS_DYING        equ 3
GS_LEVELEND     equ 4
GS_NAMEENTRY    equ 5
GS_GAMEOVER     equ 6
GS_DEMO         equ 7
GS_VICTORY      equ 8
GS_INTRO        equ 9
GS_JUKEBOX      equ 10

; Level types
LT_GIRDERS      equ 0
LT_PIES         equ 1
LT_ELEVATORS    equ 2
LT_RIVETS       equ 3

; Input scratch offsets
INP_HELD        equ SCRATCH + 40
INP_PREV        equ SCRATCH + 41
INP_EDGE        equ SCRATCH + 42

; ============================================================================
; Hardware Vectors ($0000 Reset, $0038 IRQ, $0066 NMI Console Pause)
; ============================================================================
        DI
        IM 1
        LD SP, STACK_TOP
        JP ColdBoot

        DS $0038 - $, $FF
        ORG $0038
IrqVector:
        PUSH AF
        IN A, (VDP_CTRL)
        POP AF
        RETI

        DS $0066 - $, $FF
        ORG $0066
NmiVector:
        PUSH AF
        LD A, (GAME + G_STATE)
        CP GS_PLAY
        JR NZ, nmi_done
        LD A, (GAME + G_PAUSE)
        XOR 1
        LD (GAME + G_PAUSE), A
nmi_done:
        POP AF
        RETN

; ============================================================================
; Cold Boot Initialization
; ============================================================================
ColdBoot:
        ; Clear work RAM below stack
        LD HL, $C000
        LD DE, RAM_CLEAR_END - $C000
cb_clr:
        XOR A
        LD (HL), A
        INC HL
        DEC DE
        LD A, D
        OR E
        JR NZ, cb_clr

        LD A, $A5
        LD (GAME + G_RNG), A

        CALL InitHighScores
        CALL VdpInit
        CALL LoadSpriteAtlas
        CALL SoundInit
        CALL TitleScreen

; ============================================================================
; Main Frame Loop (60 Hz VBlank locked)
; ============================================================================
MainLoop:
        CALL WaitVblank
        CALL SoundFrame
        CALL ReadInput

        ; Advance LFSR RNG every frame (mixed with input bits)
        LD A, (GAME + G_RNG)
        RLCA
        XOR $1D
        LD B, A
        LD A, (INP_HELD)
        XOR B
        OR 1
        LD (GAME + G_RNG), A

        ; Exclusive state dispatch
        LD A, (GAME + G_STATE)
        CP GS_TITLE
        JR Z, ml_title
        CP GS_HOWHIGH
        JR Z, ml_howhigh
        CP GS_PLAY
        JR Z, ml_play
        CP GS_DYING
        JR Z, ml_dying
        CP GS_LEVELEND
        JR Z, ml_levelend
        CP GS_NAMEENTRY
        JR Z, ml_name
        CP GS_GAMEOVER
        JR Z, ml_over
        CP GS_DEMO
        JR Z, ml_demo
        CP GS_VICTORY
        JR Z, ml_victory
        CP GS_INTRO
        JR Z, ml_intro
        CP GS_JUKEBOX
        JR Z, ml_jukebox
        JR MainLoop

ml_title:
        CALL TitleUpdate
        JR MainLoop
ml_howhigh:
        CALL HowHighUpdate
        JR MainLoop
ml_play:
        CALL PlayUpdate
        JR MainLoop
ml_dying:
        CALL DyingUpdate
        JR MainLoop
ml_levelend:
        CALL LevelEndUpdate
        JR MainLoop
ml_name:
        CALL NameEntryUpdate
        JR MainLoop
ml_over:
        CALL GameOverUpdate
        JR MainLoop
ml_demo:
        CALL DemoUpdate
        JR MainLoop
ml_victory:
        CALL VictoryUpdate
        JP MainLoop
ml_intro:
        CALL IntroUpdate
        JP MainLoop
ml_jukebox:
        CALL JukeboxUpdate
        JP MainLoop

; ============================================================================
; VDP Core Routines (TMS9918A Mode 2)
; ============================================================================
VdpInit:
        LD HL, $0000
        LD DE, $4000
        CALL VdpClear
        LD A, $02               ; M3=1 -> Graphics II (Mode 2)
        LD B, R0_MODE
        CALL VdpSetReg
        LD A, $40               ; Display ON, 8x8 sprites
        LD B, R1_CTRL
        CALL VdpSetReg
        LD A, $06               ; Name table = $1800
        LD B, R2_NAME
        CALL VdpSetReg
        LD A, $9F               ; Single bank Color = $2000
        LD B, R3_COLOR
        CALL VdpSetReg
        LD A, $00               ; Single bank Pattern = $0000
        LD B, R4_PATTERN
        CALL VdpSetReg
        LD A, $3F               ; Sprite Attributes = $1F80
        LD B, R5_SPRATTR
        CALL VdpSetReg
        LD A, $07               ; Sprite Patterns = $3800
        LD B, R6_SPRPAT
        CALL VdpSetReg
        LD A, $01               ; Black backdrop
        LD B, R7_BACKDROP
        JP VdpSetReg

VdpDisplayOff:
        LD A, $00
        LD B, R1_CTRL
        JP VdpSetReg

VdpDisplayOn:
        LD A, $40
        LD B, R1_CTRL
        JP VdpSetReg

; A = value, B = register
VdpSetReg:
        OUT (VDP_CTRL), A
        LD A, B
        OR $80
        OUT (VDP_CTRL), A
        RET

; BC = VRAM write address
VdpSetAddr:
        LD A, C
        OUT (VDP_CTRL), A
        LD A, B
        OR $40
        OUT (VDP_CTRL), A
        RET

VdpPut:
        OUT (VDP_DATA), A
        RET

; HL = VRAM start, DE = byte count
VdpClear:
        LD C, L
        LD B, H
        CALL VdpSetAddr
vc_loop:
        XOR A
        OUT (VDP_DATA), A
        DEC DE
        LD A, D
        OR E
        JR NZ, vc_loop
        RET

; HL = RAM/ROM source, DE = byte count, BC = VRAM destination
VdpWriteAt:
        CALL VdpSetAddr
vw_loop:
        LD A, (HL)
        OUT (VDP_DATA), A
        INC HL
        DEC DE
        LD A, D
        OR E
        JR NZ, vw_loop
        RET

HideSprites:
        LD HL, SPRBUF
        LD B, 32
hs_clr:
        LD (HL), $D0
        INC HL
        XOR A
        LD (HL), A
        INC HL
        LD (HL), A
        INC HL
        LD (HL), A
        INC HL
        DJNZ hs_clr
        LD HL, SPRBUF
        LD DE, 128
        LD BC, VRAM_SPRATTR
        JP VdpWriteAt

LoadSpriteAtlas:
        LD HL, SPRITE_PATTERNS
        LD DE, SPRITE_PATTERN_COUNT * 8
        LD BC, VRAM_SPRPAT
        JP VdpWriteAt

; Load Stage Tileset Bank A (0..7) in single-bank Mode 2
LoadStageGfx:
        PUSH AF
        CALL VdpDisplayOff
        CALL HideSprites
        LD A, $9F
        LD B, R3_COLOR
        CALL VdpSetReg
        LD A, $00
        LD B, R4_PATTERN
        CALL VdpSetReg

        POP AF
        AND 7
        ADD A, A
        ADD A, A
        LD L, A
        LD H, 0
        LD DE, STAGE_GFX_TABLE
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        INC HL
        PUSH HL
        EX DE, HL
        LD DE, STAGE_TILE_COUNT * 8
        LD BC, VRAM_PATTERN
        CALL VdpWriteAt
        POP HL
        LD E, (HL)
        INC HL
        LD D, (HL)
        EX DE, HL
        LD DE, STAGE_TILE_COUNT * 8
        LD BC, VRAM_COLOR
        CALL VdpWriteAt

        ; Load shared font into bank 0 (192..254)
        LD HL, FONT_PATTERNS
        LD DE, FONT_COUNT * 8
        LD BC, VRAM_PATTERN + (T_FONT_BASE * 8)
        CALL VdpWriteAt
        LD HL, FONT_COLORS
        LD DE, FONT_COUNT * 8
        LD BC, VRAM_COLOR + (T_FONT_BASE * 8)
        JP VdpWriteAt

; Load Full-Screen 3-Bank Mode-2 Artwork Descriptor at HL
LoadArtScreen:
        PUSH HL
        CALL VdpDisplayOff
        CALL HideSprites
        LD A, $FF               ; All 3 color banks ($2000, $2800, $3000)
        LD B, R3_COLOR
        CALL VdpSetReg
        LD A, $03               ; All 3 pattern banks ($0000, $0800, $1000)
        LD B, R4_PATTERN
        CALL VdpSetReg

        POP IX
        ; Bank 0
        LD BC, $0000
        CALL las_one_bank
        ; Bank 1
        LD BC, $0800
        CALL las_one_bank
        ; Bank 2
        LD BC, $1000
        CALL las_one_bank

        ; Load nametable (768 bytes)
        LD L, (IX + 0)
        LD H, (IX + 1)
        LD DE, 768
        LD BC, VRAM_NAME
        CALL VdpWriteAt

        ; Copy shared font into all 3 banks so DrawText works on any row!
        LD BC, $0000 + (T_FONT_BASE * 8)
        CALL las_font_bank
        LD BC, $0800 + (T_FONT_BASE * 8)
        CALL las_font_bank
        LD BC, $1000 + (T_FONT_BASE * 8)
        CALL las_font_bank

        JP VdpDisplayOn

; IX -> DB count, DW pat, DW col; BC = bank offset ($0000/$0800/$1000)
las_one_bank:
        PUSH BC
        LD A, (IX + 0)
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL              ; HL = count * 8
        PUSH HL                 ; save byte length
        LD E, (IX + 1)
        LD D, (IX + 2)
        EX DE, HL               ; HL = pat_ptr, DE = byte length
        CALL VdpWriteAt
        POP DE                  ; byte length
        POP BC                  ; bank offset
        PUSH DE
        LD A, B
        ADD A, $20              ; color bank = pattern bank + $2000
        LD B, A
        LD L, (IX + 3)
        LD H, (IX + 4)
        CALL VdpWriteAt
        POP DE
        LD DE, 5
        ADD IX, DE
        RET

las_font_bank:
        PUSH BC
        LD HL, FONT_PATTERNS
        LD DE, FONT_COUNT * 8
        CALL VdpWriteAt
        POP BC
        LD A, B
        ADD A, $20
        LD B, A
        LD HL, FONT_COLORS
        LD DE, FONT_COUNT * 8
        JP VdpWriteAt

; ============================================================================
; Input & Text Helpers
; ============================================================================
ReadInput:
        IN A, (JOY1)
        CPL
        AND $3F
        LD B, A
        LD (INP_HELD), A
        LD A, (INP_PREV)
        XOR B
        AND B
        LD (INP_EDGE), A
        LD A, B
        LD (INP_PREV), A
        RET

; HL = VRAM_NAME address, DE = $FF-terminated ASCII string
DrawText:
        LD C, L
        LD B, H
        CALL VdpSetAddr
dt_loop:
        LD A, (DE)
        CP $FF
        RET Z
        SUB $20
        LD C, A
        LD B, 0
        LD HL, FONT_MAP
        ADD HL, BC
        LD A, (HL)
        OUT (VDP_DATA), A
        INC DE
        JR dt_loop

; HL = VRAM_NAME address, DE = BCD bytes, B = byte count (2 digits per byte)
DrawDigits:
        PUSH BC
        LD C, L
        LD B, H
        CALL VdpSetAddr
        POP BC
dd_loop:
        LD A, (DE)
        PUSH BC
        PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        AND $0F
        ADD A, $10
        LD C, A
        LD B, 0
        LD HL, FONT_MAP
        ADD HL, BC
        LD A, (HL)
        OUT (VDP_DATA), A
        POP AF
        AND $0F
        ADD A, $10
        LD C, A
        LD B, 0
        LD HL, FONT_MAP
        ADD HL, BC
        LD A, (HL)
        OUT (VDP_DATA), A
        INC DE
        POP BC
        DJNZ dd_loop
        RET

WaitVblank:
        IN A, (VDP_CTRL)
        BIT 7, A
        JR Z, WaitVblank
        RET

; ============================================================================
; Includes
; ============================================================================
        INCLUDE "src/gfxdata.asm"
        INCLUDE "src/levels.asm"
        INCLUDE "src/game.asm"
        INCLUDE "src/sound.asm"

ROM_USED_END:
        ; Pad cartridge ROM cleanly to exact 48 KB ($0000-$BFFF = 49,152 bytes)
        ; Note: No "TMR SEGA" SMS header at $7FF0 so emulators auto-detect SG-1000!
        DS $BFC0 - $, $FF
        ORG $BFC0
        DB "DONKEY KONG SG-1000 48K EDITION "
        DB "12 STAGES / 7 ART SCREENS / 2026"
