( macOS Liquid Glass window — using objc.fy module )

include "objc.fy"
:: _appkit "/System/Library/Frameworks/AppKit.framework/AppKit" dl-open ;

( ---- App delegate — quits when last window closes ---- )
: shouldTerminate drop drop drop 1 ;
:: shouldTerminateCb callback: iii:i shouldTerminate ;

:: DelegateClass ["NSObject"] @class "FYDelegate" 0 alloc-class ;
DelegateClass "applicationShouldTerminateAfterLastWindowClosed:" sel
  shouldTerminateCb "c@:@" add-method drop
DelegateClass reg-class
:: delegate "FYDelegate" cls ns-new ;

( ---- NSApplication ---- )
:: NSApp ["NSApplication"] @class ["sharedApplication"] send ;
NSApp ["setActivationPolicy:" 0] send: drop
NSApp ["setDelegate:" delegate] send: drop

( ---- Window ---- )
:: window
  ["NSWindow"] @class ns-alloc
  "initWithContentRect:styleMask:backing:defer:"
  [200.0 200.0 800.0 500.0 15 2 0] send4diii:
;

window ["setTitle:" "FY Liquid Glass" nsstr] send: drop
window ["setTitlebarAppearsTransparent:" 1] send: drop

( ---- Toolbar for wider glass area ---- )
:: toolbar
  ["NSToolbar"] @class ns-alloc
  ["initWithIdentifier:" "fy.toolbar" nsstr] send:
;
window ["setToolbar:" toolbar] send: drop
window ["setToolbarStyle:" 3] send: drop

( ---- Visual effect view — full glass content ---- )
:: vfx
  ["NSVisualEffectView"] @class ns-alloc
  "initWithFrame:" [0.0 0.0 800.0 500.0] send4d:
;
vfx ["setBlendingMode:" 1] send: drop
vfx ["setState:" 1] send: drop
window ["setContentView:" vfx] send: drop

( ---- Label ---- )
:: label ["NSTextField"] @class ["labelWithString:" "Hello from FY!" nsstr] send: ;
label ["setFont:" ["NSFont"] @class ["boldSystemFontOfSize:" 42.0] sendd:] send: drop
label ["setTextColor:" ["NSColor"] @class ["secondaryLabelColor"] send] send: drop
label ["setAlignment:" 1] send: drop
label "setFrame:" [0.0 180.0 800.0 80.0] send4d: drop

( ---- Subtitle ---- )
:: subtitle ["NSTextField"] @class ["labelWithString:" "Pure FFI through the ObjC runtime" nsstr] send: ;
subtitle ["setFont:" ["NSFont"] @class ["systemFontOfSize:" 18.0] sendd:] send: drop
subtitle ["setTextColor:" ["NSColor"] @class ["tertiaryLabelColor"] send] send: drop
subtitle ["setAlignment:" 1] send: drop
subtitle "setFrame:" [0.0 140.0 800.0 40.0] send4d: drop

( ---- Add labels to glass view ---- )
vfx ["addSubview:" label] send: drop
vfx ["addSubview:" subtitle] send: drop

( ---- Show & run ---- )
window ["center"] send drop
window ["makeKeyAndOrderFront:" 0] send: drop
NSApp ["activateIgnoringOtherApps:" 1] send: drop
NSApp ["run"] send drop
