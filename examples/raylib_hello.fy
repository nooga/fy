( Raylib hello world )
import "raylib"

( Color packing: r g b a -- color )
( Color is 4 bytes: RGBA packed little-endian into a 32-bit int )
( On little-endian ARM64: byte 0 = R, byte 1 = G, byte 2 = B, byte 3 = A )
: rgba
  24 << swap        ( a<<24, b )
  16 << or swap     ( a<<24|b<<16, g )
  8 << or swap      ( a<<24|b<<16|g<<8, r )
  or
;

constant RAYWHITE  245 245 245 255 rgba ;
constant DARKGRAY  80 80 80 255 rgba ;
constant RED       230 41 55 255 rgba ;
constant BLUE      0 121 241 255 rgba ;
constant GREEN     0 228 48 255 rgba ;
constant YELLOW    253 249 0 255 rgba ;

800 450 "Hello from fy!" cstr-new raylib:InitWindow
60 raylib:SetTargetFPS

: frame
  raylib:BeginDrawing
    RAYWHITE raylib:ClearBackground
    "Hello from fy!" cstr-new 280 180 30 DARKGRAY raylib:DrawText
    400 280 50.0 RED raylib:DrawCircle
    100 100 600 350 BLUE raylib:DrawRectangleLines
  raylib:EndDrawing
;

: loop
  raylib:WindowShouldClose 0 =
  [ frame loop ] [ ] ifte
;

loop
raylib:CloseWindow
