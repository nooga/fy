include "funky.fy"

( --- Cathode Girls SEM sound --- )
: lead ( ev t -- sample )
  [ | ev t |
    ev t note-age
    dup 0.0 f< not over ev Event.dur@ nip 0.9 f* f< & [ | age |
      ev Event.freq@ nip
      t 2.0 sine 0.008 f* 1.0 f+ f*  ( ~2Hz pitch drift )
      [ | freq |
        ( two detuned saws )
        age freq saw
        age freq 1.003 f* saw f+
        0.5 f*
        ( ms20 filter: 244Hz base, AD envelope sweep, 62% reso )
        age 80.0 2.0 ad
        16000.0 f* 244.0 f+
        0.62 ev 0 ms20
        ( amplitude )
        age 3.0 exp-decay f*
        0.8 f*
      ] do
    ] [ drop 0.0 ] ifte
  ] do
;

100 bpm

: scene 
    [ ( stabs )
        [[ 64 62 55 50]] [[ 64 62 55 50]] [[ 64 62 55 50]] [[ 64 62 55 50]]
        \~
        \~
        [[ 64 62 55 50]] [[ 64 62 55 50]]
        [[ 67 65 57 53]] [[ 67 65 57 53]]
        81 ( \~ )
        \~
        \~
        [[ 67 65 57 53]] [[ 67 65 57 53]]
        \~
        [[ 62 60 55 48]]
        \~
        [[ 62 60 55 48]]
        \~
        [ [[ 62 60 55 48]] [[62 60 55 48]] \~ ]
        [ [[ 62 60 55 48]] [[62 60 55 48]] \~ ]
        [[ 62 60 55 48]]
    ] 2 slow \lead s 

    [ ( lead )
         \~ [ 74 77 \~ \~ 74 \~ 69 72 67 \~ \~ \~] 
         \~ [ 74 77 \~ \~ 74 \~ 69 72 67 67 \~ \~] 
    ] 4 slow \lead s
    stack 
;

\scene play-funky