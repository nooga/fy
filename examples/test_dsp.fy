include "funky.fy"

: bd ( ev t -- sample ) drop drop 0.0 ;
: hh ( ev t -- sample ) drop drop 0.0 ;
: sn ( ev t -- sample ) drop drop 0.0 ;
: clap ( ev t -- sample ) drop drop 0.0 ;
: oh ( ev t -- sample ) drop drop 0.0 ;
: bass ( ev t -- sample ) drop drop 0.0 ;
: pad ( ev t -- sample ) drop drop 0.0 ;

120 bpm

"=== electro drums ===" . .nl
: scene-d
  [ [ \bd [\hh \hh] [[\sn \clap]] [\hh [[\bd \hh]]] ]
    [ [[\bd \hh]] [\hh \clap] [[\sn \clap]] [\hh \hh \oh] ]
  ] alt 2 fast
;
\scene-d debug-funky

"=== zapp bass (cycle 0) ===" . .nl
: scene-b
  [ 36 \~ [36 48] \~ 39 \~ 43 [46 \~]
    36 \~ [36 48] 36 39 41 43 [48 36]
  ] 2 slow \bass s
;
\scene-b debug-funky

"=== pad ===" . .nl
: scene-p
  [ [[ 63 67 70 74 ]]
    [[ 68 72 75 79 ]]
  ] 2 slow \pad s
;
\scene-p debug-funky
