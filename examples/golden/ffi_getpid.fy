"/usr/lib/libSystem.B.dylib" dl-open
dup "getpid" dl-sym     ( stack: handle fptr )
swap drop               ( drop handle, keep fptr )
ccall0 .                ( print PID )

