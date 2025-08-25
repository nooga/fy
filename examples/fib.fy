: fibonacci
  0 1 swap        ( Initialize F0 and F1 )
  [ over over +   ( Calculate next Fibonacci number )
    swap 1 - dup 2 >
  ] repeat
  drop nip        ( Clean up the stack )
;

10 fibonacci .