; ============================================================================
;  DONKEY KONG - Complete Game Logic, Physics, AI, Cutscenes & UI
; ============================================================================

; Enemy slot layout (8 bytes per slot, 12 slots at ENEMIES)
MAX_ENEMIES     equ 12
E_STATE         equ 0           ; 0=free, 1=ground/active, 2=falling, 3=ladder
E_TYPE          equ 1           ; ET_*
E_X             equ 2
E_Y             equ 3
E_VX            equ 4
E_VY            equ 5
E_ANIM          equ 6           ; bit 7 = jump-scored flag
E_DATA          equ 7           ; target Y or bounce phase

ET_BARREL       equ 0
ET_BLUE         equ 1
ET_FIRE         equ 2
ET_SPRING       equ 3
ET_PIE          equ 4

; Elevator car layout (6 bytes per car, 4 cars at ELEV)
EL_COL          equ 0
EL_ROW          equ 1
EL_DY           equ 2           ; -1 (up) or +1 (down)
EL_MIN          equ 3
EL_MAX          equ 4
EL_TIMER        equ 5
EL_SIZE         equ 6

; Constant O(1) bitmask lookup table
BIT_MASK_TABLE:
        DB $01, $02, $04, $08, $10, $20, $40, $80

; Parabolic spring bounce Y-offsets above Kong's girder (16 steps per hop)
SPRING_ARC_TABLE:
        DB 0, 4, 8, 11, 14, 16, 17, 18, 18, 17, 16, 14, 11, 8, 4, 0

; ============================================================================
;  Tilemap & O(1) Collision Bitmap Primitives
; ============================================================================
; B = col (0..31), C = row (0..23) -> HL = VRAM_NAME + row*32 + col
NameAddr:
        LD H, 0
        LD L, C
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD A, B
        AND 31
        OR L
        LD L, A
        LD A, H
        ADD A, HIGH(VRAM_NAME)
        LD H, A
        RET

; B = col, C = row, A = tile (preserves BC, DE, HL)
TilePut:
        PUSH HL
        PUSH BC
        PUSH AF
        CALL NameAddr
        LD C, L
        LD B, H
        CALL VdpSetAddr
        POP AF
        OUT (VDP_DATA), A
        POP BC
        POP HL
        RET

; B = col, C = row -> A = 1 if solid, 0 if empty/out-of-bounds (preserves BC)
SolidAt:
        LD A, B
        CP 32
        JR NC, sa_out
        LD A, C
        CP 24
        JR NC, sa_out
        PUSH HL
        PUSH DE
        LD L, C
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        LD DE, SOLID
        ADD HL, DE
        LD A, B
        RRCA
        RRCA
        RRCA
        AND $03
        LD E, A
        LD D, 0
        ADD HL, DE
        LD A, (HL)
        LD E, A
        LD A, B
        AND $07
        LD HL, BIT_MASK_TABLE
        ADD A, L
        LD L, A
        JR NC, sa_nc
        INC H
sa_nc:
        LD A, (HL)
        AND E
        POP DE
        POP HL
        RET Z
        LD A, 1
        RET
sa_out:
        XOR A
        RET

; B = col, C = row, A = 0/1 (preserves BC)
SetSolid:
        PUSH HL
        PUSH DE
        PUSH BC
        LD D, A                 ; save 0/1 flag in D
        LD A, B
        CP 32
        JR NC, ss_done
        LD A, C
        CP 24
        JR NC, ss_done
        LD L, C
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        PUSH DE
        LD DE, SOLID
        ADD HL, DE
        LD A, B
        RRCA
        RRCA
        RRCA
        AND $03
        LD E, A
        LD D, 0
        ADD HL, DE
        POP DE                  ; D = 0/1 flag, HL = byte in SOLID
        PUSH HL
        LD A, B
        AND $07
        LD HL, BIT_MASK_TABLE
        ADD A, L
        LD L, A
        JR NC, ss_nc
        INC H
ss_nc:
        LD E, (HL)              ; E = bit mask
        POP HL
        LD A, D
        OR A
        JR Z, ss_clr
        LD A, (HL)
        OR E
        LD (HL), A
        JR ss_done
ss_clr:
        LD A, E
        CPL
        AND (HL)
        LD (HL), A
ss_done:
        POP BC
        POP DE
        POP HL
        RET

; B = col, C = y_px -> A = first solid row >= (C >> 3), or $FF
SurfaceAt:
        PUSH BC
        LD A, C
        SRL A
        SRL A
        SRL A
        LD C, A
sfa_loop:
        LD A, C
        CP 24
        JR NC, sfa_none
        CALL SolidAt
        OR A
        JR NZ, sfa_hit
        INC C
        JR sfa_loop
sfa_hit:
        LD A, C
        POP BC
        RET
sfa_none:
        POP BC
        LD A, $FF
        RET

CharTile:
        SUB $20
        LD C, A
        LD B, 0
        LD HL, FONT_MAP
        ADD HL, BC
        LD A, (HL)
        RET

; B = col, C = row, A = ASCII char
TilePutChar:
        PUSH BC
        PUSH HL
        CALL CharTile
        POP HL
        POP BC
        JP TilePut

Abs:
        OR A
        RET P
        NEG
        RET

; ============================================================================
;  High Score Table (5 entries: 3 BCD bytes + 3 ASCII chars)
; ============================================================================
DEFAULT_HISCORES:
        DB $00, $76, $50, "KNG"
        DB $00, $61, $00, "MAR"
        DB $00, $50, $00, "PAU"
        DB $00, $42, $00, "SEG"
        DB $00, $30, $00, "SG1"

InitHighScores:
        LD HL, DEFAULT_HISCORES
        LD DE, HISCORES
        LD BC, 30
        LDIR
        JP SyncTopHighScore

SyncTopHighScore:
        LD HL, HISCORES
        LD DE, GAME + G_HS0
        LD BC, 3
        LDIR
        RET

; Add BCD value BC to 6-digit score (B -> thousands/hundreds, C -> tens/ones)
AddScoreBC:
        LD A, (GAME + G_STATE)
        CP GS_DEMO
        RET Z                   ; never score during attract demo!

        LD A, (GAME + G_SCORE2)
        ADD A, C
        DAA
        LD (GAME + G_SCORE2), A
        LD A, (GAME + G_SCORE1)
        ADC A, B
        DAA
        LD (GAME + G_SCORE1), A
        LD A, (GAME + G_SCORE0)
        ADC A, 0
        DAA
        LD (GAME + G_SCORE0), A

        ; Live high-score sync
        LD HL, GAME + G_HS0
        LD DE, GAME + G_SCORE0
        CALL CmpScore3
        JR NC, as_chk1up
        LD HL, GAME + G_SCORE0
        LD DE, GAME + G_HS0
        LD BC, 3
        LDIR

as_chk1up:
        ; Extra life at 7,000 points!
        LD A, (GAME + G_1UP_AWARDED)
        OR A
        RET NZ
        LD A, (GAME + G_SCORE0)
        OR A
        JR NZ, as_give1up
        LD A, (GAME + G_SCORE1)
        CP $70
        RET C
as_give1up:
        LD A, 1
        LD (GAME + G_1UP_AWARDED), A
        LD A, (GAME + G_LIVES)
        INC A
        LD (GAME + G_LIVES), A
        LD A, (PLAYER + P_X)
        ADD A, 4
        LD B, A
        LD A, (PLAYER + P_Y)
        SUB 8
        LD C, A
        LD A, SPR_POP_1UP
        CALL SpawnPopup
        JP Sound1Up

; Compare 3-byte BCD at (HL) vs (DE): Carry set if (HL) < (DE)
CmpScore3:
        LD B, 3
cs3_lp:
        LD A, (DE)
        LD C, A
        LD A, (HL)
        CP C
        RET NZ
        INC HL
        INC DE
        DJNZ cs3_lp
        OR A
        RET

; ============================================================================
;  Floating Score Popup Helper
; ============================================================================
; B = x, C = y, A = SPR_POP_*
SpawnPopup:
        LD (GAME + G_POP_PAT), A
        LD A, B
        LD (GAME + G_POP_X), A
        LD A, C
        LD (GAME + G_POP_Y), A
        LD A, 36
        LD (GAME + G_POP_T), A
        RET

; ============================================================================
;  Title Screen & 4-Page Attract Mode Cycle
; ============================================================================
TitleScreen:
        XOR A
        LD (GAME + G_PAUSE), A
        LD (GAME + G_ATTRACT_PAGE), A
        LD HL, 360
        LD (GAME + G_ATTRACT_T), HL
        LD A, GS_TITLE
        LD (GAME + G_STATE), A
        CALL DrawTitlePage
        LD A, TRK_MUS_ATTRACT
        JP MusicPlayIfNew

DrawTitlePage:
        LD HL, ART_TITLE_DESC
        CALL LoadArtScreen
        CALL DrawTopScoreBar
        CALL DrawModeMenu
        LD HL, VRAM_NAME + (22 * NAME_COLS) + 4
        LD DE, txt_copy
        JP DrawText

DrawTopScoreBar:
        LD HL, VRAM_NAME + 1
        LD DE, txt_hud1
        CALL DrawText
        LD HL, VRAM_NAME + 5
        LD DE, GAME + G_SCORE0
        LD B, 3
        CALL DrawDigits
        LD HL, VRAM_NAME + 21
        LD DE, GAME + G_HS0
        LD B, 3
        JP DrawDigits

DrawModeMenu:
        LD HL, VRAM_NAME + (14 * NAME_COLS) + 8
        LD DE, txt_mode0
        CALL DrawText
        LD HL, VRAM_NAME + (16 * NAME_COLS) + 8
        LD DE, txt_mode1
        CALL DrawText
        LD HL, VRAM_NAME + (18 * NAME_COLS) + 8
        LD DE, txt_mode2
        CALL DrawText
        LD HL, VRAM_NAME + (20 * NAME_COLS) + 8
        LD DE, txt_mode3
        CALL DrawText

        ; Clear old cursors and draw '>' next to G_MODE (0..3)
        LD B, 6
        LD C, 14
        LD A, ' '
        CALL TilePutChar
        LD C, 16
        LD A, ' '
        CALL TilePutChar
        LD C, 18
        LD A, ' '
        CALL TilePutChar
        LD C, 20
        LD A, ' '
        CALL TilePutChar

        LD A, (GAME + G_MODE)
        ADD A, A
        ADD A, 14
        LD C, A
        LD B, 6
        LD A, '>'
        JP TilePutChar

DrawHighScorePage:
        LD HL, ART_HALL_DESC
        CALL LoadArtScreen
        CALL DrawTopScoreBar

        LD HL, VRAM_NAME + (5 * NAME_COLS) + 7
        LD DE, txt_hall
        CALL DrawText

        ; 5 high score rows at rows 8, 10, 12, 14, 16
        LD IX, HISCORES
        LD B, 5
        LD C, 8
dhp_row:
        PUSH BC
        ; Rank digit "1.".."5."
        LD A, 6
        SUB B
        ADD A, '0'
        LD B, 7
        CALL TilePutChar
        LD B, 8
        LD A, '.'
        CALL TilePutChar

        ; Score (6 BCD digits) at col 10
        LD B, 10
        CALL NameAddr
        PUSH IX
        POP DE
        LD B, 3
        CALL DrawDigits

        ; 3 initials at col 19..21
        POP BC
        PUSH BC
        LD A, (IX + 3)
        LD B, 19
        CALL TilePutChar
        LD A, (IX + 4)
        LD B, 20
        CALL TilePutChar
        LD A, (IX + 5)
        LD B, 21
        CALL TilePutChar

        LD DE, 6
        ADD IX, DE
        POP BC
        INC C
        INC C
        DJNZ dhp_row

        LD HL, VRAM_NAME + (19 * NAME_COLS) + 9
        LD DE, txt_press
        JP DrawText

DrawCastPage:
        LD HL, ART_CAST_DESC
        CALL LoadArtScreen
        CALL DrawTopScoreBar
        LD HL, VRAM_NAME + (3 * NAME_COLS) + 9
        LD DE, txt_cast_hdr
        CALL DrawText
        LD HL, VRAM_NAME + (5 * NAME_COLS) + 8
        LD DE, txt_cast1
        CALL DrawText
        LD HL, VRAM_NAME + (7 * NAME_COLS) + 8
        LD DE, txt_cast2
        CALL DrawText
        LD HL, VRAM_NAME + (9 * NAME_COLS) + 8
        LD DE, txt_cast3
        CALL DrawText
        LD HL, VRAM_NAME + (11 * NAME_COLS) + 4
        LD DE, txt_cast_pts
        CALL DrawText
        LD HL, VRAM_NAME + (19 * NAME_COLS) + 3
        LD DE, txt_cast_vals
        JP DrawText

TitleUpdate:
        ; Mode selection with Up/Down (0..3)
        LD A, (INP_EDGE)
        BIT 0, A
        JR Z, tu_chk_dn
        LD A, (GAME + G_MODE)
        OR A
        JR NZ, tu_mdec
        LD A, 4
tu_mdec:
        DEC A
        LD (GAME + G_MODE), A
        CALL SoundTick
        LD HL, 360
        LD (GAME + G_ATTRACT_T), HL
        LD A, (GAME + G_ATTRACT_PAGE)
        OR A
        JP Z, DrawModeMenu
        XOR A
        LD (GAME + G_ATTRACT_PAGE), A
        JP DrawTitlePage

tu_chk_dn:
        BIT 1, A
        JR Z, tu_chk_btn
        LD A, (GAME + G_MODE)
        INC A
        CP 4
        JR C, tu_minc
        XOR A
tu_minc:
        LD (GAME + G_MODE), A
        CALL SoundTick
        LD HL, 360
        LD (GAME + G_ATTRACT_T), HL
        LD A, (GAME + G_ATTRACT_PAGE)
        OR A
        JP Z, DrawModeMenu
        XOR A
        LD (GAME + G_ATTRACT_PAGE), A
        JP DrawTitlePage

tu_chk_btn:
        AND $30
        JR Z, tu_attract
        LD A, (GAME + G_MODE)
        CP 3
        JP Z, StartJukebox
        JP StartNewGame

tu_attract:
        ; Attract-mode page timer
        LD HL, (GAME + G_ATTRACT_T)
        DEC HL
        LD (GAME + G_ATTRACT_T), HL
        LD A, H
        OR L
        RET NZ

        LD HL, 340
        LD (GAME + G_ATTRACT_T), HL
        LD A, (GAME + G_ATTRACT_PAGE)
        INC A
        LD (GAME + G_ATTRACT_PAGE), A
        CP 1
        JP Z, DrawHighScorePage
        CP 2
        JP Z, DrawCastPage
        CP 3
        JP Z, StartAttractDemo
        XOR A
        LD (GAME + G_ATTRACT_PAGE), A
        JP DrawTitlePage

StartNewGame:
        LD HL, GAME + G_SCORE0
        XOR A
        LD (HL), A
        INC HL
        LD (HL), A
        INC HL
        LD (HL), A
        LD (GAME + G_LOOP), A
        LD (GAME + G_STAGE_SEQ), A
        LD (GAME + G_1UP_AWARDED), A
        LD (GAME + G_PAUSE), A
        LD A, 3
        LD (GAME + G_LIVES), A
        CALL ResolveCurrentStage
        JP StartIntroScene

; ============================================================================
;  Iconic Arcade Opening Cutscene (Kong Climbs Twin Ladders & Warps Girders!)
; ============================================================================
StartIntroScene:
        XOR A
        CALL LoadStageGfx
        LD HL, VRAM_NAME
        LD DE, 768
        CALL VdpClear

        ; Clear dynamic entities so BuildSprites renders only DK & Pauline!
        LD HL, ENEMIES
        LD B, 96
        XOR A
sis_ce: LD (HL), A
        INC HL
        DJNZ sis_ce
        LD (GAME + G_HAMMER_TIME), A
        LD (GAME + G_POP_T), A

        ; Hide Mario off-screen during Kong's climb!
        LD A, 200
        LD (PLAYER + P_Y), A
        XOR A
        LD (PLAYER + P_STATE), A

        ; Draw Pauline's top girder (row 4, cols 12..17) + 6 flat girders (rows 7,10,13,16,19,22)
        LD C, 4
        LD B, 12
sis_p4:
        LD A, T_GIRDER
        CALL TilePut
        INC B
        LD A, B
        CP 18
        JR C, sis_p4

        LD C, 7
sis_glp:
        LD B, 1
