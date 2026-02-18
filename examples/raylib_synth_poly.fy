( Polyphonic ADSR synthesizer - 10 voice callback-driven sine )
import "libm"
import "raylib"

( --- Colors --- )
: rgba  24 << swap 16 << or swap 8 << or swap or ;
:: RAYWHITE  245 245 245 255 rgba ;
:: DARKGRAY  80 80 80 255 rgba ;
:: LIGHTGRAY 200 200 200 255 rgba ;
:: GREEN     0 228 48 255 rgba ;
:: DARKBLUE  0 82 172 255 rgba ;

( --- Constants --- )
:: MAX_SAMPLES_PER_UPDATE 4096 ;
:: TWO_PI 6.283185307179586 ;
:: SAMPLE_RATE 44100.0 ;
:: NUM_VOICES 10 ;

( --- ADSR parameters --- )
:: ATTACK  0.003  ;   ( ~7ms to peak     )
:: DECAY   0.0001 ;   ( ~136ms to sustain )
:: SUSTAIN 0.4    ;   ( sustain level     )
:: RELEASE 0.0001 ;   ( ~90ms to silence  )

( --- Vibrato LFO --- )
:: VIB_RATE  6.0 ;     ( LFO speed in Hz — classic organ range )
:: VIB_DEPTH 0.003 ;   ( pitch deviation — subtle, organ-like )

( --- ADSR stages --- )
:: IDLE 0 ;  :: ATK 1 ;  :: DEC 2 ;  :: SUS 3 ;  :: REL 4 ;

( --- Voice struct --- )
( Generates: Voice.size Voice.alloc Voice.new )
( Per field: Voice.phase@ Voice.phase! etc )
( Accessors are ptr-preserving: )
(   Voice.field@ : ptr -- ptr value )
(   Voice.field! : value ptr -- ptr )
struct: Voice
  f64 phase  f64 freq  f64 env  i32 stage
;

:: voices NUM_VOICES Voice.size * alloc ;
:: lfo-phase 8 alloc ;
: voice ( i -- addr ) Voice.size * voices + ;

( --- Initialize voices --- )
: init-voices
  NUM_VOICES [
    dup voice
    0.0 swap Voice.phase!
    440.0 swap Voice.freq!
    0.0 swap Voice.env!
    IDLE swap Voice.stage!
    drop
    1+
  ] dotimes drop
;
init-voices

( --- AudioStream struct --- )
struct: AudioStream
  ptr buffer  ptr processor
  u32 sampleRate  u32 sampleSize  u32 channels
;
:: stream-cell 8 alloc ;
: stream stream-cell @64 ;

( --- ADSR envelope --- )
( Pattern: read env, adjust, clamp+transition if past threshold, write back )
: env-attack ( va -- )
  Voice.env@ ATTACK f+
  dup 1.0 f> [ drop DEC swap Voice.stage! 1.0 ] [ ] ifte
  swap Voice.env! drop
;

: env-decay ( va -- )
  Voice.env@ DECAY f-
  dup SUSTAIN f< [ drop SUS swap Voice.stage! SUSTAIN ] [ ] ifte
  swap Voice.env! drop
;

: env-release ( va -- )
  Voice.env@ RELEASE f-
  dup 0.0 f< [ drop IDLE swap Voice.stage! 0.0 ] [ ] ifte
  swap Voice.env! drop
;

: env-step ( va -- )
  Voice.stage@
  dup ATK = [ drop env-attack  ] [
  dup DEC = [ drop env-decay   ] [
  dup REL = [ drop env-release ] [
  drop drop ] ifte ] ifte ] ifte
;

( --- Keyboard input --- )
:: key-data [
  [ 90 261.63 0 ]  ( Z = C4 )   [ 88 293.66 1 ]  ( X = D4 )
  [ 67 329.63 2 ]  ( C = E4 )   [ 86 349.23 3 ]  ( V = F4 )
  [ 66 392.00 4 ]  ( B = G4 )   [ 78 440.00 5 ]  ( N = A4 )
  [ 77 493.88 6 ]  ( M = B4 )   [ 44 523.25 7 ]  ( , = C5 )
  [ 46 587.33 8 ]  ( . = D5 )   [ 47 659.25 9 ]  ( / = E5 )
] ;

