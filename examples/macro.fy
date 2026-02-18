( FY Macro System Demo )

( ---- const: compile-time evaluation ---- )
macro: const peek-quote unpush do emit-lit ;

( Computed at compile time — zero runtime cost )
[6 7 *] const .              ( => 42 )
[1000 24 * 60 *] const .     ( => 1440000 )

( ---- emit-word: custom syntax ---- )
macro: emit-add "+" emit-word ;
macro: emit-mul "*" emit-word ;

3 4 emit-add .               ( => 7 )
5 6 emit-mul .               ( => 30 )

( ---- Quote introspection ---- )
( type tags: 0=int 1=float 2=word 3=string 4=quote )
:: q [42 3.14 "hello" foo [1 2]] ;

q qlen .                     ( => 5 )
q 0 qnth-type .             ( => 0 — int )
q 1 qnth-type .             ( => 1 — float )
q 2 qnth-type .             ( => 3 — string )
q 3 qnth-type .             ( => 2 — word )
q 4 qnth-type .             ( => 4 — quote )

( ---- Word introspection ---- )
[hello-world] qhead word? .         ( => 1 )
[hello-world] qhead word->str .     ( => hello-world )

( ---- Compile-time fib ---- )
: fib dup 1 <= [drop 1] [dup 1- fib swap 2 - fib +] ifte ;
[10 fib] const .             ( => 89 )
