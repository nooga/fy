3 [3 [dup over2 drop .dbg drop drop] dotimes] dotimes

\ simple loop printing countdown using repeat and nested quotes
: x 5 [ dup . 1 - dup 0 > ] repeat drop;
\ prints: 5 4 3 2 1

\ mutual recursion: even/odd
: even dup 0 = [ drop 1 ] [ odd ] ifte ;
: odd  dup 0 = [ drop 0 ] [ 1- even ] ifte ;
\ usage:
10 even .  \ -> 1
11 even .  \ -> 0
