( Basic capture: inner quote sees outer local )
: test1 [ | n | n 0 > [ n . ] [] ifte ] do ; 5 test1

( Two captured locals )
: test2 [ | a b | [ a b + ] do ] do ; 3 4 test2 .

( Capture in map callback )
: addto [ | n | [1 2 3] [ n + ] map ] do ; 10 addto [ . ] each

( Recursive with captured local )
: countdown [ | n | n 0 > [ n . n 1 - countdown ] [] ifte ] do ; 5 countdown

( Nested locals: inner quote has own locals + captures outer )
: test3 [ | x | [ | y | x y + ] do ] do ; 10 3 test3 .

( Capture used as accumulator seed in reduce )
: sum-offset [ | n | 0 [1 2 3] [ + n + ] reduce ] do ; 10 sum-offset .

( Multiple captures in ifte branches )
: clamp [ | lo hi val | val lo < [ lo ] [ val hi > [ hi ] [ val ] ifte ] ifte ] do ;
0 10 -5 clamp .
0 10 15 clamp .
0 10 7 clamp .

