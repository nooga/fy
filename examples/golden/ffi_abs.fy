"/usr/lib/libSystem.B.dylib" dl-open
dup "abs" dl-sym      ( stack: handle fptr )
swap drop             ( drop handle, keep fptr )
-42 ccall1 .          ( print abs(-42) )

