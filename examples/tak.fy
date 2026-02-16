( Tak (function) example per https://en.wikipedia.org/wiki/Tak_(function) )
( Definition: tak(x,y,z) = (y < x) ? tak(tak(x-1,y,z), tak(y-1,z,x), tak(z-1,x,y)) : z )

: dup3 dup over2 rot;     ( a b c -- a b c a b c )
: stash >r;               ( x -- (to retain) )
: grab  r>;               ( -- x (from retain) )

: tak
  ( preserve x y for branch; move z to retain and compute y < x )
  >r dup2 swap <
  [ ( then-branch (y < x) )
    ( a = tak(x-1, y, z) )
    dup2 r@ rot 1- -rot tak stash
    ( b = tak(y-1, z, x) )
    r@ swap rot 1- -rot swap rot tak stash
    ( c = tak(z-1, x, y) )
    r@ 1- -rot tak
    ( call tak(a, b, c) )
    grab grab rot swap -rot tak
  ]
  [ ( else-branch (y >= x): return z )
    r> swap drop swap drop
  ]
  ifte
;

1 2 3 tak .  ( => 3 )