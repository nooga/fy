( Raylib hello world )
import "raylib"

( Color packing: r g b a -- color )
: rgba
  24 << swap        ( a<<24, b )
  16 << or swap     ( a<<24|b<<16, g )
  8 << or swap      ( a<<24|b<<16|g<<8, r )
  or
;

:: RAYWHITE  245 245 245 255 rgba ;
:: DARKGRAY  80 80 80 255 rgba ;
:: RED       230 41 55 255 rgba ;
:: BLUE      0 121 241 255 rgba ;
:: GREEN     0 228 48 255 rgba ;
:: YELLOW    253 249 0 255 rgba ;

800 600 "Hello from fy!" raylib:InitWindow
60 raylib:SetTargetFPS

: frame
  raylib:BeginDrawing
    RAYWHITE raylib:ClearBackground
    "Hello from fy!" 280 180 30 DARKGRAY raylib:DrawText
    400 280 50.0 GREEN raylib:DrawCircle
    100 100 600 350 BLUE raylib:DrawRectangleLines
  raylib:EndDrawing
;

: loop
  raylib:WindowShouldClose 0 =
  [ frame loop ] [ ] ifte
;

loop
raylib:CloseWindow
