"/usr/lib/libSystem.B.dylib" dl-open
dup "puts" dl-sym     ( handle fptr )
swap drop              ( keep fptr )
"Freed string" cstr-new tuck
ccall1                 ( call puts(ptr) )
drop                   ( drop return value )
cstr-free .            ( free ptr; print 0 )

