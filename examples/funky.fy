( funky.fy - Live-coding DSL for audio and patterns )
import "libm"
import "raylib"

( --- Colors --- )
: rgba  24 << swap 16 << or swap 8 << or swap or ;

( --- Constants --- )
:: TWO_PI 6.283185307179586 ;
:: SAMPLE_RATE 44100.0 ;

( --- Global Time and BPM --- )
:: bpm-cell 8 alloc ;
: bpm ( b -- ) i>f bpm-cell f!32 ;
: current-bpm ( -- f ) bpm-cell f@32 ;
120 bpm

:: time-cell 8 alloc ;
: global-time ( -- f ) time-cell @64 ;
: global-time! ( f -- ) time-cell !64 ;
0.0 global-time!

( --- Event Struct --- )
struct: Event
  f64 start
  f64 dur
  f64 freq
  f64 gain
  f64 param1
  i64 inst    ( instrument quote or callback fptr )
;

:: MAX_VOICES 32 ;
:: voices MAX_VOICES Event.size * alloc ;
: voice ( i -- addr ) Event.size * voices + ;

:: num-active-voices 8 alloc ;
0 num-active-voices !64

( --- Basic DSP --- )
: fmod ( a b -- a%b )
  over over f/ f>i i>f f* f-
;

: sine ( t freq -- sample )
  f* TWO_PI f* libm:sin
;

: saw ( t freq -- sample )
  f* 1.0 fmod 2.0 f* 1.0 f-
;

: rest ( ev t -- sample ) drop drop 0.0 ;
: ~ rest ;

:: noise-state 8 alloc ;
48271 noise-state !64
: noise ( -- sample, white noise -1.0 to 1.0 )
  noise-state @64 1103515245 * 12345 +
  dup noise-state !64
  20 >> 4095 & i>f 2048.0 f/ 1.0 f-
;

: midi2hz ( midi -- freq )
  i>f 69.0 f- 12.0 f/ 2.0 swap libm:pow 440.0 f*
;

( --- Scene --- )
:: scene-word-cell 8 alloc ;
:: scene-pat-cell 8 alloc ;

( --- Pattern Operators --- )
:: ALT_TAG 31337 ;
:: cycle-cell 8 alloc ;

