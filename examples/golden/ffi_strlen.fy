"/usr/lib/libSystem.B.dylib" dl-open
dup "strlen" dl-sym     ( handle fptr )
swap drop               ( keep fptr )
"hello, world" cstr-new ( push C string ptr )
ccall1 .                ( call strlen(ptr) and print length )