sis_gcol:
        LD A, T_GIRDER
        CALL TilePut
        INC B
        LD A, B
        CP 31
        JR C, sis_gcol
        LD A, C
        ADD A, 3
        LD C, A
        CP 23
        JR C, sis_glp

        ; Twin full-height center ladders (cols 13 & 15, rows 2..21) + upper ladder col 16
        LD C, 2
sis_llp:
        LD B, 13
        LD A, T_LADDER
        CALL TilePut
        LD B, 15
        LD A, T_LADDER
        CALL TilePut
        INC C
        LD A, C
        CP 22
        JR C, sis_llp

        ; Init DK at bottom of twin ladders (X=108, Y=160) & Pauline on his shoulder!
        LD A, 108
        LD (DK + D_X), A
        LD A, 160
        LD (DK + D_Y), A
        LD A, 1
        LD (DK + D_POSE), A
        LD A, 15
        LD (LEVELBUF + L_PAUXX), A
        LD A, 21
        LD (LEVELBUF + L_PAUYY), A

        XOR A
        LD (GAME + G_PHASE), A
        LD (GAME + G_STATE_T), A
        CALL DrawHUD
        CALL BuildSprites
        CALL VdpDisplayOn
        LD A, GS_INTRO
        LD (GAME + G_STATE), A
        LD A, TRK_MUS_CLIMB
        JP MusicPlay

IntroUpdate:
        ; Allow Button 1/2 skip after 10 frames!
        LD A, (GAME + G_STATE_T)
        INC A
        LD (GAME + G_STATE_T), A
        CP 10
        JR C, iu_run
        LD A, (INP_EDGE)
        AND $30
        JP NZ, HowHighScreen

iu_run:
        LD A, (GAME + G_FRAME)
        INC A
        LD (GAME + G_FRAME), A

        LD A, (GAME + G_PHASE)
        OR A
        JR NZ, iu_stomp

        ; Phase 0: Kong climbs UP twin ladders from Y=160 to Y=40, tearing rungs below!
        LD A, (DK + D_Y)
        SUB 2
        LD (DK + D_Y), A
        ; Alternate Kong's climbing arms (pose 1 / 2)
        RRCA
        RRCA
        RRCA
        AND 1
        INC A
        LD (DK + D_POSE), A

        ; Pauline rides upward on Kong's shoulder
        LD A, (DK + D_Y)
        ADD A, 12
        RRCA
        RRCA
        RRCA
        AND $1F
        LD (LEVELBUF + L_PAUYY), A

        ; Tear out ladder rungs 2 rows below Kong (leave girder rows 7,10,13,16,19 intact!)
        LD A, (DK + D_Y)
        ADD A, 24
        RRCA
        RRCA
        RRCA
        AND $1F
        CP 22
        JR NC, iu_chk_top
        CP 7
        JR C, iu_chk_top
        ; Skip girder rows (7, 10, 13, 16, 19)
        LD C, A
        SUB 7
iu_mod3:
        CP 3
        JR C, iu_m3ok
        SUB 3
        JR iu_mod3
iu_m3ok:
        OR A
        JR Z, iu_chk_top
        LD B, 13
        LD A, T_BLANK
        CALL TilePut
        LD B, 15
        LD A, T_BLANK
        CALL TilePut

iu_chk_top:
        LD A, (DK + D_Y)
        CP 40
        JP NZ, BuildSprites

        ; Reached row 7! Place Pauline on top platform (col 13, row 4) & begin 4 stomps!
        LD A, 13
        LD (LEVELBUF + L_PAUXX), A
        LD A, 4
        LD (LEVELBUF + L_PAUYY), A
        LD A, 1
        LD (GAME + G_PHASE), A
        XOR A
        LD (GAME + G_STATE_T), A
        JP BuildSprites

iu_stomp:
        CP 5
        JR NC, iu_laugh
        ; 4 heavy hops leftward (phase 1..4), each 18 frames!
        LD A, (GAME + G_STATE_T)
        CP 18
        JR NC, iu_land_hop
        ; Parabolic hop arc + 1px/frame leftward
        LD B, A
        LD A, (DK + D_X)
        SUB 1
        LD (DK + D_X), A
        LD A, B
        CP 9
        JR C, iu_hop_up
        LD A, 18
        SUB B
iu_hop_up:
        LD B, A
        LD A, 40
        SUB B
        LD (DK + D_Y), A
        JP BuildSprites

iu_land_hop:
        LD A, 40
        LD (DK + D_Y), A
        XOR A
        LD (DK + D_POSE), A
        LD (GAME + G_STATE_T), A
        CALL SoundSmash

        ; Warp one girder tier per stomp (erasing left/right end cap to show crooked slope!)
        LD A, (GAME + G_PHASE)  ; 1..4 -> rows 19, 16, 13, 10
        LD B, A
        LD A, 22
iu_sub3:
        SUB 3
        DJNZ iu_sub3
        LD C, A                 ; target girder row
        LD A, (GAME + G_PHASE)
        BIT 0, A
        LD B, 30
        JR NZ, iu_warp_put
        LD B, 1
iu_warp_put:
        LD A, T_BLANK
        CALL TilePut

        LD A, (GAME + G_PHASE)
        INC A
        LD (GAME + G_PHASE), A
        CP 5
        JP C, BuildSprites
        CALL SoundRoar
        JP BuildSprites

iu_laugh:
        ; Grin & beat chest for 55 frames, then enter HowHighScreen!
        LD A, (GAME + G_STATE_T)
        BIT 3, A
        LD B, 1
        JR Z, iu_lpose
        LD B, 2
iu_lpose:
        LD A, B
        LD (DK + D_POSE), A
        CALL BuildSprites
        LD A, (GAME + G_STATE_T)
        CP 55
        RET C
        JP HowHighScreen

; ============================================================================
;  Interactive Sound & Stage Jukebox Lab (GS_JUKEBOX)
; ============================================================================
StartJukebox:
        XOR A
        LD (GAME + G_JB_CUR), A
        LD (GAME + G_STAGE_ID), A
        LD (GAME + G_LOOP), A
        LD (GAME + G_JB_TRK), A
        LD A, 1
        LD (GAME + G_JB_SFX), A
        LD HL, ART_JUKEBOX_DESC
        CALL LoadArtScreen
        CALL DrawTopScoreBar
        LD HL, VRAM_NAME + (2 * NAME_COLS) + 6
        LD DE, txt_jb_hdr
        CALL DrawText
        LD HL, VRAM_NAME + (21 * NAME_COLS) + 3
        LD DE, txt_jb_help
        CALL DrawText
        CALL DrawJukeboxMenu
        LD A, GS_JUKEBOX
        LD (GAME + G_STATE), A
        LD A, TRK_BGM_BARRELS
        JP MusicPlay

DrawJukeboxMenu:
        ; Clear cursor column (col 3) on rows 11, 13, 15, 17, 19
        LD B, 3
        LD C, 11
djm_c:
        LD A, ' '
        CALL TilePutChar
        INC C
        INC C
        LD A, C
        CP 21
        JR C, djm_c

        ; Active '>' cursor
        LD A, (GAME + G_JB_CUR)
        ADD A, A
        ADD A, 11
        LD C, A
        LD B, 3
        LD A, '>'
        CALL TilePutChar

        ; Row 11: STAGE: < XX NAME >
        LD HL, VRAM_NAME + (11 * NAME_COLS) + 5
        LD DE, txt_jb_stage
        CALL DrawText
        LD A, (GAME + G_STAGE_ID)
        ADD A, A
        LD L, A
        LD H, 0
        LD DE, jb_stage_names
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        LD HL, VRAM_NAME + (11 * NAME_COLS) + 12
        CALL DrawText

        ; Row 13: LOOP : L=0X
        LD HL, VRAM_NAME + (13 * NAME_COLS) + 5
        LD DE, txt_jb_loop
        CALL DrawText
        LD A, (GAME + G_LOOP)
        ADD A, '1'
        LD B, 15
        LD C, 13
        CALL TilePutChar

        ; Row 15: MUSIC: XX NAME
        LD HL, VRAM_NAME + (15 * NAME_COLS) + 5
        LD DE, txt_jb_mus
        CALL DrawText
        LD A, (GAME + G_JB_TRK)
        ADD A, A
        LD L, A
        LD H, 0
        LD DE, jb_trk_names
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        LD HL, VRAM_NAME + (15 * NAME_COLS) + 12
        CALL DrawText

        ; Row 17: SFX  : XX NAME
        LD HL, VRAM_NAME + (17 * NAME_COLS) + 5
        LD DE, txt_jb_sfx
        CALL DrawText
        LD A, (GAME + G_JB_SFX)
        DEC A
        ADD A, A
        LD L, A
        LD H, 0
        LD DE, jb_sfx_names
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        LD HL, VRAM_NAME + (17 * NAME_COLS) + 12
        CALL DrawText

        ; Row 19: LAUNCH SELECTED STAGE
        LD HL, VRAM_NAME + (19 * NAME_COLS) + 5
        LD DE, txt_jb_go
        JP DrawText

JukeboxUpdate:
        ; Button 2 ($20) returns to Title Screen
        LD A, (INP_EDGE)
        BIT 5, A
        JP NZ, TitleScreen

        ; Up / Down moves cursor 0..4
        BIT 0, A
        JR Z, jbu_dn
        LD A, (GAME + G_JB_CUR)
        OR A
        JR NZ, jbu_up_ok
        LD A, 5
jbu_up_ok:
        DEC A
        LD (GAME + G_JB_CUR), A
        CALL SoundTick
        JP DrawJukeboxMenu

jbu_dn:
        BIT 1, A
        JR Z, jbu_lr
        LD A, (GAME + G_JB_CUR)
        INC A
        CP 5
        JR C, jbu_dn_ok
        XOR A
jbu_dn_ok:
        LD (GAME + G_JB_CUR), A
        CALL SoundTick
        JP DrawJukeboxMenu

jbu_lr:
        ; Left (-1) or Right (+1) adjusts current field
        LD C, 0
        BIT 2, A
        JR Z, jbu_chk_r
        LD C, -1
jbu_chk_r:
        BIT 3, A
        JR Z, jbu_chk_b1
        LD C, 1
jbu_chk_b1:
        LD A, C
        OR A
        JR Z, jbu_b1

        LD A, (GAME + G_JB_CUR)
        OR A
        JR Z, jbu_adj_stage
        CP 1
        JR Z, jbu_adj_loop
        CP 2
        JR Z, jbu_adj_trk
        CP 3
        JR Z, jbu_adj_sfx
        RET

jbu_adj_stage:
        LD A, (GAME + G_STAGE_ID)
        ADD A, C
        CP $FF
        JR NZ, jbu_st_hi
        LD A, STAGE_COUNT - 1
jbu_st_hi:
        CP STAGE_COUNT
        JR C, jbu_st_set
        XOR A
jbu_st_set:
        LD (GAME + G_STAGE_ID), A
        CALL SoundTick
        JP DrawJukeboxMenu

jbu_adj_loop:
        LD A, (GAME + G_LOOP)
        ADD A, C
        AND 3
        LD (GAME + G_LOOP), A
        CALL SoundTick
        JP DrawJukeboxMenu

jbu_adj_trk:
        LD A, (GAME + G_JB_TRK)
        ADD A, C
        CP $FF
        JR NZ, jbu_tk_hi
        LD A, 14
jbu_tk_hi:
        CP 15
        JR C, jbu_tk_set
        XOR A
jbu_tk_set:
        LD (GAME + G_JB_TRK), A
        CALL MusicPlay
        JP DrawJukeboxMenu

jbu_adj_sfx:
        LD A, (GAME + G_JB_SFX)
        DEC A
        ADD A, C
        CP $FF
        JR NZ, jbu_sx_hi
        LD A, 15
jbu_sx_hi:
        CP 16
        JR C, jbu_sx_set
        XOR A
jbu_sx_set:
        INC A
        LD (GAME + G_JB_SFX), A
        CALL SfxPlayForce
        JP DrawJukeboxMenu

jbu_b1:
        LD A, (INP_EDGE)
        BIT 4, A
        RET Z
        LD A, (GAME + G_JB_CUR)
        CP 2
        JR NZ, jbu_b1_sfx
        LD A, (GAME + G_JB_TRK)
        JP MusicPlay
jbu_b1_sfx:
        CP 3
        JR NZ, jbu_b1_launch
        LD A, (GAME + G_JB_SFX)
        JP SfxPlayForce
jbu_b1_launch:
        ; Launch directly into the chosen stage & loop with 3 lives!
        LD HL, GAME + G_SCORE0
        XOR A
        LD (HL), A
        INC HL
        LD (HL), A
        INC HL
        LD (HL), A
        LD (GAME + G_1UP_AWARDED), A
        LD (GAME + G_PAUSE), A
        LD A, 3
        LD (GAME + G_LIVES), A
        ; Set mode=2 if stage>=4 else mode=1 so subsequent progression continues!
        LD A, (GAME + G_STAGE_ID)
        CP 4
        JR NC, jbu_go_rmx
        LD (GAME + G_STAGE_SEQ), A
        LD A, 1
        LD (GAME + G_MODE), A
        JP HowHighScreen
jbu_go_rmx:
        SUB 4
        LD (GAME + G_STAGE_SEQ), A
        LD A, 2
        LD (GAME + G_MODE), A
        JP HowHighScreen

StartAttractDemo:
        LD A, (GAME + G_DEMO_IDX)
        AND 3
        LD B, A
        INC A
        AND 3
        LD (GAME + G_DEMO_IDX), A

        ; Look up demo stage ID (0..3) and demo script pointer
        LD E, B
        LD D, 0
        LD HL, DEMO_STAGE_TABLE
        ADD HL, DE
        LD A, (HL)
        LD (GAME + G_STAGE_ID), A
        XOR A
        LD (GAME + G_LOOP), A

        LD A, B
        ADD A, A
        LD E, A
        LD HL, DEMO_SCRIPT_TABLE
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        LD (GAME + G_DEMO_PTR), DE

        XOR A
        LD (GAME + G_DEMO_T), A
        LD (GAME + G_DEMO_MASK), A
        CALL LoadStageByID
        LD A, GS_DEMO
        LD (GAME + G_STATE), A
        LD HL, VRAM_NAME + (2 * NAME_COLS) + 7
        LD DE, txt_demo
        JP DrawText

; ============================================================================
;  Stage Progression & "HOW HIGH CAN YOU GET ?" Intermission
; ============================================================================
ResolveCurrentStage:
        LD A, (GAME + G_MODE)
        CP 1
        JR Z, rcs_jp
        CP 2
        JR Z, rcs_remix
        ; Mode 0: Authentic US Arcade 2->3->4->5 stage progression ($3A65)
        LD A, (GAME + G_LOOP)
        CP 4
        JR C, rcs_us_ok
        LD A, 4
rcs_us_ok:
        ADD A, A
        LD L, A
        LD H, 0
        LD DE, PROG_US_TABLE
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        EX DE, HL
        JR rcs_lookup
rcs_jp:
        LD HL, PROG_JP
        JR rcs_lookup
rcs_remix:
        LD HL, PROG_REMIX
rcs_lookup:
        LD A, (GAME + G_STAGE_SEQ)
        LD E, A
        LD D, 0
        ADD HL, DE
        LD A, (HL)
        CP $FF
        JR NZ, rcs_set
        ; End of level sequence -> advance loop!
        XOR A
        LD (GAME + G_STAGE_SEQ), A
        LD A, (GAME + G_LOOP)
        INC A
        LD (GAME + G_LOOP), A
        JR ResolveCurrentStage
rcs_set:
        LD (GAME + G_STAGE_ID), A
        RET

HowHighScreen:
        LD HL, ART_HOWHIGH_DESC
        CALL LoadArtScreen
        CALL DrawHUD

        ; Peek height_idx from selected stage record
        LD A, (GAME + G_STAGE_ID)
        ADD A, A
        LD L, A
        LD H, 0
        LD DE, STAGE_TABLE
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        PUSH DE
        POP IX
        LD C, (IX + L_HEIGHT_IDX)   ; 0..3 (25m..100m)

        ; Draw height labels up to C+1 tiers
        LD HL, VRAM_NAME + (18 * NAME_COLS) + 2
        LD DE, txt_25m
        PUSH BC
        CALL DrawText
        POP BC
        LD A, C
        OR A
        JR Z, hh_prompt
        LD HL, VRAM_NAME + (14 * NAME_COLS) + 2
        LD DE, txt_50m
        PUSH BC
        CALL DrawText
        POP BC
        LD A, C
        CP 2
        JR C, hh_prompt
        LD HL, VRAM_NAME + (10 * NAME_COLS) + 2
        LD DE, txt_75m
        PUSH BC
        CALL DrawText
        POP BC
        LD A, C
        CP 3
        JR C, hh_prompt
        LD HL, VRAM_NAME + (6 * NAME_COLS) + 1
        LD DE, txt_100m
        CALL DrawText

