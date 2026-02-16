"/usr/lib/libSystem.B.dylib" dl-open
dup "puts" dl-sym swap drop        ( fptr )
"Hello via with-cstr-f" swap       ( string fptr )
[ ccall1 ]                          ( string fptr quote )
with-cstr-f                         ( -> return code )
drop                                ( drop return code )

