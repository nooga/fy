( Polyphonic ADSR synthesizer - 17 voice callback-driven sine )
import "libm"
import "raylib"

( --- Colors --- )
: rgba  24 << swap 16 << or swap 8 << or swap or ;
:: BG     1 1 1 255 rgba ;
:: FG     180 175 165 255 rgba ;
:: AMBER  255 176 0 255 rgba ;

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
    dup libm:sin r> f* 0.2 f* 32000.0 f* f>i  ( va phase' sample )
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

( --- Display constants --- )
:: KB_X 60 ;    :: KB_Y 290 ;
:: KB_W 40 ;    :: KB_P 40 ;
:: KB_H 130 ;   :: WAVE_Y 162 ;

( --- Custom font --- )
:: font-buf 48 alloc ;
:: _tx 8 alloc ;  :: _ty 8 alloc ;
:: _tfs 8 alloc ; :: _tc 8 alloc ;

: text ( str x y fontSize color -- )
  _tc !64 i>f _tfs !64 i>f _ty !64 i>f _tx !64
  font-buf swap _tx @64 _ty @64 _tfs @64 0.0 _tc @64
  raylib:DrawTextEx
;

( --- Waveform display --- )
:: wave-x 8 alloc ;
:: wave-buf 128 4 * alloc ;

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
    85.0 f* f>i WAVE_Y swap -
    over 4 * wave-buf + !32
    1+
  ] dotimes
  drop
;

: draw-wave-path ( -- )
  0
  127 [
    >r
    r@ 680 * 127 / KB_X +
    r@ 4 * wave-buf + @32
    r@ 1 + 680 * 127 / KB_X +
    r@ 1 + 4 * wave-buf + @32
    AMBER raylib:DrawLine
    r> 1 +
  ] dotimes
  drop
;

: draw-waveform ( -- )
  KB_X WAVE_Y 740 WAVE_Y FG raylib:DrawLine
  compute-waveform
  draw-wave-path
;

( --- Keyboard drawing --- )
:: _kc 8 alloc ;

( Voice indices in chromatic order )
:: kb-map [
  [ 0 0 ]   [ 1 10 ]  [ 2 1 ]   [ 3 11 ]  [ 4 2 ]
  [ 5 3 ]   [ 6 12 ]  [ 7 4 ]   [ 8 13 ]  [ 9 5 ]
  [ 10 14 ] [ 11 6 ]  [ 12 7 ]  [ 13 15 ] [ 14 8 ]
  [ 15 16 ] [ 16 9 ]
] ;

: amber-env ( env -- color )
  dup 0.0 f> [
    dup 255.0 f* f>i swap 176.0 f* f>i 0 255 rgba
  ] [
    drop BG
  ] ifte
;

: draw-one-key ( [pos vidx] -- )
  do
  voice Voice.env@ nip
  amber-env _kc !64
  KB_P * KB_X +
  dup KB_Y KB_W KB_H _kc @64 raylib:DrawRectangle
  KB_Y KB_W KB_H FG raylib:DrawRectangleLines
;

: draw-keys  kb-map \draw-one-key each drop ;

( --- Main --- )
800 500 "fy - Poly Synth" raylib:InitWindow
60 raylib:SetTargetFPS
raylib:InitAudioDevice

font-buf "/System/Library/Fonts/SFNS.ttf" 64 0 0 raylib:LoadFontEx drop
font-buf 12 + 1 raylib:SetTextureFilter

MAX_SAMPLES_PER_UPDATE raylib:SetAudioStreamBufferSizeDefault
AudioStream.alloc 44100 16 1 raylib:LoadAudioStream stream-cell !64

stream audio-cb raylib:SetAudioStreamCallback
stream raylib:PlayAudioStream

: frame
  check-keys
  check-octave

  raylib:BeginDrawing
    BG raylib:ClearBackground
    "organ.fy" KB_X 20 20 FG text
    draw-waveform
    draw-keys
  raylib:EndDrawing
;

: running? raylib:WindowShouldClose 0 = ;
running? [ drop frame running? ] repeat

stream raylib:StopAudioStream
stream raylib:UnloadAudioStream
font-buf raylib:UnloadFont
raylib:CloseAudioDevice
raylib:CloseWindow