hh_prompt:
        LD HL, VRAM_NAME + (23 * NAME_COLS) + 5
        LD DE, txt_howhigh
        CALL DrawText

        LD A, 130
        LD (GAME + G_STATE_T), A
        LD A, GS_HOWHIGH
        LD (GAME + G_STATE), A
        LD A, TRK_MUS_HOWHIGH
        JP MusicPlay

HowHighUpdate:
        LD A, (GAME + G_STATE_T)
        CP 110
        JR NC, hhu_tick
        LD A, (INP_EDGE)
        AND $30
        JR NZ, hhu_go
hhu_tick:
        LD A, (GAME + G_STATE_T)
        DEC A
        LD (GAME + G_STATE_T), A
        RET NZ
hhu_go:
        CALL LoadStageByID
        LD A, GS_PLAY
        LD (GAME + G_STATE), A
        RET

; ============================================================================
;  Stage Loading & Tilemap Construction
; ============================================================================
LoadStageByID:
        LD A, (GAME + G_STAGE_ID)
        ADD A, A
        LD L, A
        LD H, 0
        LD DE, STAGE_TABLE
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        EX DE, HL
        LD DE, LEVELBUF
        LD BC, L_SIZE
        LDIR

        ; Clear dynamic entities & collision map
        LD HL, SOLID
        LD B, 96
        XOR A
lsb_s:  LD (HL), A
        INC HL
        DJNZ lsb_s

        LD HL, ENEMIES
        LD B, 96
lsb_e:  LD (HL), A
        INC HL
        DJNZ lsb_e

        LD HL, ITEMS_TAKEN
        LD B, 16                ; clears ITEMS_TAKEN (8) + RIVETS_PULLED (8)
lsb_ir: LD (HL), A
        INC HL
        DJNZ lsb_ir

        ; Player init
        LD A, (LEVELBUF + L_MARIOX)
        ADD A, A
        ADD A, A
        ADD A, A
        LD (PLAYER + P_X), A
        LD A, (LEVELBUF + L_MARIOY)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD (PLAYER + P_Y), A
        XOR A
        LD (PLAYER + P_YSUB), A
        LD (PLAYER + P_VY), A
        LD (PLAYER + P_STATE), A
        LD (PLAYER + P_ANIM), A
        LD (PLAYER + P_STEP_T), A
        LD (PLAYER + P_JUMP_CNT), A
        LD A, 1                 ; PF_GROUNDED = 1, facing right
        LD (PLAYER + P_FLAGS), A

        ; DK init
        LD A, (LEVELBUF + L_DKX)
        ADD A, A
        ADD A, A
        ADD A, A
        LD (DK + D_X), A
        LD A, (LEVELBUF + L_DKY)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD (DK + D_Y), A
        XOR A
        LD (DK + D_POSE), A
        LD (DK + D_FRAME), A
        LD A, 1
        LD (DK + D_DIR), A
        LD A, 35
        LD (DK + D_TIMER), A

        ; Stage parameters + loop speed scaling
        LD A, (LEVELBUF + L_TYPE)
        LD (GAME + G_LEVELTYPE), A
        LD A, (LEVELBUF + L_BONUS)
        LD B, A
        LD A, (GAME + G_LOOP)
        CP 4
        JR C, lsb_badd
        LD A, 3
lsb_badd:
        RLCA
        RLCA
        RLCA
        RLCA
        ADD A, B
        DAA
        LD (GAME + G_BONUS), A
        LD A, (LEVELBUF + L_BONUS + 1)
        LD (GAME + G_BONUS + 1), A
        LD A, 120
        LD (GAME + G_BONUS_T), A

        ; Scale spawn interval faster per loop (min 48 frames)
        LD A, (LEVELBUF + L_BARREL)
        LD B, A
        LD A, (GAME + G_LOOP)
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, A                ; loop * 16
        LD C, A
        LD A, B
        SUB C
        JR NC, lsb_sp_min
        LD A, 48
lsb_sp_min:
        CP 48
        JR NC, lsb_sp_ok
        LD A, 48
lsb_sp_ok:
        LD (GAME + G_SPAWN_INT), A

        XOR A
        LD (GAME + G_HAMMER_TIME), A
        LD (GAME + G_RIVETS), A
        LD (GAME + G_CONV_DIR), A
        LD (GAME + G_FIRE_CNT), A
        LD (GAME + G_POP_T), A
        LD (GAME + G_PAUSE), A
        LD A, 180
        LD (GAME + G_CONV_T), A

        ; Oil starts unlit on 25m until first barrel hits, lit immediately on 50m!
        LD A, (GAME + G_LEVELTYPE)
        CP LT_PIES
        LD A, 0
        JR NZ, lsb_oil
        LD A, 1
lsb_oil:
        LD (GAME + G_OIL_LIT), A

        ; Load stage tileset & build tilemap
        LD A, (LEVELBUF + L_GFXBANK)
        CALL LoadStageGfx
        CALL BuildStageMap
        LD A, (GAME + G_LEVELTYPE)
        CP LT_ELEVATORS
        CALL Z, InitElevators
        LD A, (GAME + G_LEVELTYPE)
        CP LT_RIVETS
        CALL Z, SpawnInitialRivetFire

        CALL DrawHUD
        CALL BuildSprites
        CALL VdpDisplayOn

        LD A, (LEVELBUF + L_BGM)
        JP MusicPlay

BuildStageMap:
        LD HL, VRAM_NAME
        LD DE, 768
        CALL VdpClear

        ; 1. Platforms -> SOLID + tiles
        LD A, (LEVELBUF + L_NPLAT)
        OR A
        JR Z, bsm_lads
        LD B, A
        LD IX, LEVELBUF + L_PLAT
bsm_plp:
        PUSH BC
        LD B, (IX + 0)          ; col_start
        LD C, (IX + 2)          ; row
bsm_pcol:
        LD A, 1
        CALL SetSolid
        ; Choose tile (conveyor vs girder)
        LD A, (IX + 3)
        AND PF_CONV_R | PF_CONV_L
        JR Z, bsm_gird
        LD A, B
        CP (IX + 0)
        JR NZ, bsm_chk_cr
        LD A, T_CONVEYOR_L
        JR bsm_putp
bsm_chk_cr:
        CP (IX + 1)
        JR NZ, bsm_cmid
        LD A, T_CONVEYOR_R
        JR bsm_putp
bsm_cmid:
        LD A, T_CONVEYOR
        JR bsm_putp
bsm_gird:
        LD A, T_GIRDER
bsm_putp:
        CALL TilePut
        LD A, B
        CP (IX + 1)
        JR NC, bsm_pnext
        INC B
        JR bsm_pcol
bsm_pnext:
        LD DE, 4
        ADD IX, DE
        POP BC
        DJNZ bsm_plp

bsm_lads:
        ; 2. Ladders (normal, broken, decorative)
        LD A, (LEVELBUF + L_NLADDER)
        OR A
        JR Z, bsm_rivs
        LD B, A
        LD IX, LEVELBUF + L_LADDERS
bsm_llp:
        PUSH BC
        LD B, (IX + 0)          ; col
        LD C, (IX + 1)          ; rtop
        LD D, (IX + 2)          ; rbot
        LD E, (IX + 3)          ; flags
bsm_lrow:
        LD A, C
        CP D
        JR NC, bsm_lnext
        LD A, E
        CP LF_BROKEN
        JR NZ, bsm_lfull
        ; Broken ladder: draw top rung & bottom stub, leave middle empty!
        LD A, C
        CP (IX + 1)
        JR Z, bsm_lstub
        INC A
        CP D
        JR Z, bsm_lstub
        JR bsm_ladv
bsm_lstub:
        LD A, T_LADDER_BROKEN
        CALL TilePut
        JR bsm_ladv
bsm_lfull:
        LD A, T_LADDER
        CALL TilePut
bsm_ladv:
        INC C
        JR bsm_lrow
bsm_lnext:
        LD DE, 4
        ADD IX, DE
        POP BC
        DJNZ bsm_llp

bsm_rivs:
        ; 3. Rivets (100m)
        LD A, (LEVELBUF + L_NRIVET)
        OR A
        JR Z, bsm_oil
        LD B, A
        LD IX, LEVELBUF + L_RIVETS
bsm_rlp:
        PUSH BC
        LD B, (IX + 0)
        LD C, (IX + 1)
        LD A, T_RIVET
        CALL TilePut
        LD DE, 2
        ADD IX, DE
        POP BC
        DJNZ bsm_rlp

bsm_oil:
        ; 4. Oil Drum (2x2) + 50m X-truss support if present
        LD A, (LEVELBUF + L_OILX)
        CP $FF
        JR Z, bsm_stack
        LD B, A
        LD A, (LEVELBUF + L_OILY)
        LD C, A
        LD A, T_OILCAN
        CALL TilePut
        INC B
        LD A, T_OILCAN + 1
        CALL TilePut
        DEC B
        INC C
        LD A, T_OILCAN + 2
        CALL TilePut
        INC B
        LD A, T_OILCAN + 3
        CALL TilePut

        ; On 50m, draw the iconic central XXX truss pedestal underneath!
        LD A, (GAME + G_LEVELTYPE)
        CP LT_PIES
        JR NZ, bsm_stack
        LD A, (LEVELBUF + L_OILY)
        ADD A, 3
        LD C, A
        LD D, 3
bsm_truss:
        LD A, (LEVELBUF + L_OILX)
        DEC A
        LD B, A
        LD E, 4
bsm_tx:
        LD A, T_TRUSS_X
        CALL TilePut
        INC B
        DEC E
        JR NZ, bsm_tx
        INC C
        DEC D
        JR NZ, bsm_truss

bsm_stack:
        ; 5. Upright Barrel Stack beside DK (2x2)
        LD A, (LEVELBUF + L_STACKX)
        CP $FF
        JR Z, bsm_items
        LD B, A
        LD A, (LEVELBUF + L_STACKY)
        LD C, A
        LD A, T_BARREL_STACK
        CALL TilePut
        INC B
        LD A, T_BARREL_STACK + 1
        CALL TilePut
        DEC B
        INC C
        LD A, T_BARREL_STACK + 2
        CALL TilePut
        INC B
        LD A, T_BARREL_STACK + 3
        CALL TilePut

bsm_items:
        ; 6. Bonus items & hammers
        LD A, (LEVELBUF + L_NITEMS)
        OR A
        RET Z
        LD B, A
        LD IX, LEVELBUF + L_ITEMS
bsm_ilp:
        PUSH BC
        LD B, (IX + 0)
        LD C, (IX + 1)
        LD A, (IX + 2)
        CALL TilePut
        LD DE, 3
        ADD IX, DE
        POP BC
        DJNZ bsm_ilp
        RET

; ============================================================================
;  HUD Rendering
; ============================================================================
DrawHUD:
        CALL DrawTopScoreBar
        LD HL, VRAM_NAME + NAME_COLS + 1
        LD DE, txt_hud2
        CALL DrawText
        JP UpdateHUD

UpdateHUD:
        LD HL, VRAM_NAME + 5
        LD DE, GAME + G_SCORE0
        LD B, 3
        CALL DrawDigits
        LD HL, VRAM_NAME + 21
        LD DE, GAME + G_HS0
        LD B, 3
        CALL DrawDigits

        ; Mario life icon + lives count
        LD B, 1
        LD C, 1
        LD A, T_LIFE_ICON
        CALL TilePut
        LD A, (GAME + G_LIVES)
        CP 10
        JR C, uh_lok
        LD A, 9
uh_lok:
        ADD A, '0'
        LD B, 3
        LD C, 1
        CALL TilePutChar

        ; Loop number L=01..99
        LD A, (GAME + G_LOOP)
        INC A
        CP 10
        JR C, uh_l1
        LD A, 9
uh_l1:
        ADD A, '0'
        LD B, 9
        LD C, 1
        CALL TilePutChar

        ; 4-digit Bonus timer
        LD HL, VRAM_NAME + NAME_COLS + 22
        LD DE, GAME + G_BONUS
        LD B, 2
        JP DrawDigits

; ============================================================================
;  Active Gameplay & Attract Demo Updates
; ============================================================================
DemoUpdate:
        ; Any button exits demo back to Title immediately
        LD A, (INP_EDGE)
        AND $3F
        JP NZ, TitleScreen

        ; Feed synthetic inputs from DEMO_SCRIPT
        LD A, (GAME + G_DEMO_T)
        OR A
        JR NZ, dmu_apply
        LD HL, (GAME + G_DEMO_PTR)
        LD A, (HL)
        OR A
        JP Z, TitleScreen
        LD (GAME + G_DEMO_T), A
        INC HL
        LD A, (HL)
        LD (GAME + G_DEMO_MASK), A
        INC HL
        LD (GAME + G_DEMO_PTR), HL
dmu_apply:
        LD A, (GAME + G_DEMO_T)
        DEC A
        LD (GAME + G_DEMO_T), A
        LD A, (GAME + G_DEMO_MASK)
        LD B, A
        LD (INP_HELD), A
        LD A, (SCRATCH + 43)
        XOR B
        AND B
        LD (INP_EDGE), A
        LD A, B
        LD (SCRATCH + 43), A
        JR PlayStepCommon

PlayUpdate:
        ; Handle NMI Pause overlay & chime
        LD A, (GAME + G_PAUSE)
        LD B, A
        LD A, (GAME + G_PAUSE_PREV)
        CP B
        JR Z, pu_chk_paused
        LD A, B
        LD (GAME + G_PAUSE_PREV), A
        CALL SoundPause
        LD A, (GAME + G_PAUSE)
        OR A
        JR Z, pu_clr_pause
        LD HL, VRAM_NAME + (2 * NAME_COLS) + 13
        LD DE, txt_paused
        JP DrawText
pu_clr_pause:
        LD HL, VRAM_NAME + (2 * NAME_COLS) + 13
        LD DE, txt_pause_clr
        CALL DrawText
pu_chk_paused:
        LD A, (GAME + G_PAUSE)
        OR A
        RET NZ

PlayStepCommon:
        CALL UpdateTimersAndBGM
        CALL AnimateStageTiles
        CALL UpdateElevators
        CALL UpdatePlayer
        LD A, (GAME + G_STATE)
        CP GS_PLAY
        JR Z, psc_cont
        CP GS_DEMO
        RET NZ
psc_cont:
        CALL UpdateDK
        CALL UpdateEnemies
        CALL UpdateRivets
        CALL UpdateItems
        CALL Collide
        CALL BuildSprites
        JP UpdateHUD

UpdateTimersAndBGM:
        LD A, (GAME + G_FRAME)
        INC A
        LD (GAME + G_FRAME), A

        ; Floating score popup timer
        LD A, (GAME + G_POP_T)
        OR A
        JR Z, utb_ham
        DEC A
        LD (GAME + G_POP_T), A
        AND 3
        JR NZ, utb_ham
        LD A, (GAME + G_POP_Y)
        DEC A
        LD (GAME + G_POP_Y), A

utb_ham:
        LD A, (GAME + G_HAMMER_TIME)
        OR A
        JR Z, utb_conv
        DEC A
        LD (GAME + G_HAMMER_TIME), A

utb_conv:
        ; Reverse conveyor direction every 240 frames
        LD A, (GAME + G_CONV_T)
        DEC A
        LD (GAME + G_CONV_T), A
        JR NZ, utb_bonus
        LD A, 240
        LD (GAME + G_CONV_T), A
        LD A, (GAME + G_CONV_DIR)
        XOR 1
        LD (GAME + G_CONV_DIR), A

utb_bonus:
        ; Bonus timer ticks down -100 every 120 frames (2.0s)
        LD A, (GAME + G_BONUS_T)
        DEC A
        LD (GAME + G_BONUS_T), A
        JR NZ, utb_bgm
        LD A, 120
        LD (GAME + G_BONUS_T), A
        LD A, (GAME + G_BONUS)
        OR A
        JR Z, utb_timeup
        SUB $01
        DAA
        LD (GAME + G_BONUS), A
        OR A
        JR NZ, utb_bgm
utb_timeup:
        CALL KillPlayer
        RET

utb_bgm:
        ; Dynamic music priority: Hammer > Hurry (<1000) > Stage BGM
        LD A, (GAME + G_HAMMER_TIME)
        OR A
        JR Z, utb_noham
        LD A, TRK_BGM_HAMMER
        JP MusicPlayIfNew
