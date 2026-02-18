( Polyphonic ADSR synthesizer - 17 voice callback-driven sine )
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
:: NUM_VOICES 17 ;

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

( --- Octave state --- )
:: octave-cell 8 alloc ;
: octave octave-cell @64 ;
: octave! octave-cell !64 ;
4 octave!

( --- Frequency from semitone + octave --- )
( freq = 440 * 2^(oct + semi/12 - 4.75) )
: semitone>freq ( semi -- freq )
  i>f 12.0 f/ octave i>f f+ 4.75 f-
  2.0 swap libm:pow 440.0 f*
;

( --- AudioStream struct --- )
struct: AudioStream
  ptr buffer  ptr processor
  u32 sampleRate  u32 sampleSize  u32 channels
;
:: stream-cell 8 alloc ;
: stream stream-cell @64 ;

( --- ADSR envelope --- )
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

( --- Piano key mapping --- )
( White keys on ASDF row, black keys on QWERTY row )
( [raylib-key semitone voice-index] )
:: key-data [
  [ 65  0  0 ]   ( A = C  )   [ 83  2  1 ]   ( S = D  )
  [ 68  4  2 ]   ( D = E  )   [ 70  5  3 ]   ( F = F  )
  [ 71  7  4 ]   ( G = G  )   [ 72  9  5 ]   ( H = A  )
  [ 74  11 6 ]   ( J = B  )   [ 75  12 7 ]   ( K = C' )
  [ 76  14 8 ]   ( L = D' )   [ 59  16 9 ]   ( ; = E' )
  [ 87  1  10 ]  ( W = C# )   [ 69  3  11 ]  ( E = D# )
  [ 84  6  12 ]  ( T = F# )   [ 89  8  13 ]  ( Y = G# )
  [ 85  10 14 ]  ( U = A# )   [ 79  13 15 ]  ( O = C#')
  [ 80  15 16 ]  ( P = D#')
] ;

: check-one ( [key semi idx] -- )
  do voice rot raylib:IsKeyDown
  [ ( semi va -- key down: set freq, trigger attack )
    over semitone>freq swap Voice.freq! nip
    Voice.stage@ dup IDLE = swap REL = or
    [ ATK swap Voice.stage! drop ] [ drop ] ifte
  ] [ ( semi va -- key up: trigger release )
    nip
    Voice.stage@ dup 0 > swap 4 < &
    [ REL swap Voice.stage! drop ] [ drop ] ifte
  ] ifte
;

: check-keys  key-data \check-one each drop ;

: check-octave
  90 raylib:IsKeyPressed [
    octave 1 > [ octave 1 - octave! ] [ ] ifte
  ] [ ] ifte
  88 raylib:IsKeyPressed [
    octave 7 < [ octave 1 + octave! ] [ ] ifte
  ] [ ] ifte
;

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
:: wave-buf 128 4 * alloc ;

( Compute waveform y-coordinates into wave-buf )
: compute-waveform ( -- )
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
    85.0 f* f>i 162 swap -
    over 4 * wave-buf + !32
    1+
  ] dotimes
  drop
;

( Draw connected line segments from wave-buf )
: draw-wave-path ( -- )
  0
  127 [
    >r
    r@ 5 * 50 +
    r@ 4 * wave-buf + @32
    r@ 1 + 5 * 50 +
    r@ 1 + 4 * wave-buf + @32
    GREEN raylib:DrawLine
    r> 1 +
  ] dotimes
  drop
;

: draw-waveform ( -- )
  50 162 690 162 LIGHTGRAY raylib:DrawLine
  compute-waveform
  draw-wave-path
;

( --- Keyboard drawing --- )
:: KB_X 60 ;   :: KB_Y 290 ;
:: KB_W 64 ;   :: KB_P 68 ;    ( width + 4px gap )
:: KB_H 130 ;
:: BK_W 40 ;   :: BK_H 80 ;
:: temp-x 8 alloc ;

( Draw 10 white key rectangles )
: draw-white-keys
  0
  10 [
    dup KB_P * KB_X +              ( i x )
    over voice Voice.stage@ nip 0 >
    [ GREEN ] [ LIGHTGRAY ] ifte
    >r
    dup KB_Y KB_W KB_H r> raylib:DrawRectangle
    KB_Y KB_W KB_H DARKGRAY raylib:DrawRectangleLines
    1+
  ] dotimes
  drop
;

( Black key positions: [voice-idx white-key-pos] )
:: bk-pos [
  [ 10 0 ]  [ 11 1 ]  [ 12 3 ]  [ 13 4 ]
  [ 14 5 ]  [ 15 7 ]  [ 16 8 ]
] ;

: draw-one-bk ( [vidx wpos] -- )
  do                                       ( vidx wpos )
  KB_P * KB_X + KB_W + 2 + BK_W 2 / -     ( vidx bx )
  swap voice Voice.stage@ nip 0 >
  [ DARKBLUE ] [ DARKGRAY ] ifte
  >r
  dup KB_Y BK_W BK_H r> raylib:DrawRectangle
  drop
;

: draw-black-keys  bk-pos \draw-one-bk each drop ;

( White key labels: [position-idx note-name key-shortcut] )
:: wk-labels [
  [ 0 "C" "a" ]  [ 1 "D" "s" ]  [ 2 "E" "d" ]  [ 3 "F" "f" ]
  [ 4 "G" "g" ]  [ 5 "A" "h" ]  [ 6 "B" "j" ]  [ 7 "C" "k" ]
  [ 8 "D" "l" ]  [ 9 "E" ";" ]
] ;

: draw-wk-label ( [idx note keylbl] -- )
  do                                       ( idx note keylbl )
  rot KB_P * KB_X + 24 +                   ( note keylbl lx )
  temp-x !64                               ( note keylbl )
  temp-x @64 KB_Y 95 + 12 DARKGRAY raylib:DrawText
  temp-x @64 KB_Y 15 + 16 DARKBLUE raylib:DrawText
;

: draw-white-labels  wk-labels \draw-wk-label each drop ;

( Black key labels: [white-key-pos key-shortcut] )
:: bk-labels [
  [ 0 "w" ]  [ 1 "e" ]  [ 3 "t" ]  [ 4 "y" ]
  [ 5 "u" ]  [ 7 "o" ]  [ 8 "p" ]
] ;

: draw-bk-label ( [wpos keylbl] -- )
  do                                       ( wpos keylbl )
  swap KB_P * KB_X + KB_W + 2 + BK_W 2 / - 14 +
  KB_Y 50 + 11 RAYWHITE raylib:DrawText
;

: draw-black-labels  bk-labels \draw-bk-label each drop ;

( Octave display text )
: oct-text
  octave
  dup 0 = [ drop "Oct 0" ] [
  dup 1 = [ drop "Oct 1" ] [
  dup 2 = [ drop "Oct 2" ] [
  dup 3 = [ drop "Oct 3" ] [
  dup 4 = [ drop "Oct 4" ] [
  dup 5 = [ drop "Oct 5" ] [
  dup 6 = [ drop "Oct 6" ] [
  drop "Oct 7" ] ifte ] ifte ] ifte ] ifte ] ifte ] ifte ] ifte
;

: draw-keyboard
  draw-white-keys
  draw-black-keys
  draw-white-labels
  draw-black-labels
  oct-text 345 432 20 DARKBLUE raylib:DrawText
  "[Z] octave [X]" 300 455 14 DARKGRAY raylib:DrawText
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
  check-octave

  raylib:BeginDrawing
    RAYWHITE raylib:ClearBackground
    "fy - Polyphonic Synth" 50 15 30 DARKBLUE raylib:DrawText

    draw-waveform
    active-count 0 > [
      "Playing" 650 15 20 GREEN raylib:DrawText
    ] [
      "Silent" 650 15 20 DARKGRAY raylib:DrawText
    ] ifte

    draw-keyboard
    10 480 raylib:DrawFPS
  raylib:EndDrawing
;

: running? raylib:WindowShouldClose 0 = ;
running? [ drop frame running? ] repeat

stream raylib:StopAudioStream
stream raylib:UnloadAudioStream
raylib:CloseAudioDevice
raylib:CloseWindow
