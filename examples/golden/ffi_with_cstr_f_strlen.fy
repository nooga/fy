"./build/libfytest.dylib" dl-open
dup "my_strlen" dl-sym swap drop    ( fptr )
"abcdefg" swap                      ( string fptr )
[ ccall1 ]                           ( string fptr quote )
with-cstr-f .                        ( expect 7 )