utb_noham:
        LD A, (GAME + G_BONUS)
        CP $10
        JR NC, utb_norm
        LD A, TRK_BGM_HURRY
        JP MusicPlayIfNew
utb_norm:
        LD A, (LEVELBUF + L_BGM)
        JP MusicPlayIfNew

AnimateStageTiles:
        ; Flicker oil-drum flame if lit
        LD A, (GAME + G_OIL_LIT)
        OR A
        JR Z, ast_conv
        LD A, (LEVELBUF + L_OILX)
        CP $FF
        JR Z, ast_conv
        LD B, A
        LD A, (LEVELBUF + L_OILY)
        DEC A
        LD C, A
        LD A, (GAME + G_FRAME)
        BIT 2, A
        LD A, T_OILFIRE_A
        JR Z, ast_f1
        LD A, T_OILFIRE_B
ast_f1:
        CALL TilePut
        INC B
        XOR T_OILFIRE_A ^ T_OILFIRE_B
        CALL TilePut

ast_conv:
        ; Animate conveyor rollers every 8 frames on conveyor stages
        LD A, (GAME + G_FRAME)
        AND 7
        RET NZ
        LD A, (LEVELBUF + L_NPLAT)
        OR A
        RET Z
        LD B, A
        LD IX, LEVELBUF + L_PLAT
ast_plp:
        PUSH BC
        LD A, (IX + 3)
        AND PF_CONV_R | PF_CONV_L
        JR Z, ast_pnxt
        LD B, (IX + 0)
        INC B
        LD C, (IX + 2)
ast_col:
        LD A, B
        CP (IX + 1)
        JR NC, ast_pnxt
        LD A, (GAME + G_FRAME)
        BIT 3, A
        LD A, T_CONVEYOR
        JR Z, ast_put
        LD A, T_CONVEYOR_ALT
ast_put:
        CALL TilePut
        INC B
        JR ast_col
ast_pnxt:
        LD DE, 4
        ADD IX, DE
        POP BC
        DJNZ ast_plp
        RET

; ============================================================================
;  Elevators (4 Wrapping Cars on Dual Cable Shafts - Stage 3 & Remix 3)
; ============================================================================
InitElevators:
        ; Draw static cable columns + top/bottom pulleys
        LD A, (LEVELBUF + L_ELEVC0)
        CP $FF
        RET Z
        LD B, A
        CALL DrawCableShaft
        LD A, (LEVELBUF + L_ELEVC1)
        LD B, A
        CALL DrawCableShaft

        ; Car 0 & 1 in left shaft (rising), Car 2 & 3 in right shaft (descending)
        LD IX, ELEV
        LD A, (LEVELBUF + L_ELEVC0)
        LD (IX + EL_COL), A
        LD (IX + EL_ROW), 19
        LD (IX + EL_DY), -1
        LD (IX + EL_MIN), 8
        LD (IX + EL_MAX), 20
        LD (IX + EL_TIMER), 14

        LD DE, EL_SIZE
        ADD IX, DE
        LD A, (LEVELBUF + L_ELEVC0)
        LD (IX + EL_COL), A
        LD (IX + EL_ROW), 13
        LD (IX + EL_DY), -1
        LD (IX + EL_MIN), 8
        LD (IX + EL_MAX), 20
        LD (IX + EL_TIMER), 14

        ADD IX, DE
        LD A, (LEVELBUF + L_ELEVC1)
        LD (IX + EL_COL), A
        LD (IX + EL_ROW), 9
        LD (IX + EL_DY), 1
        LD (IX + EL_MIN), 8
        LD (IX + EL_MAX), 20
        LD (IX + EL_TIMER), 14

        ADD IX, DE
        LD A, (LEVELBUF + L_ELEVC1)
        LD (IX + EL_COL), A
        LD (IX + EL_ROW), 15
        LD (IX + EL_DY), 1
        LD (IX + EL_MIN), 8
        LD (IX + EL_MAX), 20
        LD (IX + EL_TIMER), 14

        ; Stamp initial elevator cars
        LD IX, ELEV
        LD B, 4
ie_draw:
        PUSH BC
        CALL StampElevatorCar
        LD DE, EL_SIZE
        ADD IX, DE
        POP BC
        DJNZ ie_draw
        RET

; B = shaft col
DrawCableShaft:
        LD C, 6
        LD A, T_PULLEY_TOP
        CALL TilePut
        LD C, 7
dcs_lp:
        LD A, T_CABLE
        CALL TilePut
        INC C
        LD A, C
        CP 22
        JR C, dcs_lp
        LD A, T_PULLEY_BOT
        JP TilePut

StampElevatorCar:
        LD B, (IX + EL_COL)
        LD C, (IX + EL_ROW)
        LD A, T_ELEVATOR
        CALL TilePut
        LD A, 1
        CALL SetSolid
        INC B
        LD A, T_ELEVATOR + 1
        CALL TilePut
        LD A, 1
        JP SetSolid

EraseElevatorCar:
        LD B, (IX + EL_COL)
        LD C, (IX + EL_ROW)
        LD A, T_CABLE
        CALL TilePut
        XOR A
        CALL SetSolid
        INC B
        LD A, T_BLANK
        CALL TilePut
        XOR A
        JP SetSolid

UpdateElevators:
        LD A, (GAME + G_LEVELTYPE)
        CP LT_ELEVATORS
        RET NZ
        LD IX, ELEV
        LD B, 4
ue_lp:
        PUSH BC
        CALL UpdateOneElevator
        LD DE, EL_SIZE
        ADD IX, DE
        POP BC
        DJNZ ue_lp
        RET

UpdateOneElevator:
        LD A, (IX + EL_TIMER)
        DEC A
        LD (IX + EL_TIMER), A
        RET NZ
        LD A, 14
        LD (IX + EL_TIMER), A

        ; Check if Mario is standing on this car before moving it!
        LD E, 0                 ; E = 1 if carrying Mario
        LD A, (PLAYER + P_X)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        LD B, (IX + EL_COL)
        CP B
        JR Z, uoe_yck
        INC B
        CP B
        JR NZ, uoe_step
uoe_yck:
        LD A, (IX + EL_ROW)
        ADD A, A
        ADD A, A
        ADD A, A
        LD C, A                 ; car surface Y in pixels
        LD A, (PLAYER + P_Y)
        ADD A, 16
        SUB C
        CALL Abs
        CP 5
        JR NC, uoe_step
        LD E, 1

uoe_step:
        PUSH DE
        CALL EraseElevatorCar
        POP DE

        ; Advance row and wrap at bounds
        LD A, (IX + EL_ROW)
        ADD A, (IX + EL_DY)
        LD C, A
        LD A, (IX + EL_DY)
        BIT 7, A
        JR Z, uoe_down
        ; Moving up: wrap if C < EL_MIN
        LD A, C
        CP (IX + EL_MIN)
        JR NC, uoe_setr
        LD C, (IX + EL_MAX)
        LD E, 0                 ; Mario drops off if riding into top pulley!
        JR uoe_setr
uoe_down:
        LD A, (IX + EL_MAX)
        CP C
        JR NC, uoe_setr
        LD C, (IX + EL_MIN)
        LD E, 0
uoe_setr:
        LD (IX + EL_ROW), C
        PUSH DE
        CALL StampElevatorCar
        POP DE
        LD A, E
        OR A
        RET Z
        ; Snap Mario onto the moved elevator car
        LD A, (IX + EL_ROW)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD (PLAYER + P_Y), A
        XOR A
        LD (PLAYER + P_YSUB), A
        LD (PLAYER + P_VY), A
        RET

; ============================================================================
;  Player Physics, Conveyor Drift, Ladders & Hammer
; ============================================================================
UpdatePlayer:
        LD A, (PLAYER + P_STATE)
        CP PS_DEAD
        RET Z
        CP PS_WIN
        RET Z
        CP PS_CLIMB
        JP Z, pl_climb_update

        ; ---- 1. Horizontal input (1 px/frame) ----
        LD B, 0
        LD A, (INP_HELD)
        BIT 2, A                ; Left
        JR Z, pl_chk_r
        LD B, -1
        LD A, (PLAYER + P_FLAGS)
        SET PF_LEFT, A
        LD (PLAYER + P_FLAGS), A
        JR pl_hmove
pl_chk_r:
        BIT 3, A                ; Right
        JR Z, pl_hmove
        LD B, 1
        LD A, (PLAYER + P_FLAGS)
        RES PF_LEFT, A
        LD (PLAYER + P_FLAGS), A

pl_hmove:
        LD A, (PLAYER + P_X)
        ADD A, B
        CP 241
        JR C, pl_xset
        BIT 7, B
        LD A, 0
        JR NZ, pl_xset
        LD A, 240
pl_xset:
        LD (PLAYER + P_X), A

        ; Walking step SFX + anim when grounded & moving
        LD A, B
        OR A
        JR Z, pl_conv_push
        LD A, (PLAYER + P_FLAGS)
        BIT PF_GROUNDED, A
        JR Z, pl_conv_push
        LD A, (PLAYER + P_ANIM)
        INC A
        LD (PLAYER + P_ANIM), A
        AND 15
        CALL Z, SoundStep

pl_conv_push:
        ; ---- 2. Conveyor belt drift (0.5 px/frame when grounded) ----
        LD A, (PLAYER + P_FLAGS)
        BIT PF_GROUNDED, A
        JR Z, pl_chk_jump
        LD A, (GAME + G_FRAME)
        AND 1
        JR NZ, pl_chk_jump
        CALL GetConveyorPush
        OR A
        JR Z, pl_chk_jump
        LD B, A
        LD A, (PLAYER + P_X)
        ADD A, B
        CP 240
        JR NC, pl_chk_jump
        LD (PLAYER + P_X), A

pl_chk_jump:
        ; ---- 3. Jump (disabled while holding Hammer, just like arcade!) ----
        LD A, (GAME + G_HAMMER_TIME)
        OR A
        JR NZ, pl_gravity
        LD A, (INP_EDGE)
        AND $30
        JR Z, pl_gravity
        LD A, (PLAYER + P_FLAGS)
        BIT PF_GROUNDED, A
        JR Z, pl_gravity
        LD A, -17               ; -17 eighths -> 17.5 px peak, 34-frame arc!
        LD (PLAYER + P_VY), A
        XOR A
        LD (PLAYER + P_YSUB), A
        LD (PLAYER + P_JUMP_CNT), A
        LD A, (PLAYER + P_FLAGS)
        RES PF_GROUNDED, A
        LD (PLAYER + P_FLAGS), A
        LD A, PS_JUMP
        LD (PLAYER + P_STATE), A
        CALL SoundJump

pl_gravity:
        ; ---- 4. Subpixel 1/8th Gravity (strictly signed!) ----
        LD A, (PLAYER + P_VY)
        INC A
        JP M, pl_vy_store
        CP 25
        JR C, pl_vy_store
        LD A, 24
pl_vy_store:
        LD (PLAYER + P_VY), A

        ; Add signed P_VY to 16-bit (P_Y * 8 + P_YSUB)
        LD E, A
        RLCA
        SBC A, A
        LD D, A                 ; DE = sign-extended P_VY
        LD A, (PLAYER + P_Y)
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD A, (PLAYER + P_YSUB)
        AND 7
        OR L
        LD L, A
        ADD HL, DE
        BIT 7, H
        JR Z, pl_ypos_ok
        LD HL, 0
pl_ypos_ok:
        LD A, L
        AND 7
        LD (PLAYER + P_YSUB), A
        SRL H
        RR L
        SRL H
        RR L
        SRL H
        RR L
        LD A, L
        LD (PLAYER + P_Y), A

        ; ---- 5. Ground landing (only when P_VY >= 0!) ----
        LD A, (PLAYER + P_VY)
        BIT 7, A
        JR NZ, pl_airborne

        LD A, (PLAYER + P_X)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        LD B, A                 ; center column
        LD A, (PLAYER + P_Y)
        ADD A, 16
        LD E, A                 ; feet Y in pixels
        SRL A
        SRL A
        SRL A
        LD C, A                 ; feet tile row
        CALL SolidAt
        OR A
        JR Z, pl_airborne
        ; Snap only if feet are within top 6 pixels of this solid row!
        LD A, C
        ADD A, A
        ADD A, A
        ADD A, A
        LD D, A                 ; row * 8
        LD A, E
        SUB D
        CP 7
        JR NC, pl_airborne

        ; Landed!
        LD A, D
        SUB 16
        LD (PLAYER + P_Y), A
        XOR A
        LD (PLAYER + P_YSUB), A
        LD (PLAYER + P_VY), A
        LD A, (PLAYER + P_FLAGS)
        SET PF_GROUNDED, A
        LD (PLAYER + P_FLAGS), A
        JR pl_chk_ladder

pl_airborne:
        LD A, (PLAYER + P_FLAGS)
        RES PF_GROUNDED, A
        LD (PLAYER + P_FLAGS), A

pl_chk_ladder:
        ; ---- 6. Ladder Grab (only when not holding Hammer!) ----
        LD A, (GAME + G_HAMMER_TIME)
        OR A
        JR NZ, pl_set_ground_state
        LD A, (INP_HELD)
        AND $03
        JR Z, pl_set_ground_state
        CALL TryGrabLadder
        LD A, (PLAYER + P_STATE)
        CP PS_CLIMB
        RET Z

pl_set_ground_state:
        LD A, (PLAYER + P_FLAGS)
        BIT PF_GROUNDED, A
        JR Z, pl_chk_pit
        LD A, (INP_HELD)
        AND $0C
        JR Z, pl_idle
        LD A, PS_RUN
        LD (PLAYER + P_STATE), A
        JR pl_chk_pit
pl_idle:
        LD A, PS_STAND
        LD (PLAYER + P_STATE), A

pl_chk_pit:
        LD A, (PLAYER + P_Y)
        CP 178
        RET C
        JP KillPlayer

; Check all normal ladders for column proximity & directional Y range
TryGrabLadder:
        LD A, (LEVELBUF + L_NLADDER)
        OR A
        RET Z
        LD B, A
        LD IX, LEVELBUF + L_LADDERS
tgl_loop:
        PUSH BC
        LD A, (IX + 3)
        CP LF_NORMAL
        JR NZ, tgl_next

        ; Horizontal check: |(P_X + 8) - (lad_col*8 + 4)| <= 5
        LD A, (IX + 0)
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, 4
        LD C, A
        LD A, (PLAYER + P_X)
        ADD A, 8
        SUB C
        CALL Abs
        CP 6
        JR NC, tgl_next

        ; Compute top_py = rtop*8 - 16, bot_py = rbot*8 - 16
        LD A, (IX + 1)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD D, A                 ; D = top_py
        LD A, (IX + 2)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD E, A                 ; E = bot_py

        LD A, (INP_HELD)
        BIT 0, A                ; Up pressed?
        JR Z, tgl_down
        ; For Up: D < P_Y <= E + 2
        LD A, (PLAYER + P_Y)
        CP D
        JR Z, tgl_next
        JR C, tgl_next
        LD A, E
        ADD A, 2
        LD B, A
        LD A, (PLAYER + P_Y)
        CP B
        JR Z, tgl_grab
        JR C, tgl_grab
        JR tgl_next

tgl_down:
        ; For Down: D - 2 <= P_Y < E
        LD A, D
        SUB 2
        LD B, A
        LD A, (PLAYER + P_Y)
        CP B
        JR C, tgl_next
        CP E
        JR NC, tgl_next

tgl_grab:
        POP BC
        LD A, (IX + 0)
        LD (PLAYER + P_LAD_COL), A
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 4
        LD (PLAYER + P_X), A
        LD A, (IX + 1)
        LD (PLAYER + P_LAD_TOP), A
        LD A, (IX + 2)
        LD (PLAYER + P_LAD_BOT), A
        XOR A
        LD (PLAYER + P_VY), A
        LD (PLAYER + P_YSUB), A
        LD A, PS_CLIMB
        LD (PLAYER + P_STATE), A
        RET

tgl_next:
        LD DE, 4
        ADD IX, DE
        POP BC
        DEC B
        JP NZ, tgl_loop
        RET

pl_climb_update:
        ; Keep centered on ladder
        LD A, (PLAYER + P_LAD_COL)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 4
        LD (PLAYER + P_X), A

        LD A, (INP_HELD)
        BIT 0, A
        JR Z, pcu_dn
        LD A, (PLAYER + P_Y)
        DEC A
        LD (PLAYER + P_Y), A
        JR pcu_anim
