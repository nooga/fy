"/usr/lib/libSystem.B.dylib" dl-open
dup "puts" dl-sym swap drop   ( leave fptr )
"Hello via quote"
[ ccall1 ]
with-cstr-q

