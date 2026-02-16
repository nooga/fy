"./build/libfytest.dylib" dl-open
dup "my_strlen" dl-sym   ( handle fptr )
swap drop                 ( keep fptr )
"abcdef" cstr-new
ccall1 .                  ( expect 6 )