pcu_dn:
        BIT 1, A
        JR Z, pcu_bounds
        LD A, (PLAYER + P_Y)
        INC A
        LD (PLAYER + P_Y), A
pcu_anim:
        LD A, (PLAYER + P_ANIM)
        INC A
        LD (PLAYER + P_ANIM), A
        AND 7
        CALL Z, SoundClimb

pcu_bounds:
        ; Reached top girder? (P_Y <= rtop*8 - 16)
        LD A, (PLAYER + P_LAD_TOP)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD B, A
        LD A, (PLAYER + P_Y)
        CP B
        JR Z, pcu_exit_top
        JR NC, pcu_chk_bot
pcu_exit_top:
        LD A, B
        LD (PLAYER + P_Y), A
        JR pcu_dismount

pcu_chk_bot:
        ; Reached bottom girder? (P_Y >= rbot*8 - 16)
        LD A, (PLAYER + P_LAD_BOT)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD B, A
        LD A, (PLAYER + P_Y)
        CP B
        RET C
        LD A, B
        LD (PLAYER + P_Y), A
pcu_dismount:
        XOR A
        LD (PLAYER + P_VY), A
        LD (PLAYER + P_YSUB), A
        LD A, (PLAYER + P_FLAGS)
        SET PF_GROUNDED, A
        LD (PLAYER + P_FLAGS), A
        LD A, PS_STAND
        LD (PLAYER + P_STATE), A
        RET

; Return signed conveyor push (-1, 0, +1) for Mario's current foot position
GetConveyorPush:
        LD A, (PLAYER + P_X)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        LD D, A                 ; D = col
        LD A, (PLAYER + P_Y)
        ADD A, 16
        SRL A
        SRL A
        SRL A
        LD E, A                 ; E = row
        JP ConveyorDirAtDE

; D = col, E = row -> A = -1, 0, or +1
ConveyorDirAtDE:
        LD A, (LEVELBUF + L_NPLAT)
        OR A
        RET Z
        LD B, A
        LD IX, LEVELBUF + L_PLAT
cda_lp:
        LD A, (IX + 2)
        CP E
        JR NZ, cda_nxt
        LD A, D
        CP (IX + 0)
        JR C, cda_nxt
        CP (IX + 1)
        JR Z, cda_hit
        JR NC, cda_nxt
cda_hit:
        LD A, (IX + 3)
        AND PF_CONV_R | PF_CONV_L
        RET Z
        LD C, A
        LD A, (GAME + G_CONV_DIR)
        OR A
        JR Z, cda_norm
        LD A, C
        XOR PF_CONV_R | PF_CONV_L
        LD C, A
cda_norm:
        BIT 0, C                ; PF_CONV_R -> +1, PF_CONV_L -> -1
        LD A, 1
        RET NZ
        LD A, -1
        RET
cda_nxt:
        PUSH DE
        LD DE, 4
        ADD IX, DE
        POP DE
        DJNZ cda_lp
        XOR A
        RET

KillPlayer:
        LD A, (GAME + G_STATE)
        CP GS_DEMO
        JP Z, TitleScreen
        LD A, PS_DEAD
        LD (PLAYER + P_STATE), A
        LD A, 96
        LD (GAME + G_STATE_T), A
        LD A, GS_DYING
        LD (GAME + G_STATE), A
        JP SoundDie

; ============================================================================
;  Donkey Kong Behavior & Stage Hazard Spawners
; ============================================================================
UpdateDK:
        ; Horizontal pacing on 50m Conveyors & 100m Rivets
        LD A, (GAME + G_LEVELTYPE)
        CP LT_PIES
        JR Z, udk_slide
        CP LT_RIVETS
        JR Z, udk_pace
        JR udk_timer

udk_slide:
        LD A, (GAME + G_FRAME)
        AND 1
        JR NZ, udk_timer
        LD A, (DK + D_DIR)
        LD B, A
        LD A, (DK + D_X)
        ADD A, B
        CP 24
        JR C, udk_rev
        CP 208
        JR NC, udk_rev
        LD (DK + D_X), A
        JR udk_timer
udk_pace:
        LD A, (GAME + G_FRAME)
        AND 3
        JR NZ, udk_timer
        LD A, (DK + D_DIR)
        LD B, A
        LD A, (DK + D_X)
        ADD A, B
        CP 96
        JR C, udk_rev
        CP 144
        JR NC, udk_rev
        LD (DK + D_X), A
        JR udk_timer
udk_rev:
        LD A, (DK + D_DIR)
        NEG
        LD (DK + D_DIR), A

udk_timer:
        ; Animate DK pose based on countdown to next throw
        LD A, (DK + D_TIMER)
        DEC A
        LD (DK + D_TIMER), A
        JR Z, udk_fire
        CP 24
        JR NC, udk_idle_anim
        CP 12
        LD A, 3                 ; hold barrel pose
        JR NC, udk_setp
        LD A, 4                 ; throw pose
        JR udk_setp
udk_idle_anim:
        LD A, (GAME + G_FRAME)
        RRCA
        RRCA
        RRCA
        RRCA
        AND 3
        CP 3
        JR NZ, udk_setp
        LD A, 0
udk_setp:
        LD (DK + D_POSE), A
        RET

udk_fire:
        LD A, (GAME + G_SPAWN_INT)
        LD (DK + D_TIMER), A
        LD A, (DK + D_FRAME)
        INC A
        LD (DK + D_FRAME), A

        LD A, (GAME + G_LEVELTYPE)
        CP LT_GIRDERS
        JP Z, SpawnStageBarrel
        CP LT_PIES
        JP Z, SpawnStagePie
        CP LT_ELEVATORS
        JP Z, SpawnStageSpring
        JP SpawnRivetFire

; Find free enemy slot -> IX (Z flag set if none free)
AllocEnemySlot:
        LD IX, ENEMIES
        LD B, MAX_ENEMIES
aes_lp:
        LD A, (IX + E_STATE)
        OR A
        JR Z, aes_ok
        LD DE, 8
        ADD IX, DE
        DJNZ aes_lp
        XOR A                   ; Z = 1 (failed)
        RET
aes_ok:
        LD A, 1                 ; Z = 0 (found)
        OR A
        RET

SpawnStageBarrel:
        CALL AllocEnemySlot
        RET Z
        LD A, 1
        LD (IX + E_STATE), A
        ; Every 4th barrel is a Blue Barrel!
        LD A, (DK + D_FRAME)
        AND 3
        LD B, ET_BARREL
        JR NZ, ssb_type
        LD B, ET_BLUE
ssb_type:
        LD (IX + E_TYPE), B
        LD A, (DK + D_X)
        ADD A, 12
        LD (IX + E_X), A
        LD A, (DK + D_Y)
        ADD A, 8
        LD (IX + E_Y), A
        LD (IX + E_VX), 1
        LD (IX + E_VY), 0
        LD (IX + E_ANIM), 0
        LD (IX + E_DATA), 0
        JP SoundThrow

SpawnStagePie:
        ; Also ensure fireballs emerge from central oil tub up to L_MAX_FIRES!
        LD A, (GAME + G_FIRE_CNT)
        LD B, A
        LD A, (LEVELBUF + L_MAX_FIRES)
        CP B
        JR Z, ssp_pie
        JR C, ssp_pie
        LD A, (DK + D_FRAME)
        AND 1
        JR NZ, ssp_pie
        LD A, (LEVELBUF + L_OILX)
        ADD A, A
        ADD A, A
        ADD A, A
        LD B, A
        LD A, (LEVELBUF + L_OILY)
        ADD A, A
        ADD A, A
        ADD A, A
        LD C, A
        JP SpawnFireAtBC

ssp_pie:
        CALL AllocEnemySlot
        RET Z
        LD (IX + E_STATE), 1
        LD (IX + E_TYPE), ET_PIE
        LD (IX + E_VY), 0
        LD (IX + E_ANIM), 0
        ; Alternate spawning on row 11 (80px) & row 18 (136px), left or right edge
        LD A, (GAME + G_RNG)
        BIT 1, A
        JR Z, ssp_row18
        LD (IX + E_Y), 11 * 8 - 8
        BIT 2, A
        JR Z, ssp_left
        LD (IX + E_X), 29 * 8
        LD (IX + E_VX), -1
        RET
ssp_left:
        LD (IX + E_X), 1 * 8
        LD (IX + E_VX), 1
        RET
ssp_row18:
        LD (IX + E_Y), 18 * 8 - 8
        BIT 2, A
        JR Z, ssp_l18
        LD (IX + E_X), 29 * 8
        LD (IX + E_VX), -1
        RET
ssp_l18:
        LD (IX + E_X), 1 * 8
        LD (IX + E_VX), 1
        RET

SpawnStageSpring:
        CALL AllocEnemySlot
        RET Z
        LD (IX + E_STATE), 1
        LD (IX + E_TYPE), ET_SPRING
        LD A, (DK + D_X)
        ADD A, 8
        LD (IX + E_X), A
        LD A, (LEVELBUF + L_DKY)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 8
        LD (IX + E_Y), A
        LD (IX + E_DATA), 0     ; bounce phase 0..15
        LD (IX + E_VX), 1
        LD (IX + E_VY), 0
        LD (IX + E_ANIM), 0
        JP SoundSpring

SpawnInitialRivetFire:
        LD B, 20 * 8
        LD C, 15 * 8 - 8
        JP SpawnFireAtBC

SpawnRivetFire:
        LD A, (GAME + G_FIRE_CNT)
        LD B, A
        LD A, (LEVELBUF + L_MAX_FIRES)
        CP B
        RET Z
        RET C
        LD B, 24 * 8
        LD C, 19 * 8 - 8
        ; fall through

; B = pixel X, C = pixel Y
SpawnFireAtBC:
        PUSH BC
        CALL AllocEnemySlot
        POP BC
        RET Z
        LD (IX + E_STATE), 1
        LD (IX + E_TYPE), ET_FIRE
        LD (IX + E_X), B
        LD (IX + E_Y), C
        LD A, (GAME + G_RNG)
        BIT 1, A
        LD A, 1
        JR Z, sfb_dir
        LD A, -1
sfb_dir:
        LD (IX + E_VX), A
        LD (IX + E_VY), 0
        LD (IX + E_ANIM), 0
        LD (IX + E_DATA), 0
        LD A, (GAME + G_FIRE_CNT)
        INC A
        LD (GAME + G_FIRE_CNT), A
        RET

; ============================================================================
;  Unified Enemy Update (Barrels, Blue Barrels, Fireballs, Springs, Pies)
; ============================================================================
UpdateEnemies:
        LD IX, ENEMIES
        LD B, MAX_ENEMIES
uen_lp:
        PUSH BC
        LD A, (IX + E_STATE)
        OR A
        CALL NZ, UpdateOneEnemy
        LD DE, 8
        ADD IX, DE
        POP BC
        DJNZ uen_lp
        RET

UpdateOneEnemy:
        ; Preserve bit 7 (jump-scored flag) while advancing anim bits 0..6
        LD A, (IX + E_ANIM)
        LD B, A
        AND $80
        LD C, A
        LD A, B
        INC A
        AND $7F
        OR C
        LD (IX + E_ANIM), A

        LD A, (IX + E_TYPE)
        CP ET_FIRE
        JP Z, EnemyFire
        CP ET_SPRING
        JP Z, EnemySpring
        CP ET_PIE
        JP Z, EnemyPie
        ; Otherwise ET_BARREL or ET_BLUE
        LD A, (IX + E_STATE)
        CP 2
        JP Z, BarrelFalling
        CP 3
        JP Z, BarrelDownLadder

        ; ---- Rolling Barrel ----
        ; Check if aligned over a ladder top (full OR broken!) to shortcut down
        LD A, (IX + E_X)
        AND 7
        JR NZ, brl_roll
        LD A, (IX + E_X)
        SRL A
        SRL A
        SRL A
        LD D, A                 ; D = barrel col
        LD A, (IX + E_Y)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        LD E, A                 ; E = surface row
        CALL CheckBarrelLadderDE
        OR A
        JR Z, brl_roll
        ; E_DATA holds target pixel Y; take ladder with ~35% probability (75% for Blue!)
        LD A, (IX + E_TYPE)
        CP ET_BLUE
        JR Z, brl_take_lad
        LD A, (GAME + G_RNG)
        AND 3
        JR NZ, brl_roll
brl_take_lad:
        LD (IX + E_STATE), 3
        RET

brl_roll:
        ; Advance X (1 px/frame, + extra speed every 4th frame on higher loops)
        LD A, (IX + E_VX)
        LD B, A
        LD A, (IX + E_X)
        ADD A, B
        LD (IX + E_X), A

        ; Check oil drum ignition / bottom screen exit
        CP 3
        JR C, brl_edge
        CP 246
        JR NC, brl_edge

        ; Check oil drum collision if on bottom tier
        LD A, (LEVELBUF + L_OILX)
        CP $FF
        JR Z, brl_chk_floor
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, 8
        LD B, A
        LD A, (IX + E_X)
        SUB B
        CALL Abs
        CP 8
        JR NC, brl_chk_floor
        LD A, (LEVELBUF + L_OILY)
        ADD A, 2
        ADD A, A
        ADD A, A
        ADD A, A
        LD B, A
        LD A, (IX + E_Y)
        ADD A, 8
        CP B
        JR NZ, brl_chk_floor
        ; Barrel hit the Oil Drum!
        LD A, 1
        LD (GAME + G_OIL_LIT), A
        LD A, (GAME + G_FIRE_CNT)
        LD B, A
        LD A, (LEVELBUF + L_MAX_FIRES)
        CP B
        JR Z, brl_kill_oil
        JR C, brl_kill_oil
        LD A, (IX + E_X)
        LD B, A
        LD A, (IX + E_Y)
        LD C, A
        PUSH IX
        CALL SpawnFireAtBC
        POP IX
        CALL SoundThrow
brl_kill_oil:
        LD (IX + E_STATE), 0
        RET

brl_edge:
        ; If near bottom of screen, despawn; otherwise reverse at wall
        LD A, (IX + E_Y)
        CP 156
        JR C, brl_wall_flip
        LD (IX + E_STATE), 0
        RET
brl_wall_flip:
        LD A, (IX + E_VX)
        NEG
        LD (IX + E_VX), A

brl_chk_floor:
        ; Is there still solid girder beneath barrel center?
        LD A, (IX + E_X)
        ADD A, 4
        SRL A
        SRL A
        SRL A
        LD B, A
        LD A, (IX + E_Y)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        LD C, A
        CALL SolidAt
        OR A
        RET NZ
        ; Reached gap at end of girder -> start falling & flip VX for next tier!
        LD (IX + E_STATE), 2
        LD (IX + E_VY), 1
        LD A, (IX + E_VX)
        NEG
        LD (IX + E_VX), A
        RET

BarrelFalling:
        LD A, (IX + E_VY)
        CP 4
        JR NC, bf_vok
        INC A
        LD (IX + E_VY), A
bf_vok:
        LD B, A
        LD A, (IX + E_Y)
        ADD A, B
        LD (IX + E_Y), A
        CP 182
        JR C, bf_land_chk
        LD (IX + E_STATE), 0
        RET
bf_land_chk:
        LD A, (IX + E_X)
        ADD A, 4
        SRL A
        SRL A
        SRL A
        LD B, A
        LD A, (IX + E_Y)
        ADD A, 8
        LD E, A
        SRL A
        SRL A
        SRL A
        LD C, A
        CALL SolidAt
        OR A
        RET Z
        LD A, C
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 8
        LD (IX + E_Y), A
        LD (IX + E_VY), 0
        LD (IX + E_STATE), 1
        RET

BarrelDownLadder:
        LD A, (IX + E_Y)
        INC A
        LD (IX + E_Y), A
        CP (IX + E_DATA)
        RET C
        LD A, (IX + E_DATA)
        LD (IX + E_Y), A
        LD A, (IX + E_VX)
        NEG
        LD (IX + E_VX), A
        LD (IX + E_STATE), 1
        RET

; D = col, E = rtop -> returns A=1 and sets (IX+E_DATA) = rbot*8 - 8 if ladder matches
CheckBarrelLadderDE:
        LD A, (LEVELBUF + L_NLADDER)
        OR A
        RET Z
        LD B, A
        LD HL, LEVELBUF + L_LADDERS
cbl_lp:
        LD A, (HL)
        INC HL
        CP D
        JR NZ, cbl_skip3
        LD A, (HL)              ; rtop
        INC HL
        CP E
        JR NZ, cbl_skip2
        LD C, (HL)              ; rbot
        INC HL
        LD A, (HL)              ; flags
        CP LF_DECOR
        JR Z, cbl_skip1
        LD A, C
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 8
        LD (IX + E_DATA), A
        LD A, 1
        RET
