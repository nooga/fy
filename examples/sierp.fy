:N 16;
N [  dup [' .c] dotimes
N [
    dup
    over2 drop 1 -
    swap N !-
    &
    \'  \'* ifte .c
    '  .c
] dotimes .nl ] dotimes
