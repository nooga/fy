"./build/libfytest.dylib" dl-open
dup "my_strlen" dl-sym   ( handle fptr )
swap drop                 ( keep fptr )
"free me" cstr-new tuck
ccall1 .                  ( print length )
swap cstr-free .          ( print 0 after free )

