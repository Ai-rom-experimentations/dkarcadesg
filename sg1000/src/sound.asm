; ============================================================================
;  SN76489AN Sound & Music Engine (Arcade dkong-snd.asm patterns + swept SFX)
; ============================================================================

MUS_CUR_TRK     equ MUSIC + 0
MUS_PTR         equ MUSIC + 1       ; 2 bytes
MUS_START       equ MUSIC + 3       ; 2 bytes
MUS_TIMER       equ MUSIC + 5
MUS_DECAY       equ MUSIC + 6
MUS_VOL0        equ MUSIC + 7
MUS_VOL1        equ MUSIC + 8
MUS_ENV_DIV     equ MUSIC + 9
SFX_PTR         equ MUSIC + 10      ; 2 bytes
SFX_TIMER       equ MUSIC + 12
MUS_STEP_TOGGLE equ MUSIC + 13

; ----------------------------------------------------------------------------
; Low-level SN76489 primitives (port PSG = $7F)
; ----------------------------------------------------------------------------
; A = channel (0..2), HL = 10-bit period (0 = silence)
PsgTone:
        PUSH BC
        LD B, A
        LD A, H
        OR L
        JR NZ, pt_nonzero
        LD A, B
        LD B, 15
        CALL PsgVol
        POP BC
        RET
pt_nonzero:
        LD A, B
        RRCA
        RRCA
        RRCA
        AND $60
        OR $80
        LD C, A
        LD A, L
        AND $0F
        OR C
        OUT (PSG), A
        LD A, L
        RRCA
        RRCA
        RRCA
        RRCA
        AND $0F
        LD C, A
        LD A, H
        AND $03
        RLCA
        RLCA
        RLCA
        RLCA
        OR C
        OUT (PSG), A
        POP BC
        RET

; A = channel (0..3), B = attenuation (0..15, 15 = silent)
PsgVol:
        RRCA
        RRCA
        RRCA
        AND $60
        OR $90
        LD C, A
        LD A, B
        AND $0F
        OR C
        OUT (PSG), A
        RET

; A = noise control ($00..$07: bit2=1 white / 0 periodic, bits1..0=rate)
PsgNoise:
        AND $07
        OR $E0
        OUT (PSG), A
        RET

SoundSilenceAll:
        LD A, $9F
        OUT (PSG), A
        LD A, $BF
        OUT (PSG), A
        LD A, $DF
        OUT (PSG), A
        LD A, $FF
        OUT (PSG), A
        RET

SoundInit:
        CALL SoundSilenceAll
        LD A, TRK_NONE
        LD (MUS_CUR_TRK), A
        LD HL, 0
        LD (MUS_PTR), HL
        LD (SFX_PTR), HL
        XOR A
        LD (MUS_TIMER), A
        LD (SFX_TIMER), A
        RET

; ----------------------------------------------------------------------------
; Start music track A (TRK_* or TRK_NONE); if already playing, keep playing
; ----------------------------------------------------------------------------
MusicPlayIfNew:
        LD B, A
        LD A, (MUS_CUR_TRK)
        CP B
        RET Z
        LD A, B
        ; fall through to MusicPlay

MusicPlay:
        LD (MUS_CUR_TRK), A
        CP TRK_NONE
        JR NZ, mp_load
        LD HL, 0
        LD (MUS_PTR), HL
        XOR A
        LD B, 15
        CALL PsgVol
        LD A, 1
        LD B, 15
        JP PsgVol
mp_load:
        LD L, A
        LD H, 0
        ADD HL, HL
        LD DE, MUSIC_TRACK_TABLE
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        LD A, (DE)              ; header byte: decay flag
        LD (MUS_DECAY), A
        INC DE
        LD (MUS_START), DE
        LD (MUS_PTR), DE
        XOR A
        LD (MUS_TIMER), A
        LD A, 15
        LD (MUS_VOL0), A
        LD (MUS_VOL1), A
        RET

MusicStart:
        LD A, TRK_MUS_ATTRACT
        JP MusicPlay

