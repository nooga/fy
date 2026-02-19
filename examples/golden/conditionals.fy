( then: run body if truthy )
5 1 [1+] then .
5 0 [1+] then .

( unless: run body if falsy )
5 0 [1+] unless .
5 1 [1+] unless .

( then with side effect )
1 [ "yes" swrite ] then "\n" swrite
0 [ "yes" swrite ] then "no" swrite "\n" swrite

( cond: value matching )
3 [ [1 =] [10] [2 =] [20] [3 =] [30] [0] ] cond .
1 [ [1 =] [10] [2 =] [20] [3 =] [30] [0] ] cond .

( cond: default case )
99 [ [1 =] [10] [999] ] cond .

( cond: string matching with sstarts )
: heading-level
  [ ["######" sstarts] [6]
    ["#####" sstarts]  [5]
    ["####" sstarts]   [4]
    ["###" sstarts]    [3]
    ["##" sstarts]     [2]
    ["#" sstarts]      [1]
    [0]
  ] cond
;

"# Hello" heading-level .
"## Sub" heading-level .
"###### Deep" heading-level .
"No heading" heading-level .

( cond: no pairs, just default )
42 [ [99] ] cond .

( cond with no default, all pairs )
2 [ [1 =] [10] [2 =] [20] ] cond .
