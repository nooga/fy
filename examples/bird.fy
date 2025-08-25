:N 256;
:rem dup2 / * -;
:idx2 over2 nip over;
( ppm header )
'P .c '1 .c .nl
N . N .
( pixels )
N [
    N [ idx2
        N !- swap N !-
        dup2 + swap rot swap - &
        24 rem 9 >
        \'0 \'1 ifte .c ] dotimes
  ] dotimes
