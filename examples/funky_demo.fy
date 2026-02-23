include "funky.fy"

( 808 bass drum )
: bd ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over 0.5 f< & [ | age |
      age 40.0 exp-decay 255.0 f* 45.0 f+
      age swap sine
      age 8.0 exp-decay
      f* 1.5 f*
    ] [ drop 0.0 ] ifte
  ] do
;

( 808 hi-hat )
: hh ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over 0.06 f< & [ | age |
      noise 0.5 f*
      age 100.0 exp-decay f*
    ] [ drop 0.0 ] ifte
  ] do
;

( 808 open hi-hat )
: oh ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over 0.3 f< & [ | age |
      noise 0.4 f*
      age 10.0 exp-decay f*
    ] [ drop 0.0 ] ifte
  ] do
;

( 808 snare )
: sn ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over 0.2 f< & [ | age |
      age 185.0 sine age 15.0 exp-decay f* 0.5 f*
      noise 0.4 f* age 20.0 exp-decay f* f+
    ] [ drop 0.0 ] ifte
  ] do
;

( 808 clap )
: clap ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over 0.3 f< & [ | age |
      ( 4 discrete bursts, rate 500 = true silence between them )
      noise age 500.0 exp-decay f*
      noise age 0.02 f- fabs 500.0 exp-decay f* f+
      noise age 0.04 f- fabs 500.0 exp-decay f* f+
      noise age 0.06 f- fabs 500.0 exp-decay f* f+
      ( reverb tail — the 808 clap's sustain )
      noise age 8.0 exp-decay f* 0.4 f* f+
      ( bandpass: midrange body, not hihat-bright )
      2000.0 ev 0 lp1
      500.0 ev 1 hp1
      2.0 f*
    ] [ drop 0.0 ] ifte
  ] do
;

( Moog funk bass )
: bass ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over 0.4 f< & [ | age |
      ev Event.freq@ nip
      t swap saw
      age 12.0 exp-decay 4000.0 f* 200.0 f+
      0.7 ev 0 moog
      age 6.0 exp-decay
      f* 2.0 f*
    ] [ drop 0.0 ] ifte
  ] do
;

( Lush pad: detuned saws -> moog filter, slow attack --- )
: pad ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over ev Event.dur@ nip 0.95 f* f< & [ | age |
      ev Event.freq@ nip [ | freq |
        t freq saw
        t freq 1.005 f* saw f+
        t freq 0.995 f* saw f+
        0.33 f*
      ] do
      1200.0 0.15 ev 0 moog
      age 8.0 exp-attack
      age 1.5 exp-decay
      f* f* 0.6 f*
    ] [ drop 0.0 ] ifte
  ] do
;

( --- Saw lead: detuned saws + sub-octave --- )
: lead ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over ev Event.dur@ nip 0.9 f* f< & [ | age |
      ev Event.freq@ nip [ | freq |
        age freq saw
        age freq 1.003 f* saw f+
        0.5 f*
        age freq 8.0 f/ saw 0.3 f* f+
      ] do
      age 3.0 exp-decay f* 0.1 f*
    ] [ drop 0.0 ] ifte
  ] do
;

120 bpm

: scene
  ( drums )
  [  \bd [\hh \hh] [[\sn \clap]] [\hh [[\bd \hh]]] 
     [[\bd \hh]] [\hh \clap] [[\sn \clap]] [\hh  \oh] 
  ] 

  ( bass )
  [ 36 \~ [36 48] \~ 39 \~ 43 [46 \~]
    36 \~ [36 48] 36 39 41 43 [48 36]
  ] 2 slow \bass s
  stack

  ( pad )
  [ [[ 63 67 70 74 ]]
    [[ 68 72 75 79 ]]
  ] 2 slow \pad s
  stack

  ( arp )
  [ [ 63 67 70 74 ] [ 68 72 75 79 ] ] 2 fast \lead s
  stack
;

\scene play-funky
