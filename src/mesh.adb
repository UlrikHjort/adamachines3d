--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Unchecked_Deallocation;
with System.Storage_Elements; use System.Storage_Elements;
with Geom;

package body Mesh is

   use type GL.GLuint;
   use type GL.GLint;

   Pi : constant := Geom.Pi;

   procedure Free is new Ada.Unchecked_Deallocation (Float_Array, Float_Access);

   procedure Reset (B : in out Buffer) is
   begin
      B.Count := 0;
   end Reset;

   function Vertices (B : Buffer) return Natural is (B.Count / Stride);

   procedure Grow (B : in out Buffer) is
      New_Data : Float_Access;
   begin
      if B.Data = null then
         B.Data := new Float_Array (0 .. Stride * 4096 - 1);
      elsif B.Count + Stride > B.Data'Length then
         New_Data := new Float_Array (0 .. B.Data'Length * 2 - 1);
         New_Data (0 .. B.Count - 1) := B.Data (0 .. B.Count - 1);
         Free (B.Data);
         B.Data := New_Data;
      end if;
   end Grow;

   Tilting : Boolean := False;
   Tilt_O, Tilt_F, Tilt_S : V3;
   Tilt_Pitch, Tilt_Roll : Float := 0.0;

   procedure Set_Tilt (Origin, Fwd : V3; Pitch, Roll : Float) is
   begin
      Tilting := abs Pitch > 1.0E-4 or else abs Roll > 1.0E-4;
      Tilt_O := Origin;
      Tilt_F := Fwd;
      Tilt_S := (-Fwd.Z, 0.0, Fwd.X);
      Tilt_Pitch := Pitch;
      Tilt_Roll := Roll;
   end Set_Tilt;

   procedure No_Tilt is
   begin
      Tilting := False;
   end No_Tilt;

   --  V turned by A about the unit axis K (Rodrigues)
   function Turned (V, K : V3; A : Float) return V3 is
     (Cos (A) * V + Sin (A) * Cross (K, V) + ((1.0 - Cos (A)) * Dot (K, V)) * K);

   function Tilted (V : V3) return V3 is (Turned (Turned (V, Tilt_S, Tilt_Pitch), Tilt_F, Tilt_Roll));

   procedure Vertex (B : in out Buffer; P, N : V3; C : Color; Tex : Float := 0.0) is
      Q : V3 := P;
      Pt : V3 := P;
      Nt : V3 := N;
   begin
      Grow (B);
      if Tex > 0.0 and then Pull /= 1.0 then
         Q := Pull_Center + Pull * (P - Pull_Center);
      end if;
      if Tilting then
         Pt := Tilt_O + Tilted (P - Tilt_O);
         Nt := Tilted (N);
      end if;
      B.Data (B.Count .. B.Count + Stride - 1) :=
        (Pt.X, Pt.Y, Pt.Z, Nt.X, Nt.Y, Nt.Z, C.R, C.G, C.B, C.A, Q.X / World_W, Q.Z / World_H, Tex);
      B.Count := B.Count + Stride;
   end Vertex;

   procedure Vertex_UV (B : in out Buffer; P : V3; U, V : Float) is
   begin
      Grow (B);
      B.Data (B.Count .. B.Count + Stride - 1) :=
        (P.X, P.Y, P.Z, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, U, V, 1.0);
      B.Count := B.Count + Stride;
   end Vertex_UV;

   procedure Vertex_Full (B : in out Buffer; P : V3; C : Color; U, V : Float) is
   begin
      Grow (B);
      B.Data (B.Count .. B.Count + Stride - 1) :=
        (P.X, P.Y, P.Z, 0.0, 0.0, 0.0, C.R, C.G, C.B, C.A, U, V, 1.0);
      B.Count := B.Count + Stride;
   end Vertex_Full;

   procedure Tri (B : in out Buffer; P1, P2, P3 : V3; C : Color; Tex : Float := 0.0; Lit : Boolean := True) is
      N : V3 := (0.0, 0.0, 0.0);
   begin
      if Lit then
         N := Normal (Cross (P2 - P1, P3 - P1));
      end if;
      Vertex (B, P1, N, C, Tex);
      Vertex (B, P2, N, C, Tex);
      Vertex (B, P3, N, C, Tex);
   end Tri;

   procedure Quad (B : in out Buffer; P1, P2, P3, P4 : V3; C : Color; Tex : Float := 0.0;
                   Lit : Boolean := True) is
      N : V3 := (0.0, 0.0, 0.0);
   begin
      if Lit then
         N := Normal (Cross (P2 - P1, P3 - P1));
         if Length (N) = 0.0 then
            N := Normal (Cross (P3 - P1, P4 - P1));
         end if;
      end if;
      Vertex (B, P1, N, C, Tex);
      Vertex (B, P2, N, C, Tex);
      Vertex (B, P3, N, C, Tex);
      Vertex (B, P1, N, C, Tex);
      Vertex (B, P3, N, C, Tex);
      Vertex (B, P4, N, C, Tex);
   end Quad;

   procedure Block (B : in out Buffer; O, Fwd : V3; F, U, S, HF, HU, HS : Float; C : Color;
                  Tex : Float := 0.0)
   is
      Side : constant V3 := (-Fwd.Z, 0.0, Fwd.X);
      function P (DF, DU, DS : Float) return V3 is
        (O + (F + DF * HF) * Fwd + (U + DU * HU) * Up + (S + DS * HS) * Side);
   begin
      --  the normals come out right whichever way round: the shader lights both faces alike
      Quad (B, P (-1.0, 1.0, -1.0), P (-1.0, 1.0, 1.0), P (1.0, 1.0, 1.0), P (1.0, 1.0, -1.0), C, Tex);     -- top
      Quad (B, P (-1.0, -1.0, -1.0), P (1.0, -1.0, -1.0), P (1.0, -1.0, 1.0), P (-1.0, -1.0, 1.0), C, Tex); -- bottom
      Quad (B, P (1.0, -1.0, -1.0), P (1.0, 1.0, -1.0), P (1.0, 1.0, 1.0), P (1.0, -1.0, 1.0), C, Tex);     -- front
      Quad (B, P (-1.0, -1.0, -1.0), P (-1.0, -1.0, 1.0), P (-1.0, 1.0, 1.0), P (-1.0, 1.0, -1.0), C, Tex); -- back
      Quad (B, P (-1.0, -1.0, 1.0), P (1.0, -1.0, 1.0), P (1.0, 1.0, 1.0), P (-1.0, 1.0, 1.0), C, Tex);     -- right
      Quad (B, P (-1.0, -1.0, -1.0), P (-1.0, 1.0, -1.0), P (1.0, 1.0, -1.0), P (1.0, -1.0, -1.0), C, Tex); -- left
   end Block;

   function Ring (Center : V3; RX, RZ, Angle, A : Float) return V3 is
      LX : constant Float := RX * Cos (A);
      LZ : constant Float := RZ * Sin (A);
   begin
      return (Center.X + LX * Cos (Angle) - LZ * Sin (Angle), Center.Y,
              Center.Z + LX * Sin (Angle) + LZ * Cos (Angle));
   end Ring;

   procedure Cylinder (B : in out Buffer; Center : V3; RX, RZ, Angle, Y0, Y1 : Float; C : Color;
                       Tex : Float := 0.0; Segments : Positive := 20; Cap : Boolean := True;
                       Taper : Float := 1.0)
   is
      Top : constant V3 := (Center.X, Y1, Center.Z);
      Side_C : constant Color := Shade (C, 0.92);
   begin
      for K in 0 .. Segments - 1 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / Float (Segments);
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / Float (Segments);
            R0 : constant V3 := Ring (Center, RX, RZ, Angle, A0);
            R1 : constant V3 := Ring (Center, RX, RZ, Angle, A1);
            B0 : constant V3 := (R0.X, Y0, R0.Z);
            B1 : constant V3 := (R1.X, Y0, R1.Z);
            T0 : constant V3 := (Center.X + Taper * (R0.X - Center.X), Y1, Center.Z + Taper * (R0.Z - Center.Z));
            T1 : constant V3 := (Center.X + Taper * (R1.X - Center.X), Y1, Center.Z + Taper * (R1.Z - Center.Z));
            Rise : constant Float := (1.0 - Taper) * Float'Max (RX, RZ) / Float'Max (0.01, Y1 - Y0);
            N0 : constant V3 := Normal ((R0.X - Center.X, Rise * Float'Max (RX, RZ), R0.Z - Center.Z));
            N1 : constant V3 := Normal ((R1.X - Center.X, Rise * Float'Max (RX, RZ), R1.Z - Center.Z));
         begin
            Vertex (B, B0, N0, Side_C, Tex);
            Vertex (B, B1, N1, Side_C, Tex);
            Vertex (B, T1, N1, Side_C, Tex);
            Vertex (B, B0, N0, Side_C, Tex);
            Vertex (B, T1, N1, Side_C, Tex);
            Vertex (B, T0, N0, Side_C, Tex);
            if Cap then
               declare
                  Saved : constant Float := Pull;
               begin
                  Pull := 1.0;
                  Vertex (B, Top, Up, C, Tex);
                  Vertex (B, T0, Up, C, Tex);
                  Vertex (B, T1, Up, C, Tex);
                  Pull := Saved;
               end;
            end if;
         end;
      end loop;
   end Cylinder;

   procedure Barrel (B : in out Buffer; Center, Fwd : V3; R, Half_Length : Float; C : Color;
                     Segments : Positive := 12)
   is
      Side : constant V3 := (-Fwd.Z, 0.0, Fwd.X);
      function P (A, L : Float) return V3 is
        (Center + L * Fwd + (R * Cos (A)) * Side + (R * Sin (A)) * Up);
      function N (A : Float) return V3 is (Cos (A) * Side + Sin (A) * Up);
   begin
      for K in 0 .. Segments - 1 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / Float (Segments);
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / Float (Segments);
         begin
            Vertex (B, P (A0, -Half_Length), N (A0), C);
            Vertex (B, P (A1, -Half_Length), N (A1), C);
            Vertex (B, P (A1, Half_Length), N (A1), C);
            Vertex (B, P (A0, -Half_Length), N (A0), C);
            Vertex (B, P (A1, Half_Length), N (A1), C);
            Vertex (B, P (A0, Half_Length), N (A0), C);
            Tri (B, Center + Half_Length * Fwd, P (A0, Half_Length), P (A1, Half_Length), C);
            Tri (B, Center - Half_Length * Fwd, P (A1, -Half_Length), P (A0, -Half_Length), C);
         end;
      end loop;
   end Barrel;

   procedure Dome (B : in out Buffer; Center : V3; RX, RZ, Angle, H : Float; C : Color;
                   Tex : Float := 0.0; Segments : Positive := 20)
   is
      Rings : constant := 6;
      function P (K, J : Natural) return V3 is
         Lat : constant Float := Pi / 2.0 * Float (J) / Float (Rings);
         R   : constant V3 := Ring (Center, RX * Cos (Lat), RZ * Cos (Lat), Angle,
                                    2.0 * Pi * Float (K) / Float (Segments));
      begin
         return (R.X, Center.Y + H * Sin (Lat), R.Z);
      end P;
      function N (K, J : Natural) return V3 is
         Q : constant V3 := P (K, J) - Center;
      begin
         --  the normal of an ellipsoid: the place divided by the square of the radii
         return Normal ((Q.X / (RX * RX), Q.Y / (H * H), Q.Z / (RZ * RZ)));
      end N;
   begin
      for J in 0 .. Rings - 1 loop
         for K in 0 .. Segments - 1 loop
            Vertex (B, P (K, J), N (K, J), C, Tex);
            Vertex (B, P (K + 1, J), N (K + 1, J), C, Tex);
            Vertex (B, P (K + 1, J + 1), N (K + 1, J + 1), C, Tex);
            Vertex (B, P (K, J), N (K, J), C, Tex);
            Vertex (B, P (K + 1, J + 1), N (K + 1, J + 1), C, Tex);
            Vertex (B, P (K, J + 1), N (K, J + 1), C, Tex);
         end loop;
      end loop;
   end Dome;

   procedure Lathe (B : in out Buffer; Center : V3; P : Profile; Scale_R, Scale_Y : Float; C : Color;
                    Tex : Float := 0.0; Segments : Positive := 20)
   is
      function Pt (J : Positive; A : Float) return V3 is
        (Center.X + P (J).R * Scale_R * Cos (A), Center.Y + P (J).Y * Scale_Y, Center.Z + P (J).R * Scale_R * Sin (A));
   begin
      for J in P'First .. P'Last - 1 loop
         declare
            DR : constant Float := (P (J + 1).R - P (J).R) * Scale_R;
            DY : constant Float := (P (J + 1).Y - P (J).Y) * Scale_Y;
            L  : constant Float := Sqrt (DR * DR + DY * DY);
            NR : constant Float := (if L > 0.0 then DY / L else 0.0);   --  outwards
            NY : constant Float := (if L > 0.0 then -DR / L else 1.0);  --  upwards
         begin
            if L > 0.0 then
               for K in 0 .. Segments - 1 loop
                  declare
                     A0 : constant Float := 2.0 * Pi * Float (K) / Float (Segments);
                     A1 : constant Float := 2.0 * Pi * Float (K + 1) / Float (Segments);
                     N0 : constant V3 := (NR * Cos (A0), NY, NR * Sin (A0));
                     N1 : constant V3 := (NR * Cos (A1), NY, NR * Sin (A1));
                  begin
                     Vertex (B, Pt (J, A0), N0, C, Tex);
                     Vertex (B, Pt (J, A1), N1, C, Tex);
                     Vertex (B, Pt (J + 1, A1), N1, C, Tex);
                     Vertex (B, Pt (J, A0), N0, C, Tex);
                     Vertex (B, Pt (J + 1, A1), N1, C, Tex);
                     Vertex (B, Pt (J + 1, A0), N0, C, Tex);
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Lathe;

   procedure Sphere (B : in out Buffer; Center : V3; R : Float; C : Color; Segments : Positive := 12) is
      Rings : constant Positive := Segments / 2;
      function N (K, J : Natural) return V3 is
         Lat : constant Float := -Pi / 2.0 + Pi * Float (J) / Float (Rings);
         Lon : constant Float := 2.0 * Pi * Float (K) / Float (Segments);
      begin
         return (Cos (Lat) * Cos (Lon), Sin (Lat), Cos (Lat) * Sin (Lon));
      end N;
   begin
      for J in 0 .. Rings - 1 loop
         for K in 0 .. Segments - 1 loop
            Vertex (B, Center + R * N (K, J), N (K, J), C);
            Vertex (B, Center + R * N (K + 1, J), N (K + 1, J), C);
            Vertex (B, Center + R * N (K + 1, J + 1), N (K + 1, J + 1), C);
            Vertex (B, Center + R * N (K, J), N (K, J), C);
            Vertex (B, Center + R * N (K + 1, J + 1), N (K + 1, J + 1), C);
            Vertex (B, Center + R * N (K, J + 1), N (K, J + 1), C);
         end loop;
      end loop;
   end Sphere;

   procedure Disc (B : in out Buffer; Center : V3; RX, RZ, Angle : Float; C : Color;
                   Segments : Positive := 16)
   is
      Edge : constant Color := (C.R, C.G, C.B, 0.0);
      Zero : constant V3 := (0.0, 0.0, 0.0);
   begin
      for K in 0 .. Segments - 1 loop
         Vertex (B, Center, Zero, C);
         Vertex (B, Ring (Center, RX, RZ, Angle, 2.0 * Pi * Float (K) / Float (Segments)), Zero, Edge);
         Vertex (B, Ring (Center, RX, RZ, Angle, 2.0 * Pi * Float (K + 1) / Float (Segments)), Zero, Edge);
      end loop;
   end Disc;

   procedure Upload (B : in out Buffer; Static : Boolean) is
      use GL;
      Bytes : constant := Float'Size / 8;
      function Off (N : Natural) return System.Address is (To_Address (Integer_Address (N * Bytes)));
   begin
      if B.Vao = 0 then
         Gen_Vertex_Arrays (1, B.Vao'Access);
         Gen_Buffers (1, B.Vbo'Access);
         Bind_Vertex_Array (B.Vao);
         Bind_Buffer (GL_ARRAY_BUFFER, B.Vbo);
         Vertex_Attrib_Pointer (0, 3, GL_FLOAT, GL_FALSE, Stride * Bytes, Off (0));
         Vertex_Attrib_Pointer (1, 3, GL_FLOAT, GL_FALSE, Stride * Bytes, Off (3));
         Vertex_Attrib_Pointer (2, 4, GL_FLOAT, GL_FALSE, Stride * Bytes, Off (6));
         Vertex_Attrib_Pointer (3, 2, GL_FLOAT, GL_FALSE, Stride * Bytes, Off (10));
         Vertex_Attrib_Pointer (4, 1, GL_FLOAT, GL_FALSE, Stride * Bytes, Off (12));
         for I in GLuint range 0 .. 4 loop
            Enable_Vertex_Attrib_Array (I);
         end loop;
      else
         Bind_Vertex_Array (B.Vao);
         Bind_Buffer (GL_ARRAY_BUFFER, B.Vbo);
      end if;
      if B.Count > 0 then
         Buffer_Data (GL_ARRAY_BUFFER, GLsizeiptr (B.Count * Bytes), B.Data.all'Address,
                      (if Static then GL_STATIC_DRAW else GL_STREAM_DRAW));
      end if;
      B.Drawn := B.Count / Stride;
      Bind_Vertex_Array (0);
   end Upload;

   procedure Draw (B : Buffer) is
      use GL;
   begin
      if B.Drawn > 0 then
         Bind_Vertex_Array (B.Vao);
         Draw_Arrays (GL_TRIANGLES, 0, GLsizei (B.Drawn));
         Bind_Vertex_Array (0);
      end if;
   end Draw;

   procedure Draw_Range (B : Buffer; First, Count : Natural) is
      use GL;
      N : constant Integer := Integer'Min (Count, B.Drawn - First);
   begin
      if N > 0 then
         Bind_Vertex_Array (B.Vao);
         Draw_Arrays (GL_TRIANGLES, GLint (First), GLsizei (N));
         Bind_Vertex_Array (0);
      end if;
   end Draw_Range;

end Mesh;