; ----------------------------------------------------------------------------
; Per-frame update (handles ch0/ch1 music + ch2/ch3 SFX)
; ----------------------------------------------------------------------------
SoundFrame:
        LD A, (GAME + G_PAUSE)
        OR A
        JP NZ, SoundSilenceAll

        ; ---- Music channels (0 & 1) ----
        LD HL, (MUS_PTR)
        LD A, H
        OR L
        JP Z, sf_sfx

        LD A, (MUS_TIMER)
        OR A
        JR Z, sf_next_ev
        DEC A
        LD (MUS_TIMER), A

        ; Staccato release on final frame for non-decay tracks, or smooth decay
        LD B, A
        LD A, (MUS_DECAY)
        OR A
        JR NZ, sf_decay
        LD A, B
        CP 1
        JP NZ, sf_sfx
        XOR A
        LD B, 15
        CALL PsgVol
        LD A, 1
        LD B, 15
        CALL PsgVol
        JP sf_sfx

sf_decay:
        LD A, (MUS_ENV_DIV)
        INC A
        LD (MUS_ENV_DIV), A
        AND 3
        JP NZ, sf_sfx
        LD A, (MUS_VOL0)
        CP 13
        JR NC, sf_dec1
        INC A
        LD (MUS_VOL0), A
        LD B, A
        XOR A
        CALL PsgVol
sf_dec1:
        LD A, (MUS_VOL1)
        CP 14
        JP NC, sf_sfx
        INC A
        LD (MUS_VOL1), A
        LD B, A
        LD A, 1
        CALL PsgVol
        JP sf_sfx

sf_next_ev:
        LD HL, (MUS_PTR)
        LD A, (HL)
        CP $FF
        JR Z, sf_stop_mus
        CP $FE
        JR NZ, sf_read_ev
        LD HL, (MUS_START)
        LD A, (HL)
sf_read_ev:
        LD (MUS_TIMER), A
        INC HL
        LD D, (HL)              ; ch0 note (0 = rest, 1..64)
        INC HL
        LD E, (HL)              ; ch1 note (0 = rest, 1..64)
        INC HL
        LD (MUS_PTR), HL
        XOR A
        LD (MUS_ENV_DIV), A

        ; Channel 0
        PUSH DE
        LD A, D
        OR A
        JR NZ, sf_play_c0
        LD A, 15
        LD (MUS_VOL0), A
        LD B, 15
        XOR A
        CALL PsgVol
        JR sf_do_c1
sf_play_c0:
        DEC A
        LD L, A
        LD H, 0
        ADD HL, HL
        LD BC, ARCADE_PERIOD_TABLE
        ADD HL, BC
        LD C, (HL)
        INC HL
        LD H, (HL)
        LD L, C
        XOR A
        CALL PsgTone
        LD A, 2
        LD (MUS_VOL0), A
        LD B, 2
        XOR A
        CALL PsgVol

sf_do_c1:
        POP DE
        LD A, E
        OR A
        JR NZ, sf_play_c1
        LD A, 15
        LD (MUS_VOL1), A
        LD B, 15
        LD A, 1
        CALL PsgVol
        JR sf_sfx
sf_play_c1:
        DEC A
        LD L, A
        LD H, 0
        ADD HL, HL
        LD BC, ARCADE_PERIOD_TABLE
        ADD HL, BC
        LD C, (HL)
        INC HL
        LD H, (HL)
        LD L, C
        LD A, 1
        CALL PsgTone
        LD A, 4
        LD (MUS_VOL1), A
        LD B, 4
        LD A, 1
        CALL PsgVol
        JR sf_sfx

sf_stop_mus:
        LD HL, 0
        LD (MUS_PTR), HL
        LD A, TRK_NONE
        LD (MUS_CUR_TRK), A
        XOR A
        LD B, 15
        CALL PsgVol
        LD A, 1
        LD B, 15
        CALL PsgVol

        ; ---- SFX channels (Tone 2 + Noise 3) ----
sf_sfx:
        LD HL, (SFX_PTR)
        LD A, H
        OR L
        RET Z
        LD A, (SFX_TIMER)
        OR A
        JR Z, sfx_step_next
        DEC A
        LD (SFX_TIMER), A
        RET

sfx_step_next:
        LD HL, (SFX_PTR)
        LD A, (HL)
        OR A
        JR Z, sfx_end
        CP $FE
        JR Z, sfx_death_tail
        LD (SFX_TIMER), A
        INC HL
        LD D, (HL)              ; low nibble = vol2, high nibble = vol_noise
        INC HL
        LD E, (HL)              ; period low
        INC HL
        LD B, (HL)              ; bits 1..0 = period hi, bits 4..2 = noise ctrl, bit7 = set noise
        INC HL
        LD (SFX_PTR), HL

        PUSH BC
        PUSH DE
        ; Tone 2 period + volume
        LD L, E
        LD A, B
        AND $03
        LD H, A
        LD A, 2
        CALL PsgTone
        POP DE
        PUSH DE
        LD A, D
        AND $0F
        LD B, A
        LD A, 2
        CALL PsgVol
        POP DE
        POP BC

        ; Noise control + volume
        BIT 7, B
        JR Z, sfx_nvol
        LD A, B
        RRCA
        RRCA
        AND $07
        CALL PsgNoise
