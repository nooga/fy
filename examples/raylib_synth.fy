( Audio synthesizer demo - callback-driven sine wave )
import "libm"
import "raylib"

( --- Colors --- )
: rgba  24 << swap 16 << or swap 8 << or swap or ;
:: RAYWHITE  245 245 245 255 rgba ;
:: DARKGRAY  80 80 80 255 rgba ;
:: LIGHTGRAY 200 200 200 255 rgba ;
:: GREEN     0 228 48 255 rgba ;
:: DARKBLUE  0 82 172 255 rgba ;

( --- Audio constants --- )
:: MAX_SAMPLES_PER_UPDATE 4096 ;
:: TWO_PI 6.283185307179586 ;

( --- AudioStream struct --- )
struct: AudioStream
  ptr buffer  ptr processor
  u32 sampleRate  u32 sampleSize  u32 channels
;

( --- Mutable state cells --- )
:: phase-cell 8 alloc ;
:: freq-cell  8 alloc ;
:: play-cell  4 alloc ;
:: stream-cell 8 alloc ;

0.0 phase-cell !64
440.0 freq-cell !64
0 play-cell !32

: stream stream-cell @64 ;

( --- Keyboard input --- )
: check-key ( key freq -- ) swap raylib:IsKeyDown
  [ freq-cell !64  1 play-cell !32 ] [ drop ] ifte ;

: check-keys
  0 play-cell !32
  90  261.63 check-key   ( Z = C4 )
  88  293.66 check-key   ( X = D4 )
  67  329.63 check-key   ( C = E4 )
  86  349.23 check-key   ( V = F4 )
  66  392.00 check-key   ( B = G4 )
  78  440.00 check-key   ( N = A4 )
  77  493.88 check-key   ( M = B4 )
  44  523.25 check-key   ( , = C5 )
  46  587.33 check-key   ( . = D5 )
  47  659.25 check-key   ( / = E5 )
;

( --- Sample generation --- )
: gen-sample ( -- sample )
  phase-cell @64
  dup libm:sin 0.25 f* 32000.0 f*
  f>i
  swap
  freq-cell @64 TWO_PI f* 44100.0 f/ f+
  dup TWO_PI f> [ TWO_PI f- ] [ ] ifte
  phase-cell !64
;

( --- Audio callback --- )
( Called on audio thread: buf frames -- )
: audio-fill
  0 swap                                   ( buf 0 frames )
  [                                        ( buf i )
    play-cell @32 [
      over over 2 * +                     ( buf i addr )
      gen-sample                           ( buf i addr sample )
      swap !16                             ( buf i )
    ] [
      over over 2 * + 0 swap !16          ( buf i )
    ] ifte
    1+
  ] dotimes
  drop drop
;

:: audio-cb callback: pi:v audio-fill ;

( --- Waveform drawing --- )
( Compute sine inline at current freq, no buffer needed )
: draw-waveform ( -- )
  0
  128 [
    dup i>f freq-cell @64 f* TWO_PI f* 44100.0 f/
    libm:sin 120.0 f* f>i
    280 swap -
    over 5 * 50 +
    swap 2.0 GREEN raylib:DrawCircle
    1+
  ] dotimes
  drop
;

( --- Main --- )
800 500 "fy - Audio Synth" raylib:InitWindow
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
    "fy - Audio Synthesizer" 50 20 30 DARKBLUE raylib:DrawText
    "Press Z X C V B N M , . / to play notes" 50 60 20 DARKGRAY raylib:DrawText
    "C4  D4  E4  F4  G4  A4  B4  C5  D5  E5" 50 85 16 LIGHTGRAY raylib:DrawText

    ( Waveform )
    50 150 690 260 LIGHTGRAY raylib:DrawRectangleLines
    play-cell @32 [
      draw-waveform
      "Playing" 650 20 20 GREEN raylib:DrawText
    ] [
      "Silent" 650 20 20 DARKGRAY raylib:DrawText
    ] ifte

    10 475 raylib:DrawFPS
  raylib:EndDrawing
;

: running? raylib:WindowShouldClose 0 = ;
running? [ drop frame running? ] repeat

stream raylib:StopAudioStream
stream raylib:UnloadAudioStream
raylib:CloseAudioDevice
raylib:CloseWindow
