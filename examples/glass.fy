( macOS Liquid Glass window — pure FY FFI through the ObjC runtime )

( ---- Load frameworks ---- )
:: _appkit "/System/Library/Frameworks/AppKit.framework/AppKit" dl-open ;

( ---- ObjC runtime ---- )
:: _objc "/usr/lib/libobjc.A.dylib" dl-open ;
:: _getClass _objc "objc_getClass" dl-sym ;
:: _sel _objc "sel_registerName" dl-sym ;
:: _msgSend _objc "objc_msgSend" dl-sym ;
:: _allocClassPair _objc "objc_allocateClassPair" dl-sym ;
:: _registerClassPair _objc "objc_registerClassPair" dl-sym ;
:: _addMethod _objc "class_addMethod" dl-sym ;

( ObjC helpers )
: cls     _getClass bind: s:i ;
: sel     _sel bind: s:i ;
: msg0    _msgSend bind: ii:i ;
: msg1    _msgSend bind: iii:i ;
: msg1d   _msgSend bind: iid:i ;
: msg2d   _msgSend bind: iidd:i ;
: msg1s   _msgSend bind: iis:i ;
: msg4d   _msgSend bind: iidddd:i ;
: initWin _msgSend bind: iiddddiii:i ;

: allocClass    _allocClassPair bind: isi:i ;
: registerClass _registerClassPair bind: i:v ;
: addMethod     _addMethod bind: iiis:i ;

( NSString from FY string )
: nsstr  "NSString" cls swap "stringWithUTF8String:" sel swap msg1s ;

( ---- App delegate — quits when last window closes ---- )
: shouldTerminate drop drop drop 1 ;
:: shouldTerminateCb callback: iii:i shouldTerminate ;

:: NSObjectClass "NSObject" cls ;
:: DelegateClass NSObjectClass "FYDelegate" 0 allocClass ;
DelegateClass "applicationShouldTerminateAfterLastWindowClosed:" sel
  shouldTerminateCb "c@:@" addMethod drop
DelegateClass registerClass

:: delegate "FYDelegate" cls "alloc" sel msg0 "init" sel msg0 ;

( ---- NSApplication ---- )
:: NSApp "NSApplication" cls "sharedApplication" sel msg0 ;
NSApp "setActivationPolicy:" sel 0 msg1 drop
NSApp "setDelegate:" sel delegate msg1 drop

( ---- Window ---- )
:: styleMask 15 ;  ( titled | closable | miniaturizable | resizable )
:: window
  "NSWindow" cls "alloc" sel msg0
  "initWithContentRect:styleMask:backing:defer:" sel
  200.0 200.0 800.0 500.0 styleMask 2 0
  initWin
;

window "setTitle:" sel "FY macOS" nsstr msg1 drop
window "setTitlebarAppearsTransparent:" sel 1 msg1 drop

( ---- Toolbar for wider glass area ---- )
:: toolbar
  "NSToolbar" cls "alloc" sel msg0
  "initWithIdentifier:" sel "fy.toolbar" nsstr msg1
;
window "setToolbar:" sel toolbar msg1 drop
window "setToolbarStyle:" sel 3 msg1 drop  ( unified )

( ---- Visual effect view — full glass content ---- )
:: vfx
  "NSVisualEffectView" cls "alloc" sel msg0
  "initWithFrame:" sel 0.0 0.0 800.0 500.0 msg4d
;
vfx "setBlendingMode:" sel 1 msg1 drop   ( behindWindow )
vfx "setState:" sel 1 msg1 drop          ( active )
window "setContentView:" sel vfx msg1 drop

( ---- Label ---- )
:: label "NSTextField" cls "labelWithString:" sel "Hello from FY!" nsstr msg1 ;
label "setFont:" sel
  "NSFont" cls "boldSystemFontOfSize:" sel 42.0 msg1d
  msg1 drop
label "setTextColor:" sel
  "NSColor" cls "secondaryLabelColor" sel msg0
  msg1 drop
label "setAlignment:" sel 1 msg1 drop  ( center )
label "setFrame:" sel 0.0 180.0 800.0 80.0 msg4d drop

( ---- Subtitle ---- )
:: subtitle "NSTextField" cls "labelWithString:" sel "Pure FFI through the ObjC runtime" nsstr msg1 ;
subtitle "setFont:" sel
  "NSFont" cls "systemFontOfSize:" sel 18.0 msg1d
  msg1 drop
subtitle "setTextColor:" sel
  "NSColor" cls "tertiaryLabelColor" sel msg0
  msg1 drop
subtitle "setAlignment:" sel 1 msg1 drop
subtitle "setFrame:" sel 0.0 140.0 800.0 40.0 msg4d drop

( ---- Add labels to glass view ---- )
vfx "addSubview:" sel label msg1 drop
vfx "addSubview:" sel subtitle msg1 drop

( ---- Show & run ---- )
window "center" sel msg0 drop
window "makeKeyAndOrderFront:" sel 0 msg1 drop
NSApp "activateIgnoringOtherApps:" sel 1 msg1 drop
NSApp "run" sel msg0 drop
