( Polyphonic audio synthesizer - 10 voice callback-driven sine )
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

( --- Voice memory block --- )
( Each voice: f64 phase [0], f64 freq [8], i32 active [16] = 24 bytes )
:: VOICE_SIZE 24 ;
:: voices NUM_VOICES VOICE_SIZE * alloc ;

: voice     ( i -- addr )      VOICE_SIZE * voices + ;
: v-phase@  ( addr -- f64 )    @64 ;
: v-freq@   ( addr -- f64 )    8 + @64 ;
: v-active@ ( addr -- i32 )    16 + @32 ;
: v-phase!  ( f64 addr -- )    !64 ;
: v-freq!   ( f64 addr -- )    8 + !64 ;
: v-active! ( i32 addr -- )    16 + !32 ;

( --- Initialize voices --- )
: init-voices
  NUM_VOICES [
    dup voice
    0.0 over v-phase!
    440.0 over v-freq!
    0 swap v-active!
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
  [ tuck v-freq! 1 swap v-active! ]
  [ nip 0 swap v-active! ]
  ifte
;

: check-keys  key-data \check-one each drop ;

( --- Sample generation --- )
: gen-voice-sample ( va -- sample )
  dup v-active@ [
    dup v-phase@                            ( va phase )
    dup libm:sin 0.025 f* 32000.0 f* f>i    ( va phase sample )
    swap rot dup                            ( sample phase va va )
    v-freq@ TWO_PI f* SAMPLE_RATE f/        ( sample phase va incr )
    rot f+                                  ( sample va phase' )
    dup TWO_PI f> [ TWO_PI f- ] [ ] ifte    ( sample va phase' )
    swap v-phase!                           ( sample )
  ] [
    drop 0
  ] ifte
;

: mix-voices ( -- sample )
  0 0
  NUM_VOICES [
    dup voice gen-voice-sample              ( acc i sample )
    rot + swap                              ( acc' i )
    1+
  ] dotimes
  drop
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
    dup voice v-active@ rot + swap
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
      dup voice dup v-active@ [             ( acc j va )
        v-freq@ wave-x @64 f*
        TWO_PI f* SAMPLE_RATE f/
        libm:sin rot f+ swap               ( acc' j )
      ] [
        drop                                ( acc j )
      ] ifte
      1+
    ] dotimes
    drop                                    ( i acc )
    120.0 f* f>i 280 swap -                 ( i y )
    over 5 * 50 + swap                      ( i x y )
    2.0 GREEN raylib:DrawCircle             ( i )
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
