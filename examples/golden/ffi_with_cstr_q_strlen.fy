"./build/libfytest.dylib" dl-open
dup "my_strlen" dl-sym swap drop
"abcdefg"
[ ccall1 ]
with-cstr-q .             ( expect 7 )