sfx_nvol:
        LD A, D
        RRCA
        RRCA
        RRCA
        RRCA
        AND $0F
        LD B, A
        LD A, 3
        JP PsgVol

sfx_death_tail:
        CALL sfx_end
        LD A, TRK_MUS_DEATH_TAIL
        JP MusicPlay

sfx_end:
        LD HL, 0
        LD (SFX_PTR), HL
        LD A, 2
        LD B, 15
        CALL PsgVol
        LD A, 3
        LD B, 15
        JP PsgVol

; ----------------------------------------------------------------------------
; SFX Triggers (HL = SFX_*_DATA)
; ----------------------------------------------------------------------------
PlaySfxHL:
        LD (SFX_PTR), HL
        XOR A
        LD (SFX_TIMER), A
        RET

SoundJump:
        LD HL, SFX_JUMP_DATA
        JP PlaySfxHL

SoundStep:
        ; Don't interrupt active louder SFX!
        LD HL, (SFX_PTR)
        LD A, H
        OR L
        RET NZ
        LD A, (MUS_STEP_TOGGLE)
        XOR 1
        LD (MUS_STEP_TOGGLE), A
        JR Z, ss_2
        LD HL, SFX_STEP1_DATA
        JP PlaySfxHL
ss_2:
        LD HL, SFX_STEP2_DATA
        JP PlaySfxHL

SoundClimb:
        LD HL, (SFX_PTR)
        LD A, H
        OR L
        RET NZ
        LD HL, SFX_CLIMB_DATA
        JP PlaySfxHL

SoundScore:
        LD HL, SFX_SCORE_DATA
        JP PlaySfxHL

SoundSmash:
        LD HL, SFX_SMASH_DATA
        JP PlaySfxHL

SoundItem:
        LD HL, SFX_ITEM_DATA
        JP PlaySfxHL

SoundRivet:
        LD HL, SFX_RIVET_DATA
        JP PlaySfxHL

SoundSpring:
        LD HL, (SFX_PTR)
        LD A, H
        OR L
        RET NZ
        LD HL, SFX_SPRING_DATA
        JP PlaySfxHL

SoundSpringDrop:
        LD HL, SFX_SPRING_DROP_DATA
        JP PlaySfxHL

SoundThrow:
        LD HL, (SFX_PTR)
        LD A, H
        OR L
        RET NZ
        LD HL, SFX_THROW_DATA
        JP PlaySfxHL

SoundRoar:
        LD HL, SFX_ROAR_DATA
        JP PlaySfxHL

SoundTick:
        LD HL, SFX_TICK_DATA
        JP PlaySfxHL

Sound1Up:
        LD HL, SFX_1UP_DATA
        JP PlaySfxHL

SoundPause:
        LD HL, SFX_PAUSE_DATA
        JP PlaySfxHL

SoundDie:
        LD A, TRK_NONE
        CALL MusicPlay
        LD HL, SFX_DIE_DATA
        JP PlaySfxHL

SoundWin:
        LD A, TRK_MUS_STAGE_CLEAR
        JP MusicPlay

; A = 1..16 -> trigger SFX by index for Sound & Stage Lab
SfxPlayForce:
        DEC A
        AND 15
        ADD A, A
        LD L, A
        LD H, 0
        LD DE, SFX_TABLE
        ADD HL, DE
        LD E, (HL)
        INC HL
        LD D, (HL)
        EX DE, HL
        JP PlaySfxHL

SFX_TABLE:
        DW SFX_JUMP_DATA, SFX_STEP1_DATA, SFX_STEP2_DATA, SFX_CLIMB_DATA
        DW SFX_SCORE_DATA, SFX_SMASH_DATA, SFX_ITEM_DATA, SFX_RIVET_DATA
        DW SFX_SPRING_DATA, SFX_SPRING_DROP_DATA, SFX_THROW_DATA, SFX_ROAR_DATA
        DW SFX_TICK_DATA, SFX_1UP_DATA, SFX_PAUSE_DATA, SFX_DIE_DATA

        INCLUDE "src/snddata.asm"
