include "funky.fy"

: bd ( ev t -- sample ) drop drop 0.0 ;
: hh ( ev t -- sample ) drop drop 0.0 ;
: sn ( ev t -- sample ) drop drop 0.0 ;
: syn ( ev t -- sample ) drop drop 0.0 ;
: lead ( ev t -- sample ) drop drop 0.0 ;

"=== transpose: plain list ===" . .nl
: scene-t1 [ 60 64 67 ] 7 transpose \syn s ;
\scene-t1 debug-funky

"=== transpose: with alt ===" . .nl
: scene-t2 [ [ 60 64 67 ] [ 72 76 79 ] ] alt \syn s -2 transpose ;
\scene-t2 debug-funky

"=== oct: +1 octave ===" . .nl
: scene-t3 [ 60 64 67 ] 1 oct \syn s ;
\scene-t3 debug-funky

"=== swing 67 on drums ===" . .nl
: scene-sw [ \bd \hh \sn \hh ] 67 swing ;
\scene-sw debug-funky

"=== swing 50 (straight) ===" . .nl
: scene-sw2 [ \bd \hh \sn \hh ] 50 swing ;
\scene-sw2 debug-funky