cbl_skip3:
        INC HL
cbl_skip2:
        INC HL
cbl_skip1:
        INC HL
        DJNZ cbl_lp
        XOR A
        RET

; ---- Patrolling & Ladder-Climbing Fireball ----
EnemyFire:
        LD A, (IX + E_STATE)
        CP 3
        JR Z, ef_climb

        ; Move every 2nd frame
        LD A, (GAME + G_FRAME)
        AND 1
        RET NZ

        ; Check if aligned with a normal ladder to chase Mario vertically!
        LD A, (IX + E_X)
        AND 7
        JR NZ, ef_walk
        LD A, (GAME + G_RNG)
        AND 3
        JR NZ, ef_walk
        CALL FireTryLadder
        LD A, (IX + E_STATE)
        CP 3
        RET Z

ef_walk:
        ; Look ahead 1 column so Fireballs stay on girders (don't fall into gaps!)
        LD A, (IX + E_X)
        ADD A, (IX + E_VX)
        CP 4
        JR C, ef_flip
        CP 244
        JR NC, ef_flip
        LD D, A
        ADD A, 4
        SRL A
        SRL A
        SRL A
        LD B, A
        LD A, (IX + E_Y)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        LD C, A
        CALL SolidAt
        OR A
        JR Z, ef_flip
        LD (IX + E_X), D
        RET
ef_flip:
        LD A, (IX + E_VX)
        NEG
        LD (IX + E_VX), A
        RET

ef_climb:
        LD A, (GAME + G_FRAME)
        AND 1
        RET NZ
        LD A, (IX + E_Y)
        ADD A, (IX + E_VY)
        LD (IX + E_Y), A
        CP (IX + E_DATA)
        RET NZ
        LD (IX + E_VY), 0
        LD (IX + E_STATE), 1
        RET

FireTryLadder:
        LD A, (IX + E_X)
        SRL A
        SRL A
        SRL A
        LD D, A                 ; D = col
        LD A, (IX + E_Y)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        LD E, A                 ; E = row
        LD A, (LEVELBUF + L_NLADDER)
        OR A
        RET Z
        LD B, A
        LD HL, LEVELBUF + L_LADDERS
ftl_lp:
        LD A, (HL)
        INC HL
        CP D
        JR NZ, ftl_s3
        LD C, (HL)              ; rtop
        INC HL
        LD A, (HL)              ; rbot
        INC HL
        PUSH AF
        LD A, (HL)              ; flags
        CP LF_NORMAL
        JR NZ, ftl_pop_nxt
        POP AF                  ; A = rbot, C = rtop
        ; If at rbot and Mario is higher -> climb UP!
        CP E
        JR NZ, ftl_chk_top
        LD A, (PLAYER + P_Y)
        CP (IX + E_Y)
        JR NC, ftl_s1
        LD A, C
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 8
        LD (IX + E_DATA), A
        LD (IX + E_VY), -1
        LD (IX + E_STATE), 3
        RET
ftl_chk_top:
        LD A, C
        CP E
        JR NZ, ftl_s1
        LD A, (PLAYER + P_Y)
        CP (IX + E_Y)
        JR C, ftl_s1
        JR Z, ftl_s1
        DEC HL
        LD A, (HL)              ; rbot
        INC HL
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 8
        LD (IX + E_DATA), A
        LD (IX + E_VY), 1
        LD (IX + E_STATE), 3
        RET
ftl_pop_nxt:
        POP AF
        JR ftl_s1
ftl_s3: INC HL
        INC HL
ftl_s1: INC HL
        DJNZ ftl_lp
        RET

; ---- Bouncing Jack-Spring (75m Elevators) ----
EnemySpring:
        LD A, (IX + E_STATE)
        CP 2
        JR Z, esp_drop

        ; Advance horizontal position 1.5 px/frame across Kong's girder
        LD A, (IX + E_X)
        INC A
        LD B, A
        LD A, (GAME + G_FRAME)
        AND 1
        ADD A, B
        LD (IX + E_X), A
        CP 21 * 8               ; past end of Kong's girder -> plummet down shaft!
        JR NC, esp_start_drop

        ; Parabolic bounce arc above Kong's girder
        LD A, (IX + E_DATA)
        INC A
        AND 15
        LD (IX + E_DATA), A
        CALL Z, SoundSpring
        LD A, (IX + E_DATA)
        LD HL, SPRING_ARC_TABLE
        ADD A, L
        LD L, A
        JR NC, esp_nc
        INC H
esp_nc:
        LD B, (HL)              ; height offset
        LD A, (LEVELBUF + L_DKY)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 8
        SUB B
        LD (IX + E_Y), A
        RET

esp_start_drop:
        LD (IX + E_STATE), 2
        CALL SoundSpringDrop
esp_drop:
        LD A, (IX + E_Y)
        ADD A, 3
        LD (IX + E_Y), A
        CP 182
        RET C
        LD (IX + E_STATE), 0
        RET

; ---- Cement Pie on Conveyor (50m) ----
EnemyPie:
        LD A, (GAME + G_FRAME)
        AND 1
        RET NZ
        ; Follow conveyor direction at current row, or fallback E_VX
        LD A, (IX + E_X)
        ADD A, 4
        SRL A
        SRL A
        SRL A
        LD D, A
        LD A, (IX + E_Y)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        LD E, A
        CALL ConveyorDirAtDE
        OR A
        JR Z, epi_use_vx
        LD (IX + E_VX), A
epi_use_vx:
        LD A, (IX + E_X)
        ADD A, (IX + E_VX)
        LD (IX + E_X), A
        CP 4
        JR C, epi_kill
        CP 244
        JR NC, epi_kill
        ; Check if sliding into central Oil Firepit on row 11!
        LD A, (LEVELBUF + L_OILX)
        CP $FF
        RET Z
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, 4
        LD B, A
        LD A, (IX + E_X)
        SUB B
        CALL Abs
        CP 9
        RET NC
        LD A, (LEVELBUF + L_OILY)
        ADD A, 2
        ADD A, A
        ADD A, A
        ADD A, A
        LD B, A
        LD A, (IX + E_Y)
        ADD A, 8
        CP B
        RET NZ
epi_kill:
        LD (IX + E_STATE), 0
        RET

; ============================================================================
;  Rivets (100m) & Bonus Items
; ============================================================================
UpdateRivets:
        LD A, (LEVELBUF + L_NRIVET)
        OR A
        RET Z
        LD B, A
        LD IX, LEVELBUF + L_RIVETS
        LD HL, RIVETS_PULLED
urv_lp:
        PUSH BC
        PUSH HL
        LD A, (HL)
        OR A
        JR NZ, urv_nxt

        ; Check if Mario's center X is over rivet column and feet near rivet row
        LD A, (PLAYER + P_X)
        ADD A, 8
        SRL A
        SRL A
        SRL A
        CP (IX + 0)
        JR NZ, urv_nxt

        LD A, (IX + 1)
        ADD A, A
        ADD A, A
        ADD A, A
        LD C, A                 ; rivet surface Y
        LD A, (PLAYER + P_Y)
        ADD A, 16
        SUB C
        CALL Abs
        CP 10
        JR NC, urv_nxt

        ; Pull rivet! Create jumpable gap & score +100!
        POP HL
        LD (HL), 1
        PUSH HL

        LD B, (IX + 0)
        LD C, (IX + 1)
        LD A, T_BLANK
        CALL TilePut
        XOR A
        CALL SetSolid           ; now a real 8px gap!

        LD BC, $0100
        CALL AddScoreBC
        LD A, (IX + 0)
        ADD A, A
        ADD A, A
        ADD A, A
        LD B, A
        LD A, (IX + 1)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 12
        LD C, A
        LD A, SPR_POP_100
        CALL SpawnPopup
        CALL SoundRivet

        LD A, (GAME + G_RIVETS)
        INC A
        LD (GAME + G_RIVETS), A
        LD B, A
        LD A, (LEVELBUF + L_NRIVET)
        CP B
        JR NZ, urv_nxt

        ; All 8 rivets pulled!! Trigger 100m Kong Collapse!
        POP HL
        POP BC
        JP TriggerRivetVictory

urv_nxt:
        POP HL
        INC HL
        LD DE, 2
        ADD IX, DE
        POP BC
        DJNZ urv_lp
        RET

UpdateItems:
        LD A, (LEVELBUF + L_NITEMS)
        OR A
        RET Z
        LD B, A
        LD IX, LEVELBUF + L_ITEMS
        LD HL, ITEMS_TAKEN
uit_lp:
        PUSH BC
        PUSH HL
        LD A, (HL)
        OR A
        JP NZ, uit_nxt

        LD A, (IX + 0)
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, 4
        LD B, A
        LD A, (PLAYER + P_X)
        ADD A, 8
        SUB B
        CALL Abs
        CP 10
        JP NC, uit_nxt

        LD A, (IX + 1)
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, 4
        LD B, A
        LD A, (PLAYER + P_Y)
        ADD A, 8
        SUB B
        CALL Abs
        CP 11
        JP NC, uit_nxt

        ; Collected item!
        POP HL
        LD (HL), 1
        PUSH HL
        LD B, (IX + 0)
        LD C, (IX + 1)
        LD A, T_BLANK
        CALL TilePut

        LD A, (IX + 0)
        ADD A, A
        ADD A, A
        ADD A, A
        LD D, A                 ; popup X
        LD A, (IX + 1)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 4
        LD E, A                 ; popup Y

        LD A, (IX + 2)
        CP T_HAMMER
        JR Z, uit_ham
        CP T_ITEM_HAT
        JR Z, uit_hat
        CP T_ITEM_PURSE
        JR Z, uit_purse

        ; Umbrella = 800 pts
        PUSH DE
        LD BC, $0800
        CALL AddScoreBC
        POP BC
        LD A, SPR_POP_800
        CALL SpawnPopup
        CALL SoundItem
        JR uit_nxt

uit_ham:
        LD A, 240               ; 4.0 seconds of Hammer power!
        LD (GAME + G_HAMMER_TIME), A
        CALL SoundItem
        JR uit_nxt

uit_hat:
        PUSH DE
        LD BC, $0300
        CALL AddScoreBC
        POP BC
        LD A, SPR_POP_300
        CALL SpawnPopup
        CALL SoundItem
        JR uit_nxt

uit_purse:
        PUSH DE
        LD BC, $0500
        CALL AddScoreBC
        POP BC
        LD A, SPR_POP_500
        CALL SpawnPopup
        CALL SoundItem

uit_nxt:
        POP HL
        INC HL
        LD DE, 3
        ADD IX, DE
        POP BC
        DEC B
        JP NZ, uit_lp
        RET

; ============================================================================
;  Collisions: Kong, Hammer Smash, Jump-Over Bonus (100/300), Pauline Rescue
; ============================================================================
Collide:
        LD A, (PLAYER + P_STATE)
        CP PS_DEAD
        RET Z
        CP PS_WIN
        RET Z

        ; 1. Touching Donkey Kong -> fatal!
        LD A, (DK + D_X)
        ADD A, 8
        LD B, A
        LD A, (PLAYER + P_X)
        ADD A, 8
        SUB B
        CALL Abs
        CP 13
        JR NC, col_hammer_box
        LD A, (DK + D_Y)
        ADD A, 8
        LD B, A
        LD A, (PLAYER + P_Y)
        ADD A, 8
        SUB B
        CALL Abs
        CP 13
        JR NC, col_hammer_box
        JP KillPlayer

col_hammer_box:
        ; Precompute active Hammer head center in (SCRATCH+0, SCRATCH+1) if active
        LD A, (GAME + G_HAMMER_TIME)
        OR A
        JR Z, col_enemies
        LD A, (GAME + G_FRAME)
        BIT 2, A
        JR Z, chb_fwd
        ; Overhead swing
        LD A, (PLAYER + P_X)
        ADD A, 8
        LD (SCRATCH + 0), A
        LD A, (PLAYER + P_Y)
        SUB 4
        LD (SCRATCH + 1), A
        JR col_enemies
chb_fwd:
        ; Forward strike (left or right)
        LD A, (PLAYER + P_FLAGS)
        BIT PF_LEFT, A
        LD A, (PLAYER + P_X)
        JR Z, chb_r
        SUB 4
        JR chb_setx
chb_r:
        ADD A, 20
chb_setx:
        LD (SCRATCH + 0), A
        LD A, (PLAYER + P_Y)
        ADD A, 8
        LD (SCRATCH + 1), A

col_enemies:
        XOR A
        LD (SCRATCH + 2), A     ; count of enemies jumped over this frame!

        LD IX, ENEMIES
        LD B, MAX_ENEMIES
ce_loop:
        PUSH BC
        LD A, (IX + E_STATE)
        OR A
        JP Z, ce_next

        ; A) Check Hammer smash first (Springs cannot be hammered!)
        LD A, (GAME + G_HAMMER_TIME)
        OR A
        JR Z, ce_body
        LD A, (IX + E_TYPE)
        CP ET_SPRING
        JR Z, ce_body
        LD A, (IX + E_X)
        ADD A, 4
        LD C, A
        LD A, (SCRATCH + 0)
        SUB C
        CALL Abs
        CP 10
        JR NC, ce_body
        LD A, (IX + E_Y)
        ADD A, 4
        LD C, A
        LD A, (SCRATCH + 1)
        SUB C
        CALL Abs
        CP 10
        JR NC, ce_body

        ; Smashed enemy!
        LD A, (IX + E_TYPE)
        CP ET_FIRE
        JR NZ, ce_not_fire
        LD A, (GAME + G_FIRE_CNT)
        OR A
        JR Z, ce_not_fire
        DEC A
        LD (GAME + G_FIRE_CNT), A
ce_not_fire:
        LD (IX + E_STATE), 0
        LD A, (IX + E_TYPE)
        CP ET_BLUE
        JR Z, ce_sm500
        CP ET_FIRE
        JR Z, ce_sm500
        LD BC, $0300
        CALL AddScoreBC
        LD B, (IX + E_X)
        LD C, (IX + E_Y)
        LD A, SPR_POP_300
        CALL SpawnPopup
        CALL SoundSmash
        JP ce_next
ce_sm500:
        LD BC, $0500
        CALL AddScoreBC
        LD B, (IX + E_X)
        LD C, (IX + E_Y)
        LD A, SPR_POP_500
        CALL SpawnPopup
        CALL SoundSmash
        JP ce_next

ce_body:
        ; B) Mario body vs 8x8 enemy hitbox (forgiving arcade 9x10 core)
        LD A, (IX + E_X)
        ADD A, 4
        LD C, A
        LD A, (PLAYER + P_X)
        ADD A, 8
        SUB C
        CALL Abs
        CP 9
        JR NC, ce_next

        LD A, (IX + E_Y)
        ADD A, 4
        LD C, A
        LD A, (PLAYER + P_Y)
        ADD A, 9
        SUB C
        CALL Abs
        CP 9
        JR C, ce_fatal

        ; C) Jump-over bonus check when airborne above enemy!
        LD A, (PLAYER + P_FLAGS)
        BIT PF_GROUNDED, A
        JR NZ, ce_next
        LD A, (PLAYER + P_STATE)
        CP PS_CLIMB
        JR Z, ce_next
        LD A, (IX + E_ANIM)
        BIT 7, A
        JR NZ, ce_next
        LD A, (PLAYER + P_Y)
        ADD A, 12
        LD C, A
        LD A, (IX + E_Y)
        SUB C
        JR C, ce_next
        CP 22
        JR NC, ce_next
        ; Passed cleanly over enemy!
        SET 7, (IX + E_ANIM)
        LD A, (SCRATCH + 2)
        INC A
        LD (SCRATCH + 2), A
        JR ce_next

ce_fatal:
        POP BC
        JP KillPlayer

ce_next:
        LD DE, 8
        ADD IX, DE
        POP BC
        DEC B
        JP NZ, ce_loop

        ; Award jump-over score (100 for 1 enemy, 300 for 2+ in one leap!)
        LD A, (SCRATCH + 2)
        OR A
        JR Z, col_pauline
        CP 1
        JR NZ, col_j300
        LD BC, $0100
        CALL AddScoreBC
        LD A, (PLAYER + P_X)
        ADD A, 4
        LD B, A
        LD A, (PLAYER + P_Y)
        SUB 8
        LD C, A
        LD A, SPR_POP_100
        CALL SpawnPopup
        CALL SoundScore
        JR col_pauline
