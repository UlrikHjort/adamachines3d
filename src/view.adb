--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Environment_Variables;
with Ada.Text_IO;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Interfaces.C;
with System;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Surface;
with Glib; use Glib;
with Gtkada.Types;
with Art;
with Interfaces;
with Overlay;
with Models;
with Palette;
with Scenery;
with Cars;
with GL; use GL;
with Lin; use Lin;
with Mesh; use Mesh;
with Race; use Race;
with Tracks; use Tracks;

package body View is

   use type Geom.Vec;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type System.Address;

   function G (X : Float) return Gdouble is (Gdouble (X));
   function F (X : Float) return GLfloat is (GLfloat (X));

   ---------------------------------------------------------------------------
   --  The shaders
   ---------------------------------------------------------------------------

   LF : constant Character := ASCII.LF;

   Vertex_Source : constant String :=
     "#version 330 core" & LF &
     "layout(location=0) in vec3 aPos;" & LF &
     "layout(location=1) in vec3 aNorm;" & LF &
     "layout(location=2) in vec4 aCol;" & LF &
     "layout(location=3) in vec2 aUV;" & LF &
     "layout(location=4) in float aTW;" & LF &
     "uniform mat4 uVP;" & LF &
     "out vec3 vPos; out vec3 vNorm; out vec4 vCol; out vec2 vUV; out float vTW;" & LF &
     "void main() {" & LF &
     "  vPos = aPos; vNorm = aNorm; vCol = aCol; vUV = aUV; vTW = aTW;" & LF &
     "  gl_Position = uVP * vec4(aPos, 1.0);" & LF &
     "}" & LF;

   Fragment_Source : constant String :=
     "#version 330 core" & LF &
     "in vec3 vPos; in vec3 vNorm; in vec4 vCol; in vec2 vUV; in float vTW;" & LF &
     "uniform sampler2D uTex;" & LF &
     "uniform sampler2DShadow uShadow;" & LF &
     "uniform mat4 uLightVP;" & LF &
     "uniform int uShadowOn;" & LF &
     "uniform vec3 uShadowCenter;" & LF &
     "uniform float uShadowRadius;" & LF &
     "uniform vec3 uSun, uSunCol, uAmb, uFog, uEye;" & LF &
     "uniform float uFogNear, uFogFar;" & LF &
     "uniform int uLights;" & LF &
     "uniform vec3 uLP[8]; uniform vec3 uLD[8];" & LF &
     "out vec4 frag;" & LF &
     --  how much of the sun reaches this point: soft at the edges, gone where the map ends
     "float sunlit(vec3 n) {" & LF &
     "  if (uShadowOn == 0) return 1.0;" & LF &
     "  vec4 lp = uLightVP * vec4(vPos, 1.0);" & LF &
     "  vec3 p = lp.xyz / lp.w * 0.5 + 0.5;" & LF &
     "  if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) return 1.0;" & LF &
     "  float bias = 0.0004 + 0.0012 * (1.0 - max(dot(n, uSun), 0.0));" & LF &
     "  vec2 ts = 1.0 / vec2(textureSize(uShadow, 0));" & LF &
     "  float s = 0.0;" & LF &
     "  for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++)" & LF &
     "    s += texture(uShadow, vec3(p.xy + vec2(x, y) * ts * 1.5, p.z - bias));" & LF &
     "  s /= 9.0;" & LF &
     "  float edge = smoothstep(0.75, 1.0, length(vPos.xz - uShadowCenter.xz) / uShadowRadius);" & LF &
     "  return mix(s, 1.0, edge);" & LF &
     "}" & LF &
     "void main() {" & LF &
     "  if (vTW < -0.5) { frag = vCol; return; }" & LF &   --  the sky: not lit, not in the fog
     "  vec4 base = vCol;" & LF &
     "  if (vTW > 0.0) base = mix(base, texture(uTex, vUV) * base, vTW);" & LF &
     "  vec3 c = base.rgb;" & LF &
     "  if (dot(vNorm, vNorm) > 0.01) {" & LF &
     "    vec3 n = normalize(vNorm);" & LF &
     "    if (dot(n, uEye - vPos) < 0.0) n = -n;" & LF &   --  lit alike from either side
     "    float d = max(dot(n, uSun), 0.0);" & LF &
     "    if (uShadowOn == 2) { vec4 lp = uLightVP * vec4(vPos, 1.0); vec3 p = lp.xyz / lp.w * 0.5 + 0.5;" &
     "      frag = vec4(sunlit(n), fract(p.z * 20.0), p.x, 1.0); return; }" & LF &
     "    vec3 l = uAmb + uSunCol * d * (d > 0.0 ? sunlit(n) : 1.0);" & LF &
     "    for (int i = 0; i < uLights; i++) {" & LF &
     "      vec3 v = vPos - uLP[i]; float dist = length(v); vec3 dn = v / max(dist, 0.001);" & LF &
     "      float cone = smoothstep(0.80, 0.94, dot(dn, uLD[i]));" & LF &
     "      float near = smoothstep(0.0, 6.0, dist);" & LF &
     "      float att = 1.0 / (1.0 + dist * dist / 30000.0);" & LF &
     "      l += vec3(1.0, 0.93, 0.75) * 1.6 * cone * near * att * max(dot(n, -dn), 0.15);" & LF &
     "    }" & LF &
     "    c *= l;" & LF &
     "  }" & LF &
     "  float f = clamp((length(vPos - uEye) - uFogNear) / (uFogFar - uFogNear), 0.0, 1.0);" & LF &
     "  frag = vec4(mix(c, uFog * base.a, f), base.a);" & LF &
     "}" & LF;

   --  The shadow pass: only how far things are from the sun
   Depth_Vertex : constant String :=
     "#version 330 core" & LF &
     "layout(location=0) in vec3 aPos;" & LF &
     "uniform mat4 uVP;" & LF &
     "void main() { gl_Position = uVP * vec4(aPos, 1.0); }" & LF;
   Depth_Fragment : constant String :=
     "#version 330 core" & LF &
     "void main() { }" & LF;

   Depth_Prog : GLuint := 0;
   U_Depth_VP, U_Shadow, U_Light_VP, U_Shadow_On, U_Shadow_Center, U_Shadow_Radius : GLint := -1;
   Shadow_Size : constant := 4096;
   Shadow_Radius : constant := 900.0;   --  the shadows reach this far from their middle
   Shadow_FB, Shadow_Tex : aliased GLuint := 0;
   Shadows_Ok : Boolean := False;

   Prog : GLuint := 0;
   U_VP, U_Tex, U_Sun, U_Sun_Col, U_Amb, U_Fog, U_Eye, U_Fog_Near, U_Fog_Far,
   U_Lights, U_LP, U_LD : GLint := -1;

   World_Tex, Hud_Tex : aliased GLuint := 0;
   Max_Tex : aliased GLint := 4096;

   Static_B, Dyn_B, Glass_B, Hud_B : Mesh.Buffer;
   Clear_B : Mesh.Buffer;   --  the see-through things that stay: glass, water

   --  The light and air of the place
   Sky_C       : Color := (0.75, 0.72, 0.66, 1.0);
   Sun_Col   : V3 := (0.75, 0.72, 0.65);
   Ambient   : V3 := (0.45, 0.45, 0.48);
   Night     : Boolean := False;
   Fog_Near  : Float := 700.0;
   Fog_Far   : Float := 2600.0;
   Ground_Y  : Float := 0.0;    --  where the picture lies
   Table_Drop : constant := 260.0;
   Fly_Height : Float := 0.0;   --  how high the vehicles of the track ride

   ---------------------------------------------------------------------------
   --  The place
   ---------------------------------------------------------------------------

   procedure Set_Air is
   begin
      Night := False;
      Fog_Near := (if Scenery.Indoors then 2200.0 else 2500.0);
      Fog_Far := (if Scenery.Indoors then 7500.0 else 9500.0);
      Sun_Col := (0.75, 0.72, 0.65);
      Ambient := (0.45, 0.45, 0.48);
      case Theme is
         when Sky | Bedroom =>
            Sky_C := (0.55, 0.75, 0.97, 1.0);
         when Garden | Easter | Mud | Beach =>
            Sky_C := (0.62, 0.80, 0.97, 1.0);
            Sun_Col := (0.85, 0.80, 0.70);
         when Ice | Arctic =>
            Sky_C := (0.80, 0.88, 0.96, 1.0);
         when Moon =>
            Sky_C := (0.02, 0.02, 0.05, 1.0);
            Ambient := (0.25, 0.25, 0.30);
            Sun_Col := (0.95, 0.95, 0.95);
            Fog_Near := 3000.0;
            Fog_Far := 11000.0;
         when Alien =>
            Sky_C := (0.35, 0.20, 0.42, 1.0);
            Ambient := (0.40, 0.32, 0.48);
         when Halloween =>
            Sky_C := (0.07, 0.05, 0.13, 1.0);
            Ambient := (0.16, 0.14, 0.24);
            Sun_Col := (0.18, 0.18, 0.30);
            Night := True;
         when Attic =>
            Sky_C := (0.03, 0.03, 0.05, 1.0);
            Ambient := (0.10, 0.10, 0.13);
            Sun_Col := (0.12, 0.13, 0.20);   --  moonlight through the window
            Night := True;
            Fog_Near := 900.0;
            Fog_Far := 4200.0;
         when Fish_Tank =>
            Sky_C := (0.12, 0.38, 0.48, 1.0);
            Fog_Near := 400.0;
            Fog_Far := 2400.0;
            Ambient := (0.40, 0.48, 0.52);
         when others =>
            Sky_C := (0.74, 0.70, 0.64, 1.0);   --  the walls of the room
      end case;
   end Set_Air;


   procedure Ground_Quad (X0, Z0, X1, Z1, Y : Float; Tex : Float; C : Color) is
   begin
      Quad (Static_B, (X0, Y, Z0), (X1, Y, Z0), (X1, Y, Z1), (X0, Y, Z1), C, Tex);
   end Ground_Quad;

   procedure Build_World is
      W : constant Float := Tracks.Width;
      H : constant Float := Tracks.Height;
   begin
      Reset (Static_B);
      Mesh.World_W := W;
      Mesh.World_H := H;
      Pull := 1.0;
      Fly_Height := (if Vehicle = Plane then 46.0 else 0.0);
      Ground_Y := (if Vehicle = Plane then -140.0 else 0.0);

      Reset (Clear_B);
      Scenery.Build (Static_B, Clear_B, Ground_Y, Sky_C);
      Upload (Clear_B, Static => True);

      --  The things in the way
      Models.Set_Picture;
      for I in 1 .. Item_Count loop
         Models.Item (Static_B, Get_Item (I), Ground_Y, Fly_Height);
      end loop;
      Upload (Static_B, Static => True);
   end Build_World;

   procedure Upload_World_Picture is
      use Cairo.Image_Surface;
      Pic : constant Cairo_Surface := Art.World;
      PW  : constant Gint := Get_Width (Pic);
      PH  : constant Gint := Get_Height (Pic);
   begin
      Cairo.Surface.Flush (Pic);
      if World_Tex = 0 then
         Gen_Textures (1, World_Tex'Access);
      end if;
      Bind_Texture (GL_TEXTURE_2D, World_Tex);
      Pixel_Storei (GL_UNPACK_ROW_LENGTH, GLint (Get_Stride (Pic) / 4));
      Pixel_Storei (GL_UNPACK_ALIGNMENT, 4);
      if Integer (PW) > Integer (Max_Tex) or else Integer (PH) > Integer (Max_Tex) then
         raise Program_Error with "the world's picture is larger than the card takes";
      end if;
      Tex_Image_2D (GL_TEXTURE_2D, 0, GL_RGB8, GLsizei (PW), GLsizei (PH), 0, GL_BGRA, GL_UNSIGNED_BYTE,
                    Get_Data_Generic (Pic));
      Pixel_Storei (GL_UNPACK_ROW_LENGTH, 0);
      Generate_Mipmap (GL_TEXTURE_2D);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      Tex_Parameterf (GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY, 16.0);
   end Upload_World_Picture;




   ---------------------------------------------------------------------------
   --  The frame
   ---------------------------------------------------------------------------

   function Interp_P (C : Cars.Car; Alpha : Float) return Geom.Vec is (Geom.Lerp (C.Prev_P, C.P, Alpha));
   function Interp_H (C : Cars.Car; Alpha : Float) return Float is
     (C.Prev_H + Geom.Wrap (C.H - C.Prev_H) * Alpha);

   function Base_Y return Float is (if Vehicle = Plane then Fly_Height else Ground_Y);

   --  How high the car's body rides: its jump, the plane's height, its fall
   function Ride (C : Cars.Car) return Float is
     (Base_Y + C.Z - (if C.Fall_T > 0.0 then 500.0 * C.Fall_T * C.Fall_T else 0.0));

   type GLfloat_3 is array (0 .. 2) of GLfloat with Convention => C;

   Lights_P, Lights_D : array (0 .. 7) of V3;
   Light_Count : Natural := 0;

   Clock : Float := 0.0;
   Frame_Alpha : Float := 1.0;

   --  How each vehicle leans and pitches just now
   type Lean_State is record
      Roll, Pitch : Float := 0.0;
      Speed : Float := 0.0;     --  a frame ago
      Bounce : Float := 0.0;    --  a landing, nose down for a moment
   end record;
   Leans : array (Race.Car_Index) of Lean_State;


   ---------------------------------------------------------------------------
   --  Particles: smoke, dust, sparks, spray, flame and confetti
   ---------------------------------------------------------------------------

   type Particle_Kind is (Smoke, Dust, Spark, Spray, Flame, Confetti, Bubble);
   type Particle is record
      Kind : Particle_Kind := Smoke;
      P, V : V3;
      Life, Span : Float := 0.0;    --  seconds left, and all it had
      Size0, Size1 : Float := 4.0;  --  how big it starts and ends
      C : Color;
   end record;
   Max_Particles : constant := 1500;
   Parts : array (1 .. Max_Particles) of Particle;
   Next_Part : Positive := 1;
   Rand : Geom.Seed := 4242;
   Part_B : Mesh.Buffer;
   Part_Tex : aliased GLuint := 0;
   Emit_T : array (Race.Car_Index) of Float := (others => 0.0);

   function Rnd return Float is (Geom.Random (Rand));
   function Spr return Float is (Geom.Spread (Rand));

   procedure Spawn (K : Particle_Kind; P, V : V3; Span, Size0, Size1 : Float; C : Color) is
   begin
      Parts (Next_Part) := (K, P, V, Span, Span, Size0, Size1, C);
      Next_Part := (if Next_Part = Max_Particles then 1 else Next_Part + 1);
   end Spawn;

   function Ground_At (P : Geom.Vec) return Color renames Models.Ground_At;

   function Lighter (C : Color; F : Float) return Color is
     (C.R + (1.0 - C.R) * F, C.G + (1.0 - C.G) * F, C.B + (1.0 - C.B) * F, C.A);

   procedure Hear (E : Race.Event) is
      P : constant V3 := (E.P.X, Base_Y + 5.0, E.P.Y);
      Watery : constant Boolean := Theme in Bath | Fish_Tank | Ice | Beach | Arctic;
   begin
      case E.Kind is
         when Race.Bump =>
            if E.Size > 60.0 then
               for K in 1 .. Natural (Float'Min (24.0, E.Size / 12.0)) loop
                  Spawn (Spark, P, (Spr * 90.0, 40.0 + Rnd * 90.0, Spr * 90.0), 0.35 + Rnd * 0.3, 1.6, 0.6,
                         (1.0, 0.85 + Rnd * 0.15, 0.4, 1.0));
               end loop;
            end if;
         when Race.Fell | Race.Splash =>
            if Watery or else E.Kind = Race.Splash then
               for K in 1 .. 26 loop
                  Spawn (Spray, (P.X, Ground_Y + 1.0, P.Z), (Spr * 60.0, 80.0 + Rnd * 120.0, Spr * 60.0),
                         0.7 + Rnd * 0.4, 3.0, 5.0, (0.85, 0.92, 1.0, 0.8));
               end loop;
            end if;
         when Race.Landed =>
            if E.Car in Race.Car_Index then
               Leans (E.Car).Bounce := -0.14;
            end if;
            for K in 1 .. 14 loop
               Spawn (Dust, (P.X + Spr * 10.0, Base_Y + 2.0, P.Z + Spr * 10.0), (Spr * 40.0, 10.0 + Rnd * 20.0, Spr * 40.0),
                      0.8 + Rnd * 0.5, 5.0, 14.0, Lighter (Ground_At (E.P), 0.2));
            end loop;
         when Race.Exploded =>
            for K in 1 .. 30 loop
               Spawn (Flame, P, (Spr * 70.0, 20.0 + Rnd * 70.0, Spr * 70.0), 0.4 + Rnd * 0.4, 6.0, 2.0,
                      (1.0, 0.45 + Rnd * 0.4, 0.1, 1.0));
            end loop;
            for K in 1 .. 20 loop
               Spawn (Smoke, P, (Spr * 30.0, 20.0 + Rnd * 30.0, Spr * 30.0), 1.2 + Rnd * 0.8, 6.0, 20.0,
                      (0.25, 0.25, 0.27, 0.8));
            end loop;
            for K in 1 .. 16 loop
               Spawn (Spark, P, (Spr * 140.0, 60.0 + Rnd * 120.0, Spr * 140.0), 0.5 + Rnd * 0.3, 1.8, 0.5,
                      (1.0, 0.9, 0.5, 1.0));
            end loop;
         when Race.Picked =>
            for K in 1 .. 16 loop
               Spawn (Confetti, P + (0.0, 4.0, 0.0), (Spr * 50.0, 50.0 + Rnd * 60.0, Spr * 50.0), 0.9 + Rnd * 0.4,
                      2.2, 2.2, (0.5 + 0.5 * Rnd, 0.5 + 0.5 * Rnd, 0.5 + 0.5 * Rnd, 1.0));
            end loop;
         when Race.Finished =>
            for K in 1 .. 60 loop
               Spawn (Confetti, P + (0.0, 10.0, 0.0), (Spr * 90.0, 90.0 + Rnd * 120.0, Spr * 90.0), 1.6 + Rnd * 0.8,
                      2.5, 2.5, (0.4 + 0.6 * Rnd, 0.4 + 0.6 * Rnd, 0.4 + 0.6 * Rnd, 1.0));
            end loop;
         when Race.Put_Back =>
            for K in 1 .. 20 loop
               Spawn (Spark, P, (Spr * 40.0, 30.0 + Rnd * 60.0, Spr * 40.0), 0.6, 2.0, 0.5, (0.9, 0.95, 1.0, 1.0));
            end loop;
         when others =>
            null;
      end case;
   end Hear;

   --  What the cars throw up as they go
   Bubble_T : Float := 0.0;

   procedure Emit (Dt : Float) is
      St : State_Type renames Race.State;
   begin
      --  bubbles from the air stones of the fish tank
      if Theme = Fish_Tank then
         Bubble_T := Bubble_T + Dt;
         while Bubble_T > 0.02 loop
            Bubble_T := Bubble_T - 0.02;
            for I in 1 .. Item_Count loop
               if Get_Item (I).Kind = Air_Stone and then Rnd < 0.5 then
                  Spawn (Bubble, (Get_Item (I).S.C.X + Spr * 6.0, Ground_Y + 4.0, Get_Item (I).S.C.Y + Spr * 6.0),
                         (Spr * 4.0, 60.0 + 40.0 * Rnd, Spr * 4.0), 9.0, 1.5 + 2.0 * Rnd, 3.0 + 2.0 * Rnd,
                         (0.85, 0.95, 1.0, 0.55));
               end if;
            end loop;
         end loop;
      end if;
      for I in 1 .. St.Count loop
         declare
            C : Cars.Car renames St.Racers (I).Car;
            H : constant Float := C.H;
            Fwd : constant V3 := (Cos (H), 0.0, Sin (H));
            Sd : constant V3 := (-Fwd.Z, 0.0, Fwd.X);
            Back : constant V3 := (C.P.X, Ride (C) + 2.0, C.P.Y) + (-11.0) * Fwd;
            Wheeled : constant Boolean := Vehicle not in Plane | Boat | Hovercraft | Submarine;
            Rate : Float := 0.0;
         begin
            if not Cars.Falling (C) then
               Emit_T (I) := Emit_T (I) + Dt;
               if C.Boost_T > 0.0 then
                  Rate := 60.0;
               elsif not C.Air and then C.Speed > 70.0 and then Vehicle not in Plane | Submarine then
                  if Vehicle in Boat | Hovercraft or else C.Under = Water then
                     Rate := C.Speed / 8.0;
                  elsif Wheeled and then C.Under in Floor | Sand then
                     Rate := C.Speed / 10.0;
                  elsif Wheeled and then C.Slip > 0.35 then
                     Rate := 50.0 * C.Slip;
                  end if;
               end if;
               while Rate > 0.0 and then Emit_T (I) > 1.0 / Rate loop
                  Emit_T (I) := Emit_T (I) - 1.0 / Rate;
                  if C.Boost_T > 0.0 then
                     Spawn (Flame, Back + (0.0, 3.0, 0.0), (-40.0) * Fwd + (Spr * 10.0, 10.0, Spr * 10.0),
                            0.25 + Rnd * 0.15, 4.0, 1.0, (1.0, 0.55 + Rnd * 0.3, 0.15, 1.0));
                  elsif Vehicle in Boat | Hovercraft or else C.Under = Water then
                     Spawn (Spray, Back + (Spr * 6.0) * Sd, (-30.0) * Fwd + (Spr * 30.0, 40.0 + Rnd * 40.0, Spr * 30.0),
                            0.6, 2.5, 5.0, (0.88, 0.94, 1.0, 0.7));
                  elsif C.Under in Floor | Sand then
                     Spawn (Dust, Back + (Spr * 6.0) * Sd, (-20.0) * Fwd + (Spr * 15.0, 8.0 + Rnd * 12.0, Spr * 15.0),
                            0.9 + Rnd * 0.5, 4.0, 13.0, Lighter (Ground_At (C.P), 0.15));
                  else
                     Spawn (Smoke, Back + (Spr * 6.0) * Sd, (Spr * 10.0, 6.0 + Rnd * 8.0, Spr * 10.0),
                            1.0 + Rnd * 0.5, 4.0, 14.0, (0.85, 0.85, 0.85, 0.5));
                  end if;
               end loop;
               if Rate = 0.0 then
                  Emit_T (I) := 0.0;
               end if;
            end if;
         end;
      end loop;
   end Emit;

   procedure Step_Particles (Dt : Float) is
   begin
      for Pt of Parts loop
         if Pt.Life > 0.0 then
            Pt.Life := Pt.Life - Dt;
            Pt.P := Pt.P + Dt * Pt.V;
            case Pt.Kind is
               when Spark | Spray | Confetti =>
                  Pt.V.Y := Pt.V.Y - (if Pt.Kind = Confetti then 120.0 else 300.0) * Dt;
                  if Pt.Kind = Confetti then
                     Pt.V := (1.0 - 2.0 * Dt) * Pt.V;
                  end if;
                  if Pt.P.Y < Ground_Y then
                     Pt.P.Y := Ground_Y;
                     Pt.V := (0.5 * Pt.V.X, -0.3 * Pt.V.Y, 0.5 * Pt.V.Z);
                  end if;
               when Smoke | Dust | Flame =>
                  Pt.V := (1.0 - 1.5 * Dt) * Pt.V;
                  Pt.V.Y := Pt.V.Y + 6.0 * Dt;
               when Bubble =>
                  Pt.P.X := Pt.P.X + Sin (Clock * 6.0 + Pt.Span * 40.0) * 12.0 * Dt;
                  if Pt.P.Y > Ground_Y + 455.0 then
                     Pt.Life := 0.0;   --  out at the top of the water
                  end if;
            end case;
         end if;
      end loop;
   end Step_Particles;

   procedure Make_Particle_Texture is
      N : constant := 64;
      type Pixels is array (0 .. N * N * 4 - 1) of Interfaces.Unsigned_8;
      Data : Pixels;
   begin
      for Y in 0 .. N - 1 loop
         for X in 0 .. N - 1 loop
            declare
               DX : constant Float := (Float (X) + 0.5) / Float (N) * 2.0 - 1.0;
               DY : constant Float := (Float (Y) + 0.5) / Float (N) * 2.0 - 1.0;
               R  : constant Float := Sqrt (DX * DX + DY * DY);
               A  : constant Float := Geom.Clamp (1.0 - R, 0.0, 1.0);
               I  : constant Natural := (Y * N + X) * 4;
            begin
               Data (I .. I + 2) := (255, 255, 255);
               Data (I + 3) := Interfaces.Unsigned_8 (255.0 * A * A * (3.0 - 2.0 * A));
            end;
         end loop;
      end loop;
      Gen_Textures (1, Part_Tex'Access);
      Bind_Texture (GL_TEXTURE_2D, Part_Tex);
      Pixel_Storei (GL_UNPACK_ALIGNMENT, 1);
      Tex_Image_2D (GL_TEXTURE_2D, 0, GL_RGBA8, N, N, 0, GL_RGBA, GL_UNSIGNED_BYTE, Data'Address);
      Pixel_Storei (GL_UNPACK_ALIGNMENT, 4);
      Generate_Mipmap (GL_TEXTURE_2D);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
   end Make_Particle_Texture;

   --  The particles as squares turned to the eye
   procedure Build_Particles (Eye, Target : V3) is
      F : constant V3 := Normal (Target - Eye);
      R : constant V3 := Normal (Cross (F, Up));
      U : constant V3 := Cross (R, F);
   begin
      Reset (Part_B);
      for Pt of Parts loop
         if Pt.Life > 0.0 then
            declare
               T : constant Float := 1.0 - Pt.Life / Pt.Span;   --  0 new .. 1 gone
               Sz : constant Float := Pt.Size0 + (Pt.Size1 - Pt.Size0) * T;
               A : constant Float := Pt.C.A * (if Pt.Kind in Smoke | Dust then (1.0 - T) * Float'Min (1.0, T * 8.0)
                                               elsif Pt.Kind = Bubble then 1.0
                                               else 1.0 - T * T);
               C : constant Color := (Pt.C.R, Pt.C.G, Pt.C.B, A);
               DR : constant V3 := Sz * R;
               DU : constant V3 := Sz * U;
            begin
               Vertex_Full (Part_B, Pt.P - DR - DU, C, 0.0, 1.0);
               Vertex_Full (Part_B, Pt.P + DR - DU, C, 1.0, 1.0);
               Vertex_Full (Part_B, Pt.P + DR + DU, C, 1.0, 0.0);
               Vertex_Full (Part_B, Pt.P - DR - DU, C, 0.0, 1.0);
               Vertex_Full (Part_B, Pt.P + DR + DU, C, 1.0, 0.0);
               Vertex_Full (Part_B, Pt.P - DR + DU, C, 0.0, 0.0);
            end;
         end if;
      end loop;
      Upload (Part_B, Static => False);
   end Build_Particles;

   ---------------------------------------------------------------------------
   --  Skid marks: strips on the floor, the oldest giving way to the newest
   ---------------------------------------------------------------------------

   Max_Marks : constant := 6000;
   type Mark is record
      A, B : Geom.Vec;
      W : Float := 2.4;
      C : Color;
   end record;
   Marks : array (1 .. Max_Marks) of Mark;
   Next_Mark : Positive := 1;
   Mark_Count : Natural := 0;
   Marks_Changed : Boolean := True;
   Mark_B : Mesh.Buffer;
   type Wheel_Pair is array (1 .. 2) of Geom.Vec;
   Last_Wheels : array (Race.Car_Index) of Wheel_Pair;
   Had_Wheels : array (Race.Car_Index) of Boolean := (others => False);

   procedure Clear_Marks is
   begin
      Mark_Count := 0;
      Next_Mark := 1;
      Marks_Changed := True;
      Had_Wheels := (others => False);
   end Clear_Marks;

   procedure Leave_Marks is
      St : State_Type renames Race.State;
      Bike : constant Boolean := Vehicle in Bike_Kind;
   begin
      for I in 1 .. St.Count loop
         declare
            C : Cars.Car renames St.Racers (I).Car;
            F : constant Geom.Vec := Geom.Dir (C.H);
            R : constant Geom.Vec := Geom.Perp (F);
            Now : constant Wheel_Pair :=
              (if Bike then (C.P - F * 8.0, C.P - F * 8.0) else (C.P - F * 7.0 - R * 6.0, C.P - F * 7.0 + R * 6.0));
            On_Ground : constant Boolean := not C.Air and then not Cars.Falling (C);
            Rough : constant Boolean := C.Under in Floor | Sand;
            Strength : constant Float :=
              (if not On_Ground then 0.0
               elsif Rough and then Theme /= Workbench then Float'Max (C.Slip, Float'Min (0.7, C.Speed / 300.0))
               elsif C.Slip > 0.12 then C.Slip
               else 0.0);
            Look : Art.RGB;
            Alpha, W : Float;
            Seen : Boolean;
         begin
            if Strength = 0.0 or else not Had_Wheels (I) then
               Last_Wheels (I) := Now;
               Had_Wheels (I) := True;
            elsif Geom.Distance (Last_Wheels (I) (1), Now (1)) > 30.0 then
               Last_Wheels (I) := Now;   --  put back somewhere else
            elsif Geom.Distance (Last_Wheels (I) (1), Now (1)) >= 4.0 then
               Art.Skid_Look (Strength, C.Under, Look, Alpha, W, Seen);
               if Seen then
                  for K in 1 .. (if Bike then 1 else 2) loop
                     Marks (Next_Mark) := (Last_Wheels (I) (K), Now (K), W, (Look.R, Look.G, Look.B, Alpha));
                     Next_Mark := (if Next_Mark = Max_Marks then 1 else Next_Mark + 1);
                     Mark_Count := Natural'Min (Max_Marks, Mark_Count + 1);
                  end loop;
                  Marks_Changed := True;
               end if;
               Last_Wheels (I) := Now;
            end if;
         end;
      end loop;
   end Leave_Marks;

   procedure Build_Marks is
   begin
      if not Marks_Changed then
         return;
      end if;
      Reset (Mark_B);
      for K in 1 .. Mark_Count loop
         declare
            M : Mark renames Marks (K);
            D : constant Geom.Vec := Geom.Normal ((M.B.X - M.A.X, M.B.Y - M.A.Y));
            Across : constant V3 := (-D.Y * M.W / 2.0, 0.0, D.X * M.W / 2.0);
            A : constant V3 := (M.A.X, Ground_Y + 0.05, M.A.Y);
            B : constant V3 := (M.B.X, Ground_Y + 0.05, M.B.Y);
         begin
            Quad (Mark_B, A - Across, A + Across, B + Across, B - Across, M.C, Lit => False);
         end;
      end loop;
      Upload (Mark_B, Static => False);
      Marks_Changed := False;
   end Build_Marks;

   ---------------------------------------------------------------------------
   --  How the vehicles lean in a turn and pitch as they speed up, brake and fly
   ---------------------------------------------------------------------------

   procedure Update_Leans (Dt : Float) is
      St : State_Type renames Race.State;
      Into : constant Boolean := Vehicle in Bike_Kind | Plane | Snowmobile | Hovercraft | Boat;
      Most : constant Float := (case Vehicle is
                                   when Bike_Kind => 0.55,
                                   when Plane => 0.7,
                                   when Monster_Truck => 0.14,
                                   when Boat | Hovercraft | Snowmobile => 0.25,
                                   when others => 0.07);
   begin
      for I in 1 .. St.Count loop
         declare
            C : Cars.Car renames St.Racers (I).Car;
            L : Lean_State renames Leans (I);
            Yaw : constant Float := Geom.Wrap (C.H - C.Prev_H) / Race.Dt;      --  turning right, positive
            Accel : constant Float := (C.Forward - L.Speed) / Float'Max (Dt, 1.0E-3);
            Want_Roll : constant Float :=
              Geom.Clamp ((if Into then 0.0045 else -0.0012) * C.Speed * Yaw, -Most, Most);
            Want_Pitch : constant Float :=
              (if C.Air then Geom.Clamp (C.Vz / (abs C.Speed + 60.0) * 0.8, -0.35, 0.35)
               elsif Vehicle = Plane then 0.0
               else Geom.Clamp (Accel * 0.00012, -0.06, 0.05));
            K : constant Float := Float'Min (1.0, 8.0 * Dt);
         begin
            L.Roll := L.Roll + (Want_Roll - L.Roll) * K;
            L.Pitch := L.Pitch + (Want_Pitch - L.Pitch) * K;
            L.Bounce := L.Bounce * Float'Max (0.0, 1.0 - 6.0 * Dt);
            L.Speed := C.Forward;
         end;
      end loop;
   end Update_Leans;

   --  Where each car's vertices lie in the buffer of the things that move, to leave
   --  out the one whose driver's eyes the cockpit view looks through
   Car_First, Car_Count : array (Race.Car_Index) of Natural := (others => 0);
   Cockpit_B : Mesh.Buffer;

   ---------------------------------------------------------------------------
   --  The things that move, built once a frame for every view
   ---------------------------------------------------------------------------

   procedure Build_Dynamic (Alpha : Float) is
      St : State_Type renames Race.State;
   begin
      Reset (Dyn_B);
      Reset (Glass_B);
      Light_Count := 0;
      Pull := 1.0;

      --  The cars, and their shadows
      for I in 1 .. St.Count loop
         declare
            R  : Racer renames St.Racers (I);
            C  : Cars.Car renames R.Car;
            P  : constant Geom.Vec := Interp_P (C, Alpha);
            H  : constant Float := Interp_H (C, Alpha);
            Y  : constant Float := Ride (C);
            Fwd : constant V3 := (Cos (H), 0.0, Sin (H));
            Bob : constant Float :=
              (if Vehicle in Boat | Hovercraft | Submarine then 0.8 * Sin (Clock * 3.0 + Float (I)) else 0.0);
            Pc : constant Palette.RGB := Palette.Paint (R.Paint);
         begin
            Car_First (I) := Vertices (Dyn_B);
            Mesh.Set_Tilt ((P.X, Y + Bob, P.Y), Fwd, Leans (I).Pitch + Leans (I).Bounce, Leans (I).Roll);
            Models.Vehicle (Dyn_B, Glass_B, (P.X, Y + Bob, P.Y), H, (Pc.R, Pc.G, Pc.B, 1.0));
            Mesh.No_Tilt;
            Car_Count (I) := Vertices (Dyn_B) - Car_First (I);
            if not Cars.Falling (C) then
               declare
                  Lift : constant Float := Y - Ground_Y;
                  Dark : constant Float := 0.45 / (1.0 + Lift / 40.0);
               begin
                  Disc (Glass_B, (P.X, Ground_Y + 0.3, P.Y), 15.0, 9.0, H, (0.0, 0.0, 0.0, Dark), 14);
               end;
               if R.Shield_T > 0.0 then
                  Sphere (Glass_B, (P.X, Y + 6.0, P.Y), 18.0, (0.3, 0.8, 1.0, 0.22), 14);
               end if;
            end if;
            if Night and then Light_Count < 8 then
               Lights_P (Light_Count) := (P.X, Y + 6.0, P.Y) + 12.0 * Fwd;
               Lights_D (Light_Count) := Normal (Fwd + (0.0, -0.12, 0.0));
               Light_Count := Light_Count + 1;
            end if;
         end;
      end loop;

      --  The ghost of the best lap
      if Ghost_On then
         Models.Vehicle (Glass_B, Glass_B, (Ghost_P.X, Base_Y, Ghost_P.Y), Ghost_H, (0.85, 0.9, 1.0, 1.0), 0.35);
      end if;

      --  The things that move across the road
      for I in 1 .. Mover_Count loop
         declare
            M : constant Mover := Get_Mover (I);
            P : Geom.Vec;
            Hd, Lift : Float;
            Seen : Boolean;
         begin
            Mover_At (M, St.Clock, P, Hd, Seen, Lift);
            if Seen then
               Models.Mover (Dyn_B, Glass_B, M, P, Hd, Lift, Ground_Y, Clock);
               Disc (Glass_B, (P.X, Ground_Y + 0.25, P.Y), M.Radius * 1.1, M.Radius * 1.1, 0.0,
                     (0.0, 0.0, 0.0, 0.3 / (1.0 + Lift / 30.0)), 12);
            end if;
         end;
      end loop;

      --  The pick-ups: boxes with a question on every side, turning
      for K in 1 .. N_Boxes loop
         if Boxes (K).Active then
            declare
               P : constant Geom.Vec := Boxes (K).P;
               A : constant Float := Clock * 1.7 + Float (K);
               Fwd : constant V3 := (Cos (A), 0.0, Sin (A));
               Y : constant Float := Base_Y + 9.0 + 2.0 * Sin (Clock * 3.0 + Float (K));
               Hue : constant Float := Clock * 2.0 + Float (K);
               C : constant Color := (0.65 + 0.35 * Sin (Hue), 0.65 + 0.35 * Sin (Hue + 2.1), 0.65 + 0.35 * Sin (Hue + 4.2), 1.0);
            begin
               Block (Dyn_B, (P.X, Y, P.Y), Fwd, 0.0, 0.0, 0.0, 5.0, 5.0, 5.0, C);
               Block (Dyn_B, (P.X, Y, P.Y), Fwd, 0.0, 0.0, 0.0, 5.3, 1.2, 5.3, (1.0, 1.0, 1.0, 1.0));
               Block (Dyn_B, (P.X, Y, P.Y), Fwd, 0.0, 0.0, 0.0, 1.2, 5.3, 5.3, (1.0, 1.0, 1.0, 1.0));
               Disc (Glass_B, (P.X, Ground_Y + 0.25, P.Y), 8.0, 8.0, 0.0, (0.0, 0.0, 0.0, 0.3), 10);
            end;
         end if;
      end loop;
      for S of Slicks loop
         if S.Life > 0.0 then
            Disc (Glass_B, (S.P.X, Ground_Y + 0.35, S.P.Y), 22.0, 18.0, 0.7, (0.02, 0.02, 0.03, 0.85), 18);
         end if;
      end loop;
      for M of Rockets loop
         if M.Life > 0.0 then
            declare
               Fwd : constant V3 := (Cos (M.H), 0.0, Sin (M.H));
               O : constant V3 := (M.P.X, Base_Y + 8.0, M.P.Y);
            begin
               Barrel (Dyn_B, O, Fwd, 1.6, 5.0, (0.85, 0.15, 0.10, 1.0), 8);
               Spawn (Smoke, O + (-6.0) * Fwd, (Spr * 5.0, 4.0, Spr * 5.0), 0.6, 2.5, 7.0, (0.8, 0.8, 0.8, 0.6));
               Spawn (Flame, O + (-6.0) * Fwd, (0.0, 0.0, 0.0), 0.12, 3.0, 1.0, (1.0, 0.7, 0.2, 1.0));
            end;
         end if;
      end loop;
   end Build_Dynamic;

   ---------------------------------------------------------------------------
   --  The cameras: one for each player's view
   ---------------------------------------------------------------------------

   type Cam_State is record
      H : Float := 0.0;
      Eye, Target : V3;
      Fresh : Boolean := True;
      Shake : Float := 0.0;
   end record;
   Cams : array (Slot) of Cam_State;

   procedure Place_Camera (S : Slot; Car : Race.Car_Index; Kind : Camera_Kind; Orbit : Boolean; Dt : Float;
                           Shared : Boolean := False) is
      Cm : Cam_State renames Cams (S);
      C : Cars.Car renames Race.State.Racers (Car).Car;
      P : constant Geom.Vec := Interp_P (C, Frame_Alpha);
      H : constant Float := Interp_H (C, Frame_Alpha);
      Body_Y : constant Float := (if Cars.Falling (C) then Base_Y else Ride (C));
      Rate : constant Float := (if Kind = Bumper then 20.0 else 5.0);
      Eye, Target : V3;
   begin
      if Cm.Fresh then
         Cm.H := H;
      else
         Cm.H := Cm.H + Geom.Wrap (H - Cm.H) * Float'Min (1.0, Rate * Dt);
      end if;
      declare
         Fwd : constant V3 := (Cos (Cm.H), 0.0, Sin (Cm.H));
         O : constant V3 := (P.X, Body_Y, P.Y);
      begin
         if Shared then
            declare
               Mid : constant Geom.Vec := Geom.Lerp (Race.State.Prev_Cam, Race.State.Cam, Frame_Alpha);
               M : constant V3 := (Mid.X, Base_Y, Mid.Y);
            begin
               Eye := M + (0.0, Shared_Height, Shared_Back);
               Target := M;
            end;
         elsif Orbit then
            --  round the leader, slowly, for the title
            Eye := O + (150.0 * Cos (Clock * 0.17), 55.0 + 25.0 * Sin (Clock * 0.11), 150.0 * Sin (Clock * 0.17));
            Target := O + (0.0, 8.0, 0.0);
         else
            case Kind is
               when Chase =>
                  Eye := O + (-62.0) * Fwd + (0.0, 26.0, 0.0);
                  Target := O + 30.0 * Fwd + (0.0, 6.0, 0.0);
               when Bumper =>
                  Eye := O + 13.0 * Fwd + (0.0, 8.0, 0.0);
                  Target := O + 120.0 * Fwd + (0.0, 5.0, 0.0);
               when Cockpit =>
                  declare
                     Real_Fwd : constant V3 := (Cos (H), 0.0, Sin (H));
                     Sd : constant V3 := (-Real_Fwd.Z, 0.0, Real_Fwd.X);
                     Pitch : constant Float := Leans (Car).Pitch + Leans (Car).Bounce;
                     Across : constant Float := (if Vehicle in Tracks.Car | Rover | Monster_Truck then -2.4 else 0.0);
                  begin
                     Eye := O + (-0.5) * Real_Fwd + Across * Sd + (0.0, Models.Eye_Height, 0.0);
                     Target := Eye + 120.0 * Real_Fwd + (0.0, 120.0 * Pitch - 4.0, 0.0)
                       + (120.0 * Leans (Car).Roll * 0.3) * Sd;
                  end;
               when High =>
                  Eye := O + (0.0, 330.0, 230.0);
                  Target := O;
            end case;
         end if;
      end;
      if Cm.Shake > 0.0 then
         Eye := Eye + (Cm.Shake * Sin (Clock * 71.0), Cm.Shake * 0.5 * Sin (Clock * 53.0), Cm.Shake * Cos (Clock * 61.0));
         Cm.Shake := Float'Max (0.0, Cm.Shake - 25.0 * Dt);
      end if;
      if Cm.Fresh or else Shared or else (Kind in Bumper | Cockpit and then not Orbit) then
         Cm.Eye := Eye;
         Cm.Target := Target;
      else
         --  the eye follows a little behind, so the car can be seen to turn
         Cm.Eye := Lerp (Cm.Eye, Eye, Float'Min (1.0, (if Orbit then 3.0 else 12.0) * Dt));
         Cm.Target := Lerp (Cm.Target, Target, Float'Min (1.0, (if Orbit then 3.0 else 18.0) * Dt));
      end if;
      Cm.Fresh := False;
   end Place_Camera;

   procedure Shake (S : Slot; Amount : Float) is
   begin
      Cams (S).Shake := Float'Max (Cams (S).Shake, Amount);
   end Shake;

   procedure Reset_Cameras is
   begin
      for C of Cams loop
         C.Fresh := True;
      end loop;
   end Reset_Cameras;

   procedure New_Race is
   begin
      Reset_Cameras;
      Clear_Marks;
      for Pt of Parts loop
         Pt.Life := 0.0;
      end loop;
   end New_Race;

   function Ear return Geom.Vec is ((Cams (1).Eye.X, Cams (1).Eye.Z));

   function Ear_Right return Geom.Vec is
      D : constant Geom.Vec := Geom.Normal ((Cams (1).Target.X - Cams (1).Eye.X, Cams (1).Target.Z - Cams (1).Eye.Z));
   begin
      return Geom.Perp (D);
   end Ear_Right;

   ---------------------------------------------------------------------------

   procedure Make_Shadow_Map;

   procedure Init is
   begin
      Prog := Build_Program (Vertex_Source, Fragment_Source);
      Depth_Prog := Build_Program (Depth_Vertex, Depth_Fragment);
      U_Depth_VP := Uniform (Depth_Prog, "uVP");
      U_Shadow := Uniform (Prog, "uShadow");
      U_Light_VP := Uniform (Prog, "uLightVP");
      U_Shadow_On := Uniform (Prog, "uShadowOn");
      U_Shadow_Center := Uniform (Prog, "uShadowCenter");
      U_Shadow_Radius := Uniform (Prog, "uShadowRadius");
      Make_Shadow_Map;
      U_VP := Uniform (Prog, "uVP");
      U_Tex := Uniform (Prog, "uTex");
      U_Sun := Uniform (Prog, "uSun");
      U_Sun_Col := Uniform (Prog, "uSunCol");
      U_Amb := Uniform (Prog, "uAmb");
      U_Fog := Uniform (Prog, "uFog");
      U_Eye := Uniform (Prog, "uEye");
      U_Fog_Near := Uniform (Prog, "uFogNear");
      U_Fog_Far := Uniform (Prog, "uFogFar");
      U_Lights := Uniform (Prog, "uLights");
      U_LP := Uniform (Prog, "uLP");
      U_LD := Uniform (Prog, "uLD");
      Get_Integer (GL_MAX_TEXTURE_SIZE, Max_Tex'Access);
      Gen_Textures (1, Hud_Tex'Access);
      Make_Particle_Texture;
   end Init;

   procedure New_Track is
   begin
      Art.Build;
      Set_Air;
      Build_World;
      Upload_World_Picture;
      New_Race;
   end New_Track;

   Frame_Times : Float := 0.0;
   Frame_Count : Natural := 0;
   Fps_Now : Float := 0.0;

   function Fps return Float is (Fps_Now);

   procedure Begin_Frame (Alpha, Dt : Float) is
   begin
      Clock := Clock + Dt;
      Frame_Alpha := Alpha;
      Frame_Times := Frame_Times + Dt;
      Frame_Count := Frame_Count + 1;
      if Frame_Times >= 0.5 then
         Fps_Now := Float (Frame_Count) / Frame_Times;
         Frame_Times := 0.0;
         Frame_Count := 0;
      end if;
      if Dt > 0.0 then
         Emit (Dt);
         Step_Particles (Dt);
         Leave_Marks;
         Update_Leans (Dt);
      end if;
      Build_Marks;
      Build_Dynamic (Alpha);
      Upload (Dyn_B, Static => False);
      Upload (Glass_B, Static => False);
   end Begin_Frame;

   procedure Make_Shadow_Map is
      Saved : aliased GLint := 0;
      White : aliased constant array (0 .. 3) of GLfloat := (1.0, 1.0, 1.0, 1.0);
   begin
      Get_Integer (GL_FRAMEBUFFER_BINDING, Saved'Access);
      Gen_Textures (1, Shadow_Tex'Access);
      Bind_Texture (GL_TEXTURE_2D, Shadow_Tex);
      Tex_Image_2D (GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, Shadow_Size, Shadow_Size, 0, GL_DEPTH_COMPONENT,
                    GL_FLOAT, System.Null_Address);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
      Tex_Parameterfv (GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, White'Address);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);
      Gen_Framebuffers (1, Shadow_FB'Access);
      Bind_Framebuffer (GL_FRAMEBUFFER, Shadow_FB);
      Framebuffer_Texture_2D (GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, Shadow_Tex, 0);
      Draw_Buffer (GL_NONE);
      Read_Buffer (GL_NONE);
      Shadows_Ok := Check_Framebuffer_Status (GL_FRAMEBUFFER) = GL_FRAMEBUFFER_COMPLETE;
      if Ada.Environment_Variables.Exists ("ADAMACHINES_GL_DEBUG") then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "shadows: " & Boolean'Image (Shadows_Ok)
                               & " framebuffer was" & GLint'Image (Saved));
      end if;
      Bind_Framebuffer (GL_FRAMEBUFFER, GLuint (Saved));
   end Make_Shadow_Map;

   Sun : constant V3 := Normal ((0.62, 0.72, 0.42));   --  well up, but low enough for shadows to show
   Light_VP : Mat4;
   Shadow_Center : V3;

   --  The things that cast shadows, seen from the sun, around Center
   procedure Shadow_Pass (Center : V3) is
      Saved : aliased GLint := 0;
      F : constant V3 := (-1.0) * Sun;
      S : constant V3 := Normal (Cross (F, (1.0, 0.0, 0.0)));
      U : constant V3 := Cross (S, F);
      Texel : constant Float := 2.0 * Shadow_Radius / Float (Shadow_Size);
      --  the middle moved a whole texel at a time, so the shadows do not shimmer as it goes
      CS : constant Float := Dot (Center, S);
      CU : constant Float := Dot (Center, U);
      C : constant V3 := Center + (Float'Rounding (CS / Texel) * Texel - CS) * S
                                + (Float'Rounding (CU / Texel) * Texel - CU) * U;
   begin
      Shadow_Center := C;
      Light_VP := Ortho (-Shadow_Radius, Shadow_Radius, -Shadow_Radius, Shadow_Radius, 1.0, 5000.0)
        * Look_At (C + 2500.0 * Sun, C, (1.0, 0.0, 0.0));
      Get_Integer (GL_FRAMEBUFFER_BINDING, Saved'Access);
      Bind_Framebuffer (GL_FRAMEBUFFER, Shadow_FB);
      Viewport (0, 0, Shadow_Size, Shadow_Size);
      Clear (GL_DEPTH_BUFFER_BIT);
      Enable (GL_DEPTH_TEST);
      Enable (GL_POLYGON_OFFSET_FILL);
      Polygon_Offset (2.0, 4.0);
      Use_Program (Depth_Prog);
      Uniform_Matrix4fv (U_Depth_VP, 1, GL_FALSE, Light_VP'Address);
      Draw (Static_B);
      Draw (Dyn_B);
      Disable (GL_POLYGON_OFFSET_FILL);
      Bind_Framebuffer (GL_FRAMEBUFFER, GLuint (Saved));
   end Shadow_Pass;

   procedure Set_Matrix (M : Mat4) is
   begin
      Uniform_Matrix4fv (U_VP, 1, GL_FALSE, M'Address);
   end Set_Matrix;

   procedure Render_View (X, Y, W, H : Natural; S : Slot; Car : Race.Car_Index; Kind : Camera_Kind;
                          Orbit : Boolean; Dt : Float; Shared : Boolean := False)
   is
      Aspect : constant Float := Float (W) / Float (Natural'Max (1, H));
      Fov : constant Float := (if Kind in Bumper | Cockpit and then not Orbit then 70.0 else 60.0) * Geom.Pi / 180.0;
      LP, LD : array (0 .. 7) of GLfloat_3;
   begin
      Place_Camera (S, Car, Kind, Orbit, Dt, Shared);
      Build_Particles (Cams (S).Eye, Cams (S).Target);
      if Shadows_Ok and then not Night then
         declare
            C : Cars.Car renames Race.State.Racers (Car).Car;
            Ahead : constant Float := (if Orbit or else Shared or else Kind = High then 0.0 else 380.0);
            Fwd : constant V3 := Normal ((Cams (S).Target.X - Cams (S).Eye.X, 0.0, Cams (S).Target.Z - Cams (S).Eye.Z));
         begin
            Shadow_Pass ((C.P.X, Base_Y, C.P.Y) + Ahead * Fwd);
         end;
      end if;

      Viewport (GLint (X), GLint (Y), GLsizei (W), GLsizei (H));
      Enable (GL_SCISSOR_TEST);
      Scissor (GLint (X), GLint (Y), GLsizei (W), GLsizei (H));
      Clear_Color (F (Sky_C.R), F (Sky_C.G), F (Sky_C.B), 1.0);
      Clear (GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT);
      Disable (GL_SCISSOR_TEST);
      Enable (GL_DEPTH_TEST);
      Depth_Func (GL_LEQUAL);
      Disable (GL_CULL_FACE);

      Use_Program (Prog);
      Set_Matrix (Perspective (Fov, Aspect, 2.0, 12000.0) * Look_At (Cams (S).Eye, Cams (S).Target, Up));
      Uniform1i (U_Tex, 0);
      Uniform3f (U_Sun, F (Sun.X), F (Sun.Y), F (Sun.Z));
      Uniform3f (U_Sun_Col, F (Sun_Col.X), F (Sun_Col.Y), F (Sun_Col.Z));
      Uniform3f (U_Amb, F (Ambient.X), F (Ambient.Y), F (Ambient.Z));
      Uniform3f (U_Fog, F (Sky_C.R), F (Sky_C.G), F (Sky_C.B));
      Uniform3f (U_Eye, F (Cams (S).Eye.X), F (Cams (S).Eye.Y), F (Cams (S).Eye.Z));
      Uniform1f (U_Fog_Near, F (Fog_Near));
      Uniform1f (U_Fog_Far, F (Fog_Far));
      for K in 0 .. Light_Count - 1 loop
         LP (K) := (F (Lights_P (K).X), F (Lights_P (K).Y), F (Lights_P (K).Z));
         LD (K) := (F (Lights_D (K).X), F (Lights_D (K).Y), F (Lights_D (K).Z));
      end loop;
      Uniform1i (U_Lights, GLint (Light_Count));
      if Light_Count > 0 then
         Uniform3fv (U_LP, GLsizei (Light_Count), LP'Address);
         Uniform3fv (U_LD, GLsizei (Light_Count), LD'Address);
      end if;

      Uniform1i (U_Shadow_On, (if not Shadows_Ok or else Night then 0
                               elsif Ada.Environment_Variables.Exists ("ADAMACHINES_SHADOW_DEBUG") then 2 else 1));
      Uniform1i (U_Shadow, 1);
      Uniform_Matrix4fv (U_Light_VP, 1, GL_FALSE, Light_VP'Address);
      Uniform3f (U_Shadow_Center, F (Shadow_Center.X), F (Shadow_Center.Y), F (Shadow_Center.Z));
      Uniform1f (U_Shadow_Radius, F (Shadow_Radius));
      Active_Texture (GL_TEXTURE1);
      Bind_Texture (GL_TEXTURE_2D, Shadow_Tex);
      Active_Texture (GL_TEXTURE0);
      Bind_Texture (GL_TEXTURE_2D, World_Tex);
      Draw (Static_B);
      if Kind = Cockpit and then not Orbit and then not Shared then
         --  everything but this car, and of it only what the driver sees
         Draw_Range (Dyn_B, 0, Car_First (Car));
         Draw_Range (Dyn_B, Car_First (Car) + Car_Count (Car), Natural'Last);
         declare
            C : Cars.Car renames Race.State.Racers (Car).Car;
            P : constant Geom.Vec := Interp_P (C, Frame_Alpha);
            H : constant Float := Interp_H (C, Frame_Alpha);
            Pc : constant Palette.RGB := Palette.Paint (Race.State.Racers (Car).Paint);
            O : constant V3 := (P.X, Ride (C), P.Y);
         begin
            Reset (Cockpit_B);
            Mesh.Set_Tilt (O, (Cos (H), 0.0, Sin (H)), Leans (Car).Pitch + Leans (Car).Bounce, Leans (Car).Roll);
            Models.Cockpit (Cockpit_B, O, H, (Pc.R, Pc.G, Pc.B, 1.0));
            Mesh.No_Tilt;
            Upload (Cockpit_B, Static => False);
            Draw (Cockpit_B);
         end;
      else
         Draw (Dyn_B);
      end if;

      --  The see-through things: shadows, oil, shields, then smoke and sparks
      Enable (GL_BLEND);
      Blend_Func (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      Depth_Mask (GL_FALSE);
      Enable (GL_POLYGON_OFFSET_FILL);
      Polygon_Offset (F (-1.0), F (-4.0));   --  over the floor they lie on, never in it
      Draw (Mark_B);
      Draw (Glass_B);
      Draw (Clear_B);
      Disable (GL_POLYGON_OFFSET_FILL);
      Bind_Texture (GL_TEXTURE_2D, Part_Tex);
      Draw (Part_B);
      Depth_Mask (GL_TRUE);
      Disable (GL_BLEND);
   end Render_View;

   --  The picture the overlay drew, over everything
   procedure Draw_Overlay (W, H : Natural) is
      use Cairo.Image_Surface;
      Pic : constant Cairo_Surface := Overlay.Surface;
   begin
      Cairo.Surface.Flush (Pic);
      Viewport (0, 0, GLsizei (W), GLsizei (H));
      Bind_Texture (GL_TEXTURE_2D, Hud_Tex);
      Pixel_Storei (GL_UNPACK_ROW_LENGTH, GLint (Get_Stride (Pic) / 4));
      Tex_Image_2D (GL_TEXTURE_2D, 0, GL_RGBA8, GLsizei (Overlay.Width), GLsizei (Overlay.Height), 0, GL_BGRA,
                    GL_UNSIGNED_BYTE, Get_Data_Generic (Pic));
      Pixel_Storei (GL_UNPACK_ROW_LENGTH, 0);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      Tex_Parameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      Reset (Hud_B);
      Vertex_UV (Hud_B, (0.0, 0.0, 0.0), 0.0, 0.0);
      Vertex_UV (Hud_B, (Float (W), 0.0, 0.0), 1.0, 0.0);
      Vertex_UV (Hud_B, (Float (W), Float (H), 0.0), 1.0, 1.0);
      Vertex_UV (Hud_B, (0.0, 0.0, 0.0), 0.0, 0.0);
      Vertex_UV (Hud_B, (Float (W), Float (H), 0.0), 1.0, 1.0);
      Vertex_UV (Hud_B, (0.0, Float (H), 0.0), 0.0, 1.0);
      Upload (Hud_B, Static => False);

      Use_Program (Prog);
      Disable (GL_DEPTH_TEST);
      Enable (GL_BLEND);
      Blend_Func (GL_ONE, GL_ONE_MINUS_SRC_ALPHA);   --  cairo's colours come multiplied by their alpha
      Set_Matrix (Ortho (0.0, Float (W), Float (H), 0.0));
      Uniform1i (U_Lights, 0);
      Uniform1i (U_Shadow_On, 0);
      Uniform1f (U_Fog_Near, 1.0E9);
      Uniform1f (U_Fog_Far, 2.0E9);
      Draw (Hud_B);
      Disable (GL_BLEND);
      Enable (GL_DEPTH_TEST);
   end Draw_Overlay;

end View;
