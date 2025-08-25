: dup3 dup over2 rot;
: tak [
  dup2 >= 
  [drop2]
  [
	  dup3 1- tak stash
	  dup3 -rot 1- tak stash
	  rot 1- tak grab grab 
  ]
  ifte 
  ] do
  ;

  1 2 3 tak . 