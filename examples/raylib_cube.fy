( Rotating 3D cube demo )
import "libm"
import "raylib"

( malloc from libSystem )
:: _libsys "/usr/lib/libSystem.B.dylib" dl-open ;
:: _malloc _libsys "malloc" dl-sym ;
: malloc _malloc sig: i:i ;

( Color packing: r g b a -- color )
: rgba  24 << swap 16 << or swap 8 << or swap or ;

:: RAYWHITE  245 245 245 255 rgba ;
:: DARKGRAY  80 80 80 255 rgba ;
:: RED       230 41 55 255 rgba ;
:: DARKBLUE  0 82 172 255 rgba ;
:: GOLD      255 203 0 255 rgba ;
:: LIGHTGRAY 200 200 200 255 rgba ;

( Camera3D struct: 44 bytes )
( 0:  position.x  f32 )
( 4:  position.y  f32 )
( 8:  position.z  f32 )
( 12: target.x    f32 )
( 16: target.y    f32 )
( 20: target.z    f32 )
( 24: up.x        f32 )
( 28: up.y        f32 )
( 32: up.z        f32 )
( 36: fovy         f32 )
( 40: projection   i32 )

: make-camera ( -- cam )
  44 malloc
  dup 0 +  6.0 f!32
  dup 4 +  4.0 f!32
  dup 8 +  6.0 f!32
  dup 12 + 0.0 f!32
  dup 16 + 0.0 f!32
  dup 20 + 0.0 f!32
  dup 24 + 0.0 f!32
  dup 28 + 1.0 f!32
  dup 32 + 0.0 f!32
  dup 36 + 45.0 f!32
  dup 40 + 0 !32
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

800 450 "fy - Rotating Cube" cstr-new raylib:InitWindow
60 raylib:SetTargetFPS

:: cam make-camera ;

: frame
  cam update-camera drop

  raylib:BeginDrawing
    RAYWHITE raylib:ClearBackground

    cam raylib:BeginMode3D
      ( Draw solid cube )
      0.0 0.0 0.0  2.0 2.0 2.0  RED raylib:DrawCube
      ( Draw wireframe )
      0.0 0.0 0.0  2.0 2.0 2.0  DARKGRAY raylib:DrawCubeWires
      ( Draw ground grid )
      10 1.0 raylib:DrawGrid
    raylib:EndMode3D

    "fy - Rotating Cube" cstr-new 10 10 20 DARKGRAY raylib:DrawText
  raylib:EndDrawing
;

: loop  raylib:WindowShouldClose 0 = [ frame loop ] [ ] ifte ;
loop
raylib:CloseWindow
