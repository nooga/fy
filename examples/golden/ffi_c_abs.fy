"./build/libfytest.dylib" dl-open
dup "my_abs" dl-sym      ( handle fptr )
swap drop                 ( keep fptr )
-123 ccall1 .             ( expect 123 )

