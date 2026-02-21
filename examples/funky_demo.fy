include "funky.fy"

( --- 808 Bass drum: exponential pitch sweep 300->45Hz, long decay --- )
: bd ( ev t -- sample )
  [ | ev t |
    t ev Event.start@ nip f-
    dup 0.0 f< not over 0.5 f< & [ | age |
      ( pitch sweep: 45 + 255 * exp(-age*40) )
      age 40.0 f* 0.0 swap f- libm:exp 255.0 f* 45.0 f+
      age swap sine
      ( amp envelope: fast attack, slow decay )
      age 8.0 f* 0.0 swap f- libm:exp
      f* 1.5 f*
    ] [
      drop 0.0
    ] ifte
  ] do
;

( --- 808 Hi-hat: filtered noise, very fast decay --- )
: hh ( ev t -- sample )
  [ | ev t |
    t ev Event.start@ nip f-
    dup 0.0 f< not over 0.06 f< & [ | age |
      noise 0.5 f*
      age 100.0 f* 0.0 swap f- libm:exp
      f*
    ] [
      drop 0.0
    ] ifte
  ] do
;

( --- 808 Open hi-hat: noise, slower decay --- )
: oh ( ev t -- sample )
  [ | ev t |
    t ev Event.start@ nip f-
    dup 0.0 f< not over 0.3 f< & [ | age |
      noise 0.4 f*
      age 10.0 f* 0.0 swap f- libm:exp
      f*
    ] [
      drop 0.0
    ] ifte
  ] do
;

( --- 808 Snare: tuned body 185Hz + noise burst --- )
: sn ( ev t -- sample )
  [ | ev t |
    t ev Event.start@ nip f-
    dup 0.0 f< not over 0.2 f< & [ | age |
      ( body: 185Hz sine with fast decay )
      age 185.0 sine
      age 15.0 f* 0.0 swap f- libm:exp f*
      0.5 f*
      ( noise burst )
      noise 0.4 f*
      age 20.0 f* 0.0 swap f- libm:exp f*
      f+
    ] [
      drop 0.0
    ] ifte
  ] do
;

( --- Sine synth with attack ramp to avoid zero-crossing pop --- )
: syn ( ev t -- sample )
  [ | ev t |
    t ev Event.start@ nip f-
    dup 0.0 f< not over 0.4 f< & [ | age |
      ev Event.freq@ nip
      age swap sine
      ( attack: 1 - exp(-age*500) rises to 1.0 in ~5ms )
      age 500.0 f* 0.0 swap f- libm:exp 1.0 swap f-
      ( decay: exp(-4t) )
      age 4.0 f* 0.0 swap f- libm:exp
      f* f*
    ] [
      drop 0.0
    ] ifte
  ] do
;

( --- Saw lead: detuned saws + sub-octave --- )
: lead ( ev t -- sample )
  [ | ev t |
    t ev Event.start@ nip f-
    dup 0.0 f< not over ev Event.dur@ nip 0.9 f* f< & [ | age |
      ev Event.freq@ nip [ | freq |
        age freq saw
        age freq 1.003 f* saw f+
        0.5 f*
        age freq 8.0 f/ saw 0.3 f* f+
      ] do
      age 3.0 f* 0.0 swap f- libm:exp
      f*
    ] [
      drop 0.0
    ] ifte
  ] do
;

( --- Scene --- )
: scene
  [ [ \bd [ \hh \hh ] \sn [ \hh \hh ] ]
    [ \bd \~ \sn [ \hh \hh \oh ] ]
  ] alt 2 fast
  [ [[ 60 64 67 ]] [[ 62 65 69 ]] [[ 64 67 71 ]] [[ 65 69 72 ]] ] \syn s
  stack
  [ [ 72 74 76 77 79 76 74 72 ]
    [ 79 77 76 74 72 74 76 77 ]
  ] alt \lead s
  stack
;

\scene play-funky