: check-one ( [key freq idx] -- )
  do voice rot raylib:IsKeyDown
  [ ( freq va -- key down )
    tuck Voice.freq! drop
    Voice.stage@ dup IDLE = swap REL = or
    [ ATK swap Voice.stage! drop ] [ drop ] ifte
  ] [ ( freq va -- key up )
    nip
    Voice.stage@ dup 0 > swap 4 < &
    [ REL swap Voice.stage! drop ] [ drop ] ifte
  ] ifte
;

: check-keys  key-data \check-one each drop ;

( --- Sample generation --- )
: gen-voice-sample ( va -- sample )
  Voice.stage@ 0 > [
    dup env-step
    Voice.env@ >r
    Voice.phase@
    over Voice.freq@ nip
    lfo-phase @64 libm:sin VIB_DEPTH f* 1.0 f+ f*
    TWO_PI f* SAMPLE_RATE f/ f+           ( va phase' )
    dup libm:sin r> f* 0.025 f* 32000.0 f* f>i  ( va phase' sample )
    -rot                                   ( sample va phase' )
    dup TWO_PI f> [ TWO_PI f- ] [ ] ifte
    swap Voice.phase! drop                 ( sample )
  ] [
    drop 0
  ] ifte
;

: mix-voices ( -- sample )
  0 0
  NUM_VOICES [
    dup voice gen-voice-sample
    rot + swap
    1+
  ] dotimes
  drop
  ( advance LFO phase )
  lfo-phase @64 VIB_RATE TWO_PI f* SAMPLE_RATE f/ f+
  dup TWO_PI f> [ TWO_PI f- ] [ ] ifte
  lfo-phase !64
;

( --- Audio callback --- )
: audio-fill ( buf frames -- )
  0 swap
  [ over over 2 * + mix-voices swap !16 1+ ]
  dotimes drop drop
;

:: audio-cb callback: pi:v audio-fill ;

( --- Display helpers --- )
: active-count ( -- n )
  0 0
  NUM_VOICES [
    dup voice Voice.stage@ nip 0 > rot + swap
    1+
  ] dotimes drop
;

:: wave-x 8 alloc ;

: draw-waveform ( -- )
  0
  128 [
    dup i>f wave-x !64
    0.0 0
    NUM_VOICES [
      dup voice Voice.stage@ 0 > [
        Voice.env@ >r
        Voice.freq@ nip wave-x @64 f*
        TWO_PI f* SAMPLE_RATE f/
        libm:sin r> f* rot f+ swap
      ] [
        drop
      ] ifte
      1+
    ] dotimes
    drop
    120.0 f* f>i 280 swap -
    over 5 * 50 + swap
    2.0 GREEN raylib:DrawCircle
    1+
  ] dotimes
  drop
;

( --- Main --- )
800 500 "fy - Poly Synth" raylib:InitWindow
60 raylib:SetTargetFPS
raylib:InitAudioDevice

MAX_SAMPLES_PER_UPDATE raylib:SetAudioStreamBufferSizeDefault
AudioStream.alloc 44100 16 1 raylib:LoadAudioStream stream-cell !64

stream audio-cb raylib:SetAudioStreamCallback
stream raylib:PlayAudioStream

: frame
  check-keys

  raylib:BeginDrawing
    RAYWHITE raylib:ClearBackground
    "fy - Polyphonic Synth" 50 20 30 DARKBLUE raylib:DrawText

    50 150 690 260 LIGHTGRAY raylib:DrawRectangleLines
    active-count 0 > [
      draw-waveform
      "Playing" 650 20 20 GREEN raylib:DrawText
    ] [
      "Silent" 650 20 20 DARKGRAY raylib:DrawText
    ] ifte

    "Z X C V B N M , . /" 50 460 20 DARKGRAY raylib:DrawText
    10 475 raylib:DrawFPS
  raylib:EndDrawing
;

: running? raylib:WindowShouldClose 0 = ;
running? [ drop frame running? ] repeat

stream raylib:StopAudioStream
stream raylib:UnloadAudioStream
raylib:CloseAudioDevice
raylib:CloseWindow
