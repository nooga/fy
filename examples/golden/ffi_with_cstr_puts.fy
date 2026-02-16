"/usr/lib/libSystem.B.dylib" dl-open
dup "puts" dl-sym     ( handle fptr )
swap drop              ( keep fptr )
"Hello with-cstr" swap with-cstr drop

