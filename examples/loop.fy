: count-up
  1 dup
  [ drop .dbg dup . 1 + .dbg over over .dbg > .dbg ] repeat
  drop drop
;

5 count-up