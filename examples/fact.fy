: factorial
  1 swap          ( Initialize result to 1, bring N to the top )
  [ over * swap   ( Multiply result by N, swap result to the top )
    1 - dup 1 >   ( Decrement N, check if N > 1 )
  ] repeat
  drop            ( Clean up the stack )
;

5 factorial .