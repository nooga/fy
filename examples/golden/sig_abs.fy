( Test sig: compile-time typed call )
( Convention: fptr is TOS, args are below )

"/usr/lib/libSystem.B.dylib" dl-open

( abs(-42) via sig: i:i - inline )
dup "abs" dl-sym
-42 swap sig: i:i .

( pow(2.0, 10.0) via sig: dd:d - inline )
dup "pow" dl-sym
2.0 10.0 rot sig: dd:d f.

( sqrtf(16.0) via sig: f:f - inline )
dup "sqrtf" dl-sym
16.0 swap sig: f:f f.

( sin/cos via word definitions )
: libsys "/usr/lib/libSystem.B.dylib" dl-open ;
: my-sin  libsys "sin" dl-sym sig: d:d ;
: my-cos  libsys "cos" dl-sym sig: d:d ;

0.0 my-sin f.
1.5707963267948966 my-sin f.
0.0 my-cos f.
3.141592653589793 my-cos f.

drop
