( Rotating 3D cube demo )
import "libm"
import "raylib"

( Color packing: r g b a -- color )
: rgba  24 << swap 16 << or swap 8 << or swap or ;

:: RAYWHITE  245 245 245 255 rgba ;
:: DARKGRAY  80 80 80 255 rgba ;
:: RED       230 41 55 255 rgba ;
:: DARKBLUE  0 82 172 255 rgba ;
:: GOLD      255 203 0 255 rgba ;
:: LIGHTGRAY 200 200 200 255 rgba ;

struct: Camera3D
  f32 position-x  f32 position-y  f32 position-z
  f32 target-x    f32 target-y    f32 target-z
  f32 up-x        f32 up-y        f32 up-z
  f32 fovy        i32 projection
;

( Update camera orbit position based on time )
: update-camera ( cam -- cam )
  raylib:GetTime                ( cam t )
  dup libm:sin 8.0 f*          ( cam t cx )
  over libm:cos 8.0 f*         ( cam t cx cz )
  ( store position.x and position.z )
  >r >r                        ( cam t  R: cz cx )
  drop                          ( cam    R: cz cx )
  dup 0 + r> f!32              ( cam    R: cz ) ( pos.x = sin(t)*8 )
  dup 8 + r> f!32              ( cam )           ( pos.z = cos(t)*8 )
;

800 450 "fy - Rotating Cube" raylib:InitWindow
60 raylib:SetTargetFPS

:: cam
  6.0 4.0 6.0 (position)
  0.0 0.0 0.0 (target)
  0.0 1.0 0.0 (up)
  45.0 0      (fovy, projection)
  Camera3D.new
;

: frame
  cam update-camera drop

  raylib:BeginDrawing
    RAYWHITE raylib:ClearBackground

    cam raylib:BeginMode3D
      ( Draw solid cube )
      0.0 0.0 0.0  
      2.0 2.0 2.0  
      RED 
      raylib:DrawCube
      ( Draw wireframe )
      0.0 0.0 0.0  
      2.0 2.0 2.0  
      DARKGRAY 
      raylib:DrawCubeWires
      ( Draw ground grid )
      10 1.0 raylib:DrawGrid
    raylib:EndMode3D

    "fy - Rotating Cube" 10 10 20 DARKGRAY raylib:DrawText
    10 40 raylib:DrawFPS
  raylib:EndDrawing
;

: running?  raylib:WindowShouldClose 0 = ;
running? [ drop frame running? ] repeat
raylib:CloseWindow