col_j300:
        LD BC, $0300
        CALL AddScoreBC
        LD A, (PLAYER + P_X)
        ADD A, 4
        LD B, A
        LD A, (PLAYER + P_Y)
        SUB 8
        LD C, A
        LD A, SPR_POP_300
        CALL SpawnPopup
        CALL SoundScore

col_pauline:
        ; Non-rivet stages complete when Mario climbs up to Pauline's platform!
        LD A, (GAME + G_LEVELTYPE)
        CP LT_RIVETS
        RET Z
        LD A, (LEVELBUF + L_PAUYY)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 14
        LD B, A
        LD A, (PLAYER + P_Y)
        CP B
        RET NC
        LD A, (LEVELBUF + L_PAUXX)
        ADD A, A
        ADD A, A
        ADD A, A
        LD B, A
        LD A, (PLAYER + P_X)
        SUB B
        CALL Abs
        CP 36
        RET NC
        JP TriggerStageClear

; ============================================================================
;  Dying, Stage Clear, 100m Collapse & Victory, Game Over, Name Entry
; ============================================================================
DyingUpdate:
        ; Spin Mario through dead0..3 during death sequence!
        CALL BuildSprites
        LD A, (GAME + G_STATE_T)
        DEC A
        LD (GAME + G_STATE_T), A
        RET NZ

        LD A, (GAME + G_LIVES)
        DEC A
        LD (GAME + G_LIVES), A
        JP NZ, HowHighScreen

        ; Out of lives -> check Top-5 High Score qualification!
        CALL CheckQualifiesHighScore
        CP $FF
        JP NZ, StartNameEntry
        JP StartGameOver

TriggerStageClear:
        LD A, (GAME + G_STATE)
        CP GS_DEMO
        JP Z, TitleScreen
        LD A, PS_WIN
        LD (PLAYER + P_STATE), A
        XOR A
        LD (GAME + G_HAMMER_TIME), A
        LD (GAME + G_PHASE), A
        LD A, 55
        LD (GAME + G_STATE_T), A
        LD A, GS_LEVELEND
        LD (GAME + G_STATE), A
        ; Clear active enemies for clean Heart celebration!
        LD HL, ENEMIES
        LD B, 96
        XOR A
tsc_clr:
        LD (HL), A
        INC HL
        DJNZ tsc_clr
        JP SoundWin

TriggerRivetVictory:
        LD A, PS_WIN
        LD (PLAYER + P_STATE), A
        XOR A
        LD (GAME + G_HAMMER_TIME), A
        LD HL, ENEMIES
        LD B, 96
trv_clr:
        LD (HL), A
        INC HL
        DJNZ trv_clr

        ; Erase entire collapsed center tower (cols 8..23, rows 6..21) under Kong!
        LD C, 6
trv_rlp:
        LD B, 8
trv_clp:
        LD A, T_BLANK
        CALL TilePut
        INC B
        LD A, B
        CP 24
        JR C, trv_clp
        INC C
        LD A, C
        CP 22
        JR C, trv_rlp

        LD A, 5                 ; upside-down falling DK pose!
        LD (DK + D_POSE), A
        LD A, 2                 ; phase 2 = Kong falling!
        LD (GAME + G_PHASE), A
        LD A, 70
        LD (GAME + G_STATE_T), A
        LD A, GS_LEVELEND
        LD (GAME + G_STATE), A
        LD A, TRK_MUS_DK_FALL_INTRO
        JP MusicPlay

collapse_rows:
        DB 7, 11, 15, 19

LevelEndUpdate:
        LD A, (GAME + G_PHASE)
        CP 2
        JR Z, leu_kong_fall
        CP 1
        JR Z, leu_bonus_tally

        ; Phase 0: Heart celebration pause before bonus tally
        CALL BuildSprites
        LD A, (GAME + G_STATE_T)
        DEC A
        LD (GAME + G_STATE_T), A
        RET NZ
        LD A, 1
        LD (GAME + G_PHASE), A
        RET

leu_kong_fall:
        ; Drop upside-down Kong onto bottom girder (Y = 22*8 - 16 = 160)!
        LD A, (DK + D_Y)
        CP 160
        JR NC, lkf_landed
        ADD A, 3
        CP 160
        JR C, lkf_sety
        LD A, 160
        PUSH AF
        CALL SoundSmash
        POP AF
lkf_sety:
        LD (DK + D_Y), A
lkf_landed:
        CALL BuildSprites
        LD A, (GAME + G_STATE_T)
        DEC A
        LD (GAME + G_STATE_T), A
        RET NZ
        LD A, 1
        LD (GAME + G_PHASE), A
        RET

leu_bonus_tally:
        ; Rapidly count remaining G_BONUS (-100 per 2 frames) into G_SCORE
        LD A, (GAME + G_FRAME)
        INC A
        LD (GAME + G_FRAME), A
        AND 1
        JR NZ, lbt_draw
        LD A, (GAME + G_BONUS)
        OR A
        JR Z, lbt_done
        SUB $01
        DAA
        LD (GAME + G_BONUS), A
        LD BC, $0100
        CALL AddScoreBC
        CALL SoundTick
lbt_draw:
        CALL BuildSprites
        JP UpdateHUD

lbt_done:
        ; If 100m Rivets stage was completed, show Full-Screen Victory Finale!
        LD A, (GAME + G_LEVELTYPE)
        CP LT_RIVETS
        JP Z, StartVictoryFinale
        ; Otherwise show Stage-Clear Broken-Heart intermission (Kong escapes with Pauline)!
        LD HL, ART_STAGECLEAR_DESC
        CALL LoadArtScreen
        CALL DrawHUD
        LD HL, VRAM_NAME + (22 * NAME_COLS) + 5
        LD DE, txt_kong_fled
        CALL DrawText
        LD A, 120
        LD (GAME + G_STATE_T), A
        LD A, GS_VICTORY
        LD (GAME + G_STATE), A
        RET

StartVictoryFinale:
        LD HL, ART_VICTORY_DESC
        CALL LoadArtScreen
        CALL DrawHUD
        LD HL, VRAM_NAME + (2 * NAME_COLS) + 5
        LD DE, txt_congrats
        CALL DrawText
        LD A, 220
        LD (GAME + G_STATE_T), A
        LD A, GS_VICTORY
        LD (GAME + G_STATE), A
        LD A, (GAME + G_LOOP)
        BIT 0, A
        LD A, TRK_MUS_VICTORY_ODD
        JR Z, svf_mus
        LD A, TRK_MUS_VICTORY_EVEN
svf_mus:
        JP MusicPlay

VictoryUpdate:
        LD A, (GAME + G_STATE_T)
        CP 180
        JR NC, vu_dec
        LD A, (INP_EDGE)
        AND $30
        JR NZ, vu_next
vu_dec:
        LD A, (GAME + G_STATE_T)
        DEC A
        LD (GAME + G_STATE_T), A
        RET NZ
vu_next:
        LD A, (GAME + G_STAGE_SEQ)
        INC A
        LD (GAME + G_STAGE_SEQ), A
        CALL ResolveCurrentStage
        JP HowHighScreen

; ---- High Score Qualification & 3-Initial Entry ----
; Returns A = rank (0..4) if G_SCORE > HISCORES[rank], else $FF
CheckQualifiesHighScore:
        LD HL, HISCORES
        LD C, 0
cqh_lp:
        PUSH HL
        PUSH BC
        LD DE, GAME + G_SCORE0
        CALL CmpScore3
        POP BC
        POP HL
        JR C, cqh_yes
        LD DE, 6
        ADD HL, DE
        INC C
        LD A, C
        CP 5
        JR C, cqh_lp
        LD A, $FF
        RET
cqh_yes:
        LD A, C
        RET

StartNameEntry:
        ; A = qualifying rank (0..4); shift lower entries down & insert score!
        LD (NAMEENTRY + 0), A   ; rank
        LD B, A
        LD A, 4
        SUB B
        JR Z, sne_insert
        ; Shift (4 - rank) * 6 bytes downward from end
        LD L, A
        LD H, 0
        ADD HL, HL              ; *2
        LD D, H
        LD E, L
        ADD HL, HL              ; *4
        ADD HL, DE              ; *6 = byte count in BC
        LD B, H
        LD C, L
        LD HL, HISCORES + 23    ; last byte of entry 3
        LD DE, HISCORES + 29    ; last byte of entry 4
        LDDR
sne_insert:
        LD A, (NAMEENTRY + 0)
        LD L, A
        LD H, 0
        ADD HL, HL
        LD D, H
        LD E, L
        ADD HL, HL
        ADD HL, DE
        LD DE, HISCORES
        ADD HL, DE
        EX DE, HL               ; DE -> target entry
        PUSH DE
        LD HL, GAME + G_SCORE0
        LD BC, 3
        LDIR
        POP HL
        INC HL
        INC HL
        INC HL
        LD (HL), 'A'
        INC HL
        LD (HL), 'A'
        INC HL
        LD (HL), 'A'
        CALL SyncTopHighScore

        XOR A
        LD (NAMEENTRY + 1), A   ; cursor pos 0..2
        LD A, 'A'
        LD (NAMEENTRY + 2), A   ; current char

        CALL DrawHighScorePage
        LD HL, VRAM_NAME + (19 * NAME_COLS) + 5
        LD DE, txt_enter_init
        CALL DrawText
        LD A, GS_NAMEENTRY
        LD (GAME + G_STATE), A
        LD A, TRK_MUS_NAMEENTRY
        JP MusicPlay

NameEntryUpdate:
        ; Left/Right changes letter; Button 1 confirms letter!
        LD A, (INP_EDGE)
        BIT 2, A
        JR Z, neu_chk_r
        LD A, (NAMEENTRY + 2)
        CP 'A'
        JR NZ, neu_dec
        LD A, 'Z' + 1
neu_dec:
        DEC A
        LD (NAMEENTRY + 2), A
        CALL SoundTick
        JR neu_draw
neu_chk_r:
        BIT 3, A
        JR Z, neu_chk_btn
        LD A, (NAMEENTRY + 2)
        CP 'Z'
        JR NZ, neu_inc
        LD A, 'A' - 1
neu_inc:
        INC A
        LD (NAMEENTRY + 2), A
        CALL SoundTick
        JR neu_draw

neu_chk_btn:
        AND $30
        JR Z, neu_draw
        CALL SoundScore
        LD A, (NAMEENTRY + 1)
        INC A
        LD (NAMEENTRY + 1), A
        CP 3
        JP NC, StartGameOver
        LD A, 'A'
        LD (NAMEENTRY + 2), A

neu_draw:
        ; Write active letter into HISCORES[rank].initials[pos] and redraw!
        LD A, (NAMEENTRY + 0)
        LD L, A
        LD H, 0
        ADD HL, HL
        LD D, H
        LD E, L
        ADD HL, HL
        ADD HL, DE
        LD DE, HISCORES + 3
        ADD HL, DE
        LD A, (NAMEENTRY + 1)
        LD E, A
        LD D, 0
        ADD HL, DE
        LD A, (NAMEENTRY + 2)
        LD (HL), A

        ; Compute screen coordinates: col = 19 + pos, row = 8 + rank*2
        LD A, (NAMEENTRY + 0)
        ADD A, A
        ADD A, 8
        LD C, A
        LD A, (NAMEENTRY + 1)
        ADD A, 19
        LD B, A
        LD A, (GAME + G_FRAME)
        INC A
        LD (GAME + G_FRAME), A
        BIT 3, A
        LD A, (NAMEENTRY + 2)
        JR Z, neu_put
        LD A, '_'
neu_put:
        JP TilePutChar

StartGameOver:
        LD HL, ART_GAMEOVER_DESC
        CALL LoadArtScreen
        CALL DrawHUD
        LD HL, VRAM_NAME + (20 * NAME_COLS) + 9
        LD DE, txt_press
        CALL DrawText
        LD A, 180
        LD (GAME + G_STATE_T), A
        LD A, GS_GAMEOVER
        LD (GAME + G_STATE), A
        RET

GameOverUpdate:
        LD A, (INP_EDGE)
        AND $30
        JP NZ, TitleScreen
        LD A, (GAME + G_STATE_T)
        DEC A
        LD (GAME + G_STATE_T), A
        RET NZ
        JP TitleScreen

; ============================================================================
;  Sprite Builder with Scanline Flicker Rotation & Terminator Safety
; ============================================================================
; SCRATCH+10=x, +11=y, +12=pat, +13..+16=colors, HL=SPRBUF write cursor, C=remaining slots
Emit1:
        LD A, C
        OR A
        RET Z
        DEC C
        LD A, (SCRATCH + 11)
        DEC A
        LD (HL), A
        INC HL
        LD A, (SCRATCH + 10)
        LD (HL), A
        INC HL
        LD A, (SCRATCH + 12)
        LD (HL), A
        INC HL
        LD A, (SCRATCH + 13)
        LD (HL), A
        INC HL
        RET

EmitBig:
        LD A, (SCRATCH + 10)
        LD (SCRATCH + 20), A
        LD A, (SCRATCH + 11)
        LD (SCRATCH + 21), A
        CALL Emit1
        LD A, (SCRATCH + 10)
        ADD A, 8
        LD (SCRATCH + 10), A
        LD A, (SCRATCH + 12)
        INC A
        LD (SCRATCH + 12), A
        LD A, (SCRATCH + 14)
        LD (SCRATCH + 13), A
        CALL Emit1
        LD A, (SCRATCH + 20)
        LD (SCRATCH + 10), A
        LD A, (SCRATCH + 21)
        ADD A, 8
        LD (SCRATCH + 11), A
        LD A, (SCRATCH + 12)
        INC A
        LD (SCRATCH + 12), A
        LD A, (SCRATCH + 15)
        LD (SCRATCH + 13), A
        CALL Emit1
        LD A, (SCRATCH + 20)
        ADD A, 8
        LD (SCRATCH + 10), A
        LD A, (SCRATCH + 12)
        INC A
        LD (SCRATCH + 12), A
        LD A, (SCRATCH + 16)
        LD (SCRATCH + 13), A
        CALL Emit1
        LD A, (SCRATCH + 20)
        LD (SCRATCH + 10), A
        LD A, (SCRATCH + 21)
        LD (SCRATCH + 11), A
        RET

SelectMarioPattern:
        LD A, (PLAYER + P_STATE)
        CP PS_DEAD
        JR Z, smp_dead
        CP PS_CLIMB
        JR Z, smp_climb

        ; Hammer active?
        LD A, (GAME + G_HAMMER_TIME)
        OR A
        JR Z, smp_noham
        LD A, (GAME + G_FRAME)
        BIT 2, A
        LD B, 16                ; ham1 offset (4*4)
        JR NZ, smp_add_dir
        LD B, 20                ; ham2 offset (5*4)
        JR smp_add_dir

smp_noham:
        LD A, (PLAYER + P_STATE)
        CP PS_JUMP
        JR NZ, smp_chk_run
        LD B, 12                ; jump offset (3*4)
        JR smp_add_dir
smp_chk_run:
        CP PS_RUN
        JR NZ, smp_stand
        LD A, (PLAYER + P_ANIM)
        BIT 2, A
        LD B, 4                 ; run1 offset
        JR Z, smp_add_dir
        LD B, 8                 ; run2 offset
        JR smp_add_dir
smp_stand:
        LD B, 0
smp_add_dir:
        LD A, (PLAYER + P_FLAGS)
        BIT PF_LEFT, A
        LD A, SPR_MARIO_R_STAND_0
        JR Z, smp_ret_b
        LD A, SPR_MARIO_L_STAND_0
smp_ret_b:
        ADD A, B
        RET

smp_climb:
        LD A, (PLAYER + P_ANIM)
        BIT 2, A
        LD A, SPR_MARIO_CLIMB1_0
        RET Z
        LD A, SPR_MARIO_CLIMB2_0
        RET

smp_dead:
        LD A, (GAME + G_STATE_T)
        CP 24
        JR C, smp_dead_lie
        RRCA
        RRCA
        AND 3
        RLCA
        RLCA
        ADD A, SPR_MARIO_DEAD0_0
        RET
smp_dead_lie:
        LD A, SPR_MARIO_DEAD2_0
        RET

BuildSprites:
        LD HL, SPRBUF
        LD C, 32                ; max 32 hardware sprites

        ; 1. Mario (highest priority + layered 3-color tan face overlay!)
        LD A, (PLAYER + P_STATE)
        CP PS_DEAD
        JR Z, bs_m_base
        CP PS_CLIMB
        JR Z, bs_m_base
        ; Emit 8x8 tan face overlay first so skin sits cleanly on front of head!
        LD A, (PLAYER + P_FLAGS)
        BIT PF_LEFT, A
        JR Z, bs_mf_r
        LD A, (PLAYER + P_X)
        ADD A, 2
        LD (SCRATCH + 10), A
        LD A, SPR_MARIO_FACE_L
        JR bs_mf_emit