: fast ( pat n -- pat' )
  qnil swap [ over qpush ] dotimes nip
;

: stack ( pat1 pat2 -- pat', layer two patterns simultaneously )
  qnil swap qpush swap qpush
  qnil swap qpush
;

: alt ( pat -- pat', pick one element per cycle )
  qnil ALT_TAG qpush swap qpush
;

: is-alt? ( q -- flag )
  dup qlen 2 = [
    dup 0 qnth ALT_TAG = nip
  ] [
    drop 0
  ] ifte
;

: is-pair? ( q -- flag, true if [note inst] pair )
  dup qlen 2 = [
    dup 0 qnth-type 0 = nip
  ] [
    drop 0
  ] ifte
;

:: s-inst-cell 8 alloc ;
: s-bind ( pat -- pat', bind s-inst-cell instrument to number leaves )
  [ | pat |
    qnil
    0 pat qlen [
      pat over qnth
      dup int? [
        qnil swap qpush s-inst-cell @64 qpush
      ] [
        dup word? [
        ] [
          s-inst-cell @64 s
        ] ifte
      ] ifte
      rot swap qpush swap
      1+
    ] dotimes
    drop
  ] do
;
: s ( pat inst -- pat', bind instrument to number leaves )
  s-inst-cell !64
  dup is-alt? [
    1 qnth s-inst-cell @64 s
    qnil ALT_TAG qpush swap qpush
  ] [
    s-bind
  ] ifte
;

( --- Timing --- )
:: last-cycle-cell 8 alloc ;
-1 last-cycle-cell !64

: cycle>sec ( cycle -- sec, 1 cycle = 1 bar = 4 beats )
  240.0 current-bpm f/ f*
;
: sec>cycle ( sec -- cycle )
  current-bpm 240.0 f/ f*
;

( --- Pattern Evaluation (Control Rate) --- )
( Recursively walks pattern, subdividing time for nested quotes.
  [ \bd [ \hh \hh ] \sn \hh ] → bd gets 1/4, each hh gets 1/8, etc. )
:: voice-idx-cell 8 alloc ;

: emit-chord ( notes start dur -- , emit all elements at same start/dur )
  [ | notes start dur |
    0 notes qlen [
      notes over qnth
      start dur
      rot dup word? [
        voice-idx-cell @64 dup 1 + voice-idx-cell !64 voice
        Event.inst!
        rot cycle>sec swap Event.start!
        swap cycle>sec swap Event.dur!
        440.0 swap Event.freq!
        1.0 swap Event.gain!
        drop
      ] [
        dup int? [
          midi2hz
          voice-idx-cell @64 dup 1 + voice-idx-cell !64 voice
          0 swap Event.inst!
          Event.freq!
          rot cycle>sec swap Event.start!
          swap cycle>sec swap Event.dur!
          1.0 swap Event.gain!
          drop
        ] [
          dup is-alt? [
            1 qnth cycle-cell @64 over qlen over over / swap * - qnth
            -rot emit-events
          ] [
          dup is-pair? [
            dup 0 qnth midi2hz
            swap 1 qnth
            voice-idx-cell @64 dup 1 + voice-idx-cell !64 voice
            Event.inst!
            Event.freq!
            rot cycle>sec swap Event.start!
            swap cycle>sec swap Event.dur!
            1.0 swap Event.gain!
            drop
          ] [
            ( chord wrapper detection for nested stacks )
            dup qlen 1 = [
              dup 0 qnth-type 4 = [
                0 qnth -rot emit-chord
              ] [
                -rot emit-events
              ] ifte
            ] [
              -rot emit-events
            ] ifte
          ] ifte
        ] ifte
        ] ifte
      ] ifte
      1+
    ] dotimes
    drop
  ] do
;

: emit-events ( pat start dur -- )
  [ | pat start dur |
    0
    pat qlen [ | i |
      pat i qnth
      start dur pat qlen i>f f/ i i>f f* f+
      dur pat qlen i>f f/
      rot dup word? [
        ( slot-start sub-dur inst-word → allocate voice, fill fields )
        voice-idx-cell @64 dup 1 + voice-idx-cell !64 voice
        Event.inst!
        rot cycle>sec swap Event.start!
        swap cycle>sec swap Event.dur!
        440.0 swap Event.freq!
        1.0 swap Event.gain!
        drop
      ] [
        dup int? [
          ( slot-start sub-dur midi-note → note event, inst=0 )
          midi2hz
          voice-idx-cell @64 dup 1 + voice-idx-cell !64 voice
          0 swap Event.inst!
          Event.freq!
          rot cycle>sec swap Event.start!
          swap cycle>sec swap Event.dur!
          1.0 swap Event.gain!
          drop
        ] [
          dup is-alt? [
            ( alt: pick one element based on cycle number )
            1 qnth cycle-cell @64 over qlen over over / swap * - qnth
            -rot emit-events
          ] [
          dup is-pair? [
            ( slot-start sub-dur [note inst] → combined event )
            dup 0 qnth midi2hz
            swap 1 qnth
            voice-idx-cell @64 dup 1 + voice-idx-cell !64 voice
            Event.inst!
            Event.freq!
            rot cycle>sec swap Event.start!
            swap cycle>sec swap Event.dur!
            1.0 swap Event.gain!
            drop
          ] [
            ( chord detection: [[ a b ]] parses as [ [a b] ] — qlen=1 wrapper )
            dup qlen 1 = [
              dup 0 qnth-type 4 = [
                0 qnth -rot emit-chord
              ] [
                -rot emit-events
              ] ifte
            ] [
              -rot emit-events
            ] ifte
          ] ifte
          ] ifte
        ] ifte
      ] ifte
      i 1 +
    ] dotimes
    drop
  ] do
;

: refresh-scene ( -- , rebuild pattern from scene word on main thread )
  scene-word-cell @64 do scene-pat-cell !64
;

: eval-pattern ( cycle -- )
  dup cycle-cell !64
  scene-pat-cell @64
  dup qempty? [ drop drop 0 num-active-voices !64 ] [
    0 voice-idx-cell !64
    ( detect alt at top level )
    dup is-alt? [
      1 qnth cycle-cell @64 over qlen over over / swap * - qnth
      swap i>f 1.0 emit-events
    ] [
    ( detect stack/chord wrapper: qlen=1 and inner is quote → emit-chord )
    dup qlen 1 = [
      dup 0 qnth-type 4 = [
        0 qnth swap i>f 1.0 emit-chord
      ] [
        swap i>f 1.0 emit-events
      ] ifte
    ] [
      swap i>f 1.0 emit-events
    ] ifte
    ] ifte
    voice-idx-cell @64 num-active-voices !64
  ] ifte
;

( --- Audio Engine (Audio Rate) --- )
:: mix-t-cell 8 alloc ;

: mix-audio ( t -- sample )
  mix-t-cell !64
  0.0 0
  num-active-voices @64 [
    dup voice dup Event.inst@ nip
    dup 0 > [ | ev inst |
      ev Event.gain@ nip
      ev mix-t-cell @64 inst do
      f* rot f+ swap
    ] [ drop drop ] ifte
    1+
  ] dotimes
  drop
;

: audio-fill ( buf frames -- )
  [ | buf frames |
    0
    frames [
      dup i>f SAMPLE_RATE f/ global-time f+

      dup sec>cycle f>i
      dup last-cycle-cell @64 != [
        dup last-cycle-cell !64
        eval-pattern
      ] [ drop ] ifte

      mix-audio 0.5 f* libm:tanh 30000.0 f* f>i

      swap dup 2 * buf + rot swap !16
      1+
    ] dotimes
    drop
    global-time frames i>f SAMPLE_RATE f/ f+ global-time!
  ] do
;

:: audio-cb callback: pi:v audio-fill ;

struct: AudioStream
  ptr buffer  ptr processor
  u32 sampleRate  u32 sampleSize  u32 channels
;
:: stream-cell 8 alloc ;
: stream stream-cell @64 ;

: debug-funky ( scene-word -- , print events for cycle 0 without audio )
  scene-word-cell !64
  120 bpm
  refresh-scene
  0 eval-pattern
  "--- " . num-active-voices @64 . " voices ---" . .nl
  0 num-active-voices @64 [
    dup voice
    "v" . over .
    "  s=" . dup Event.start@ nip f.
    "  d=" . dup Event.dur@ nip f.
    "  f=" . dup Event.freq@ nip f.
    "  g=" . dup Event.gain@ nip f.
    "  i=" . Event.inst@ nip .
    .nl
    1+
  ] dotimes
  drop
;

: play-funky ( scene-word -- )
  scene-word-cell !64
  120 bpm
  0.0 global-time!
  -1 last-cycle-cell !64
  refresh-scene

  800 450 "funky.fy" raylib:InitWindow
  60 raylib:SetTargetFPS
  raylib:InitAudioDevice
  4096 raylib:SetAudioStreamBufferSizeDefault

  AudioStream.alloc 44100 16 1 raylib:LoadAudioStream stream-cell !64
  stream audio-cb raylib:SetAudioStreamCallback
  stream raylib:PlayAudioStream

  : running? raylib:WindowShouldClose 0 = ;
  : frame
    raylib:BeginDrawing
    245 245 245 255 rgba raylib:ClearBackground
    "funky.fy is running!" 10 10 20 80 80 80 255 rgba raylib:DrawText
    raylib:EndDrawing
  ;
  running? [ drop frame running? ] repeat

  stream raylib:StopAudioStream
  stream raylib:UnloadAudioStream
  raylib:CloseAudioDevice
  raylib:CloseWindow
;
