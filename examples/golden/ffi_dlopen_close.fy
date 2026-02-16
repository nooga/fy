"/usr/lib/libSystem.B.dylib" dl-open
dup "getpid" dl-sym     ( handle fptr )
swap dl-close           ( close handle )
drop                    ( keep fptr )
ccall0 .