bs_mf_r:
        LD A, (PLAYER + P_X)
        ADD A, 6
        LD (SCRATCH + 10), A
        LD A, SPR_MARIO_FACE_R
bs_mf_emit:
        LD (SCRATCH + 12), A
        LD A, (PLAYER + P_Y)
        LD (SCRATCH + 11), A
        LD A, 11                ; tan skin
        LD (SCRATCH + 13), A
        CALL Emit1

bs_m_base:
        CALL SelectMarioPattern
        LD (SCRATCH + 12), A
        LD A, (PLAYER + P_X)
        LD (SCRATCH + 10), A
        LD A, (PLAYER + P_Y)
        LD (SCRATCH + 11), A
        LD A, 8                 ; red cap & shirt (both upper quads!)
        LD (SCRATCH + 13), A
        LD (SCRATCH + 14), A
        LD A, 5                 ; blue overalls (both lower quads!)
        LD (SCRATCH + 15), A
        LD (SCRATCH + 16), A
        CALL EmitBig

        ; 2. Swinging Hammer head sprite if Hammer active!
        LD A, (GAME + G_HAMMER_TIME)
        OR A
        JR Z, bs_popup
        LD A, (GAME + G_FRAME)
        BIT 2, A
        JR Z, bs_ham_fwd
        LD A, (PLAYER + P_X)
        ADD A, 4
        LD (SCRATCH + 10), A
        LD A, (PLAYER + P_Y)
        SUB 8
        LD (SCRATCH + 11), A
        LD A, SPR_HAMMER_UP
        JR bs_ham_emit
bs_ham_fwd:
        LD A, (PLAYER + P_FLAGS)
        BIT PF_LEFT, A
        JR Z, bs_ham_r
        LD A, (PLAYER + P_X)
        SUB 8
        LD (SCRATCH + 10), A
        LD A, SPR_HAMMER_LEFT
        JR bs_ham_y
bs_ham_r:
        LD A, (PLAYER + P_X)
        ADD A, 16
        LD (SCRATCH + 10), A
        LD A, SPR_HAMMER_RIGHT
bs_ham_y:
        PUSH AF
        LD A, (PLAYER + P_Y)
        ADD A, 4
        LD (SCRATCH + 11), A
        POP AF
bs_ham_emit:
        LD (SCRATCH + 12), A
        LD A, 11
        LD (SCRATCH + 13), A
        CALL Emit1

bs_popup:
        ; 3. Floating Score Popup ("100"/"300"/"500"/"800"/"1UP") or Stage-Clear Heart!
        LD A, (GAME + G_STATE)
        CP GS_LEVELEND
        JR NZ, bs_pop_norm
        LD A, (GAME + G_LEVELTYPE)
        CP LT_RIVETS
        JR Z, bs_dk
        LD A, (LEVELBUF + L_PAUXX)
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, 16
        LD (SCRATCH + 10), A
        LD A, (LEVELBUF + L_PAUYY)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 14
        LD (SCRATCH + 11), A
        LD A, SPR_HEART
        LD (SCRATCH + 12), A
        LD A, 8
        LD (SCRATCH + 13), A
        CALL Emit1
        JR bs_dk

bs_pop_norm:
        LD A, (GAME + G_POP_T)
        OR A
        JR Z, bs_dk
        LD A, (GAME + G_POP_X)
        LD (SCRATCH + 10), A
        LD A, (GAME + G_POP_Y)
        LD (SCRATCH + 11), A
        LD A, (GAME + G_POP_PAT)
        LD (SCRATCH + 12), A
        LD A, 15
        LD (SCRATCH + 13), A
        CALL Emit1

bs_dk:
        ; 4. Donkey Kong (layered tan face overlay + 4 chestnut fur quads!)
        LD A, (DK + D_X)
        ADD A, 4
        LD (SCRATCH + 10), A
        LD A, (DK + D_POSE)
        CP 5
        JR Z, bs_dk_ffall
        LD A, (DK + D_Y)
        ADD A, 1
        LD (SCRATCH + 11), A
        LD A, SPR_DK_FACE
        JR bs_dk_femit
bs_dk_ffall:
        LD A, (DK + D_Y)
        ADD A, 7
        LD (SCRATCH + 11), A
        LD A, SPR_DK_FACE_FALL
bs_dk_femit:
        LD (SCRATCH + 12), A
        LD A, 11                ; tan face & grin
        LD (SCRATCH + 13), A
        CALL Emit1

        LD A, (DK + D_POSE)
        RLCA
        RLCA
        ADD A, SPR_DK_STAND_0
        LD (SCRATCH + 12), A
        LD A, (DK + D_X)
        LD (SCRATCH + 10), A
        LD A, (DK + D_Y)
        LD (SCRATCH + 11), A
        LD A, 6                 ; uniform rich dark-red/brown fur (zero half-split!)
        LD (SCRATCH + 13), A
        LD (SCRATCH + 14), A
        LD (SCRATCH + 15), A
        LD (SCRATCH + 16), A
        CALL EmitBig

        ; 5. Pauline (16x16 = 4 sprites + flashing "HELP!" callout!)
        LD A, (GAME + G_FRAME)
        BIT 4, A
        LD A, SPR_PAULINE_1_0
        JR Z, bs_pau_set
        LD A, SPR_PAULINE_2_0
bs_pau_set:
        LD (SCRATCH + 12), A
        LD A, (LEVELBUF + L_PAUXX)
        ADD A, A
        ADD A, A
        ADD A, A
        LD (SCRATCH + 10), A
        LD A, (LEVELBUF + L_PAUYY)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD (SCRATCH + 11), A
        LD A, 11                ; golden hair
        LD (SCRATCH + 13), A
        LD (SCRATCH + 14), A
        LD A, 13                ; pink/magenta gown
        LD (SCRATCH + 15), A
        LD (SCRATCH + 16), A
        CALL EmitBig

        ; "HELP!" speech bubble every 64 frames during play
        LD A, (GAME + G_STATE)
        CP GS_PLAY
        JR NZ, bs_enemies
        LD A, (GAME + G_FRAME)
        AND $30
        JR NZ, bs_enemies
        LD A, (LEVELBUF + L_PAUXX)
        ADD A, 2
        ADD A, A
        ADD A, A
        ADD A, A
        LD (SCRATCH + 10), A
        LD A, (LEVELBUF + L_PAUYY)
        ADD A, A
        ADD A, A
        ADD A, A
        SUB 16
        LD (SCRATCH + 11), A
        LD A, SPR_HELP_L
        LD (SCRATCH + 12), A
        LD A, 7
        LD (SCRATCH + 13), A
        CALL Emit1
        LD A, (SCRATCH + 10)
        ADD A, 8
        LD (SCRATCH + 10), A
        LD A, SPR_HELP_R
        LD (SCRATCH + 12), A
        CALL Emit1

bs_enemies:
        ; 6. Enemies with coprime rotation (+5 mod 12) so >4/scanline flickers fairly!
        LD A, (GAME + G_FLICKER)
        ADD A, 5
        CP MAX_ENEMIES
        JR C, bse_fok
        SUB MAX_ENEMIES
bse_fok:
        LD (GAME + G_FLICKER), A
        LD D, A                 ; D = current slot index 0..11
        LD B, MAX_ENEMIES
bse_loop:
        PUSH BC
        PUSH DE
        LD A, D
        ADD A, A
        ADD A, A
        ADD A, A                ; * 8
        LD E, A
        LD D, 0
        LD IX, ENEMIES
        ADD IX, DE
        LD A, (IX + E_STATE)
        OR A
        JP Z, bse_next

        LD A, (IX + E_X)
        LD (SCRATCH + 10), A
        LD A, (IX + E_Y)
        LD (SCRATCH + 11), A

        LD A, (IX + E_TYPE)
        CP ET_FIRE
        JR Z, bse_fire
        CP ET_SPRING
        JR Z, bse_spring
        CP ET_PIE
        JR Z, bse_pie

        ; Brown or Blue Barrel (rolling vs down-ladder!)
        LD A, (IX + E_STATE)
        CP 3
        JR Z, bse_bdown
        LD A, (IX + E_ANIM)
        RRCA
        RRCA
        AND 1
        ADD A, SPR_BARREL_1
        JR bse_bcol
bse_bdown:
        LD A, (IX + E_ANIM)
        RRCA
        RRCA
        AND 1
        ADD A, SPR_BARREL_DOWN1
bse_bcol:
        LD (SCRATCH + 12), A
        LD A, (IX + E_TYPE)
        CP ET_BLUE
        LD A, 10                ; brown/gold barrel
        JR NZ, bse_emit
        LD A, 7                 ; cyan-blue barrel!
        JR bse_emit

bse_fire:
        LD A, (IX + E_VX)
        BIT 7, A
        LD B, SPR_FIRE_R1
        JR Z, bse_ffrm
        LD B, SPR_FIRE_L1
bse_ffrm:
        LD A, (IX + E_ANIM)
        RRCA
        RRCA
        AND 1
        ADD A, B
        LD (SCRATCH + 12), A
        LD A, (GAME + G_FRAME)
        BIT 2, A
        LD A, 8                 ; bright red-orange flicker!
        JR Z, bse_emit
        LD A, 11
        JR bse_emit

bse_spring:
        LD A, (IX + E_DATA)
        CP 2
        LD A, SPR_SPRING_1
        JR NC, bse_sp_ok
        LD A, SPR_SPRING_2      ; squashed on girder impact!
bse_sp_ok:
        LD (SCRATCH + 12), A
        LD A, 7
        JR bse_emit

bse_pie:
        LD A, (IX + E_ANIM)
        RRCA
        RRCA
        RRCA
        AND 1
        ADD A, SPR_PIE_1
        LD (SCRATCH + 12), A
        LD A, 11
bse_emit:
        LD (SCRATCH + 13), A
        CALL Emit1

bse_next:
        POP DE
        INC D
        LD A, D
        CP MAX_ENEMIES
        JR C, bse_nowrap
        LD D, 0
bse_nowrap:
        POP BC
        DEC B
        JP NZ, bse_loop

        ; Always write TMS9918A $D0 sprite terminator if < 32 sprites emitted!
        LD A, C
        OR A
        JR Z, bs_dma
        LD (HL), $D0
bs_dma:
        LD HL, SPRBUF
        LD DE, 128
        LD BC, VRAM_SPRATTR
        JP VdpWriteAt

; ============================================================================
;  Strings
; ============================================================================
txt_hud1:       DB "1UP 000000     HIGH 000000", $FF
txt_hud2:       DB "     L=01      BONUS 0000", $FF
txt_mode0:      DB "1P US ARCADE", $FF
txt_mode1:      DB "1P JP ARCADE", $FF
txt_mode2:      DB "1P REMIX 8-TOUR", $FF
txt_mode3:      DB "SOUND + STAGE LAB", $FF
txt_press:      DB "PRESS BUTTON 1", $FF
txt_copy:       DB "@ 1981 NINTENDO / SG-1000", $FF
txt_hall:       DB "TOP 5 KONG CHAMPIONS", $FF
txt_cast_hdr:   DB "CAST AND SCORING", $FF
txt_cast1:      DB "KONG KIDNAPS LADY!", $FF
txt_cast2:      DB "JUMPMAN TO RESCUE!", $FF
txt_cast3:      DB "JUMP BARRELS:100/300", $FF
txt_cast_pts:   DB "SMASH ENEMIES WITH HAMMER!", $FF
txt_cast_vals:  DB "HAMMER   300     500    800", $FF
txt_demo:       DB "DEMO - PRESS BUTTON", $FF
txt_howhigh:    DB "HOW HIGH CAN YOU GET ?", $FF
txt_25m:        DB " 25m", $FF
txt_50m:        DB " 50m", $FF
txt_75m:        DB " 75m", $FF
txt_100m:       DB "100m", $FF
txt_paused:     DB "PAUSED", $FF
txt_pause_clr:  DB "      ", $FF
txt_congrats:   DB "GREAT! YOU SAVED PAULINE", $FF
txt_kong_fled:  DB "KONG ESCAPED UP HIGHER!", $FF
txt_enter_init: DB "GREAT SCORE! INITIALS:", $FF
txt_over_box1:  DB "-----------", $FF
txt_over:       DB " GAME OVER ", $FF

txt_jb_hdr:     DB "SOUND AND STAGE LAB", $FF
txt_jb_help:    DB "B1:PLAY/GO  B2:TITLE MENU", $FF
txt_jb_stage:   DB "STAGE: ", $FF
txt_jb_loop:    DB "LOOP : L=01", $FF
txt_jb_mus:     DB "MUSIC: ", $FF
txt_jb_sfx:     DB "SFX  : ", $FF
txt_jb_go:      DB "LAUNCH SELECTED STAGE!", $FF

jb_stage_names:
        DW jbs_0, jbs_1, jbs_2, jbs_3, jbs_4, jbs_5
        DW jbs_6, jbs_7, jbs_8, jbs_9, jbs_10, jbs_11
jbs_0:  DB "01 25M GIRDERS   ", $FF
jbs_1:  DB "02 50M CONVEYORS ", $FF
jbs_2:  DB "03 75M ELEVATORS ", $FF
jbs_3:  DB "04 100M RIVETS   ", $FF
jbs_4:  DB "05 RMX CROSSOVER ", $FF
jbs_5:  DB "06 RMX SPIRAL    ", $FF
jbs_6:  DB "07 RMX THE PITS  ", $FF
jbs_7:  DB "08 RMX RAMPY     ", $FF
jbs_8:  DB "09 RMX DK94 SPAN ", $FF
jbs_9:  DB "10 RMX FACTORY   ", $FF
jbs_10: DB "11 RMX SHAFTS    ", $FF
jbs_11: DB "12 RMX CITADEL   ", $FF

jb_trk_names:
        DW jbt_0, jbt_1, jbt_2, jbt_3, jbt_4, jbt_5, jbt_6, jbt_7
        DW jbt_8, jbt_9, jbt_10, jbt_11, jbt_12, jbt_13, jbt_14
jbt_0:  DB "00 25M BARRELS   ", $FF
jbt_1:  DB "01 50M FACTORY   ", $FF
jbt_2:  DB "02 75M ELEVATORS ", $FF
jbt_3:  DB "03 100M RIVETS   ", $FF
jbt_4:  DB "04 HURRY UP!     ", $FF
jbt_5:  DB "05 HAMMER THEME  ", $FF
jbt_6:  DB "06 HOW HIGH?     ", $FF
jbt_7:  DB "07 KONG CLIMB    ", $FF
jbt_8:  DB "08 STAGE CLEAR   ", $FF
jbt_9:  DB "09 VICTORY ODD   ", $FF
jbt_10: DB "10 VICTORY EVEN  ", $FF
jbt_11: DB "11 KONG FALLING  ", $FF
jbt_12: DB "12 DEATH TAIL    ", $FF
jbt_13: DB "13 ATTRACT THEME ", $FF
jbt_14: DB "14 NAME ENTRY    ", $FF

jb_sfx_names:
        DW jbx_1, jbx_2, jbx_3, jbx_4, jbx_5, jbx_6, jbx_7, jbx_8
        DW jbx_9, jbx_10, jbx_11, jbx_12, jbx_13, jbx_14, jbx_15, jbx_16
jbx_1:  DB "01 JUMP          ", $FF
jbx_2:  DB "02 FOOTSTEP A    ", $FF
jbx_3:  DB "03 FOOTSTEP B    ", $FF
jbx_4:  DB "04 LADDER CLIMB  ", $FF
jbx_5:  DB "05 JUMP SCORE    ", $FF
jbx_6:  DB "06 HAMMER SMASH  ", $FF
jbx_7:  DB "07 BONUS ITEM    ", $FF
jbx_8:  DB "08 RIVET PULL    ", $FF
jbx_9:  DB "09 SPRING BOING  ", $FF
jbx_10: DB "10 SPRING DROP   ", $FF
jbx_11: DB "11 BARREL THROW  ", $FF
jbx_12: DB "12 KONG ROAR     ", $FF
jbx_13: DB "13 MENU TICK     ", $FF
jbx_14: DB "14 EXTRA LIFE    ", $FF
jbx_15: DB "15 PAUSE CHIME   ", $FF
jbx_16: DB "16 PLAYER DEATH  ", $FF
