:N 16;
N [
dup N !- 2 / [' .c ' .c] dotimes
N [
    dup
    over2 drop N !-
    swap N !-
    &
    \'  \'* ifte .c
    '  .c
] dotimes .nl ] dotimes
