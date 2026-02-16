( Fibonacci using self-recursion inside a quote-aware loop )
( Push n and call `fibonacci` to print the nth Fibonacci number )

: fibonacci
  dup 1 <= [ drop 1 ]
  [ dup 2 = [ drop 1 ]
    [ dup 1 - fibonacci
      swap 2 - fibonacci +
    ] ifte
  ] ifte
;

10 fibonacci .