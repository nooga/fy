:N 16;
N [ dup                         (y) 
    [' .c] dotimes              (print padding)
    N [ dup                     (x)
        over2 drop 1-           (y' = y - 1)
        swap N !-               (x' = N - x)
        &                       (x' & y')
        \'  \'* ifte .c ' .c ]  (print * or space)
    dotimes .nl]       
dotimes
