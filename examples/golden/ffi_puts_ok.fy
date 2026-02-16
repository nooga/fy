"/usr/lib/libSystem.B.dylib" dl-open
dup "puts" dl-sym     ( handle fptr )
swap drop              ( keep fptr )
"Hello from puts" cstr-new
ccall1 drop            ( call puts(ptr); drop return value )

