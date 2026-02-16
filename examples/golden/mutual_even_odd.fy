: even dup 0 = [ drop 1 ] [ 1- odd ] ifte ;
: odd  dup 0 = [ drop 0 ] [ 1- even ] ifte ;
0 even .
1 even .
2 even .
3 even .
