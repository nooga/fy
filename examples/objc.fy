( objc.fy — ObjC runtime bridge for FY )

( ---- Runtime ---- )
:: _objc "/usr/lib/libobjc.A.dylib" dl-open ;
:: _getClass   _objc "objc_getClass" dl-sym ;
:: _sel        _objc "sel_registerName" dl-sym ;
:: _msgSend    _objc "objc_msgSend" dl-sym ;
:: _allocClass _objc "objc_allocateClassPair" dl-sym ;
:: _regClass   _objc "objc_registerClassPair" dl-sym ;
:: _addMethod  _objc "class_addMethod" dl-sym ;

( ---- Low-level bindings ---- )
: cls      _getClass bind: s:i ;
: sel      _sel bind: s:i ;
: msg0     _msgSend bind: ii:i ;
: msg1     _msgSend bind: iii:i ;
: msg1d    _msgSend bind: iid:i ;
: msg2d    _msgSend bind: iidd:i ;
: msg1s    _msgSend bind: iis:i ;
: msg4d    _msgSend bind: iidddd:i ;
: msg4diii _msgSend bind: iiddddiii:i ;
: alloc-class _allocClass bind: isi:i ;
: reg-class   _regClass bind: i:v ;
: add-method  _addMethod bind: iiis:i ;

( ---- send: selector INSIDE quote ---- )
( The quote's first item is a selector string, rest compute args )
( When do'd: pushes selector string, then arg values              )

: send    ( obj ["sel"]          -- r )  do sel msg0 ;
: send:   ( obj ["sel:" arg]     -- r )  do swap sel swap msg1 ;
: sendd:  ( obj ["sel:" darg]    -- r )  do swap sel swap msg1d ;
: sends:  ( obj ["sel:" sarg]    -- r )  do swap sel swap msg1s ;

( ---- send: selector OUTSIDE quote (for multi-arg) ---- )
: send4d:    ( obj "sel" [d d d d]         -- r )  swap sel swap do msg4d ;
: send4diii: ( obj "sel" [d d d d i i i]   -- r )  swap sel swap do msg4diii ;

( ---- Convenience ---- )
: nsstr     ( str -- nsstr ) "NSString" cls swap "stringWithUTF8String:" sel swap msg1s ;
: ns-alloc  ( cls -- obj )  "alloc" sel msg0 ;
: ns-init   ( obj -- obj )  "init" sel msg0 ;
: ns-new    ( cls -- obj )  ns-alloc ns-init ;

( ---- Compile-time macros ---- )

( @class: resolve ObjC class at compile time )
( Usage: ["NSWindow"] @class )
macro: @class  peek-quote unpush do cls emit-lit ;

( @sel: register selector at compile time )
( Usage: ["setTitle:"] @sel )
macro: @sel  peek-quote unpush do sel emit-lit ;

( const: evaluate any quote at compile time )
macro: const  peek-quote unpush do emit-lit ;
