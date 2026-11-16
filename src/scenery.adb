--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Art;
with Geom;
with Lin; use Lin;
with Tracks; use Tracks;

package body Scenery is

   use Mesh;

   Pi : constant := Geom.Pi;
   Table_Drop : constant := 260.0;   --  from a table top to the floor
   Room_H : constant := 1050.0;      --  from the floor to the ceiling

   White : constant Color := (1.0, 1.0, 1.0, 1.0);
   Wood  : constant Color := (0.55, 0.38, 0.22, 1.0);
   Dark_Wood : constant Color := (0.36, 0.24, 0.14, 1.0);

   Rand : Geom.Seed := 1;
   function Rnd return Float is (Geom.Random (Rand));
   function Spr return Float is (Geom.Spread (Rand));

   W, H : Float := 1000.0;   --  the world of the track loaded

   type Place_Kind is (Room, Tabletop, Bench, Bathtub, Outside, Night_Out, Space, Tank);

   function Place return Place_Kind is
     (case Theme is
         when Workbench => Bench,
         when Pool | Desk | Chess | Party | Toy_Town => Tabletop,
         when Bath => Bathtub,
         when Kitchen | Bedroom | Garage | Xmas | Attic => Room,
         when Garden | Easter | Mud | Beach | Ice | Arctic | Sky => Outside,
         when Halloween => Night_Out,
         when Moon | Alien => Space,
         when Fish_Tank => Tank);

   function Indoors return Boolean is (Place in Room | Tabletop | Bench | Bathtub | Tank);

   function Floor_Y (Ground_Y : Float) return Float is
     (case Place is
         when Tabletop | Bench | Bathtub => Ground_Y - Table_Drop,
         when Tank => Ground_Y - 400.0,
         when others => Ground_Y);

   ---------------------------------------------------------------------------
   --  The sky: not lit, not in the fog
   ---------------------------------------------------------------------------

   Sky_Radius : constant := 9000.0;
   Middle : V3;

   procedure Sky_Vertex (B : in out Buffer; P : V3; C : Color) is
   begin
      Vertex (B, P, (0.0, 0.0, 0.0), C, -1.0);
   end Sky_Vertex;

   procedure Sky_Tri (B : in out Buffer; P1, P2, P3 : V3; C1, C2, C3 : Color) is
   begin
      Sky_Vertex (B, P1, C1);
      Sky_Vertex (B, P2, C2);
      Sky_Vertex (B, P3, C3);
   end Sky_Tri;

   function Mixed (A, B : Color; T : Float) return Color is
     (A.R + (B.R - A.R) * T, A.G + (B.G - A.G) * T, A.B + (B.B - A.B) * T, 1.0);

   procedure Sky_Dome (B : in out Buffer; Top, Horizon : Color; Base_Y : Float) is
      Rings : constant := 10;
      Segs : constant := 32;
      function P (K, J : Integer) return V3 is
         Lat : constant Float := (if J < 0 then -0.25 else Pi / 2.0 * Float (J) / Float (Rings));
         Lon : constant Float := 2.0 * Pi * Float (K) / Float (Segs);
      begin
         return (Middle.X + Sky_Radius * Cos (Lat) * Cos (Lon), Base_Y + Sky_Radius * Sin (Lat),
                 Middle.Z + Sky_Radius * Cos (Lat) * Sin (Lon));
      end P;
      function C (J : Integer) return Color is
        (if J <= 0 then Horizon else Mixed (Horizon, Top, Sqrt (Float (J) / Float (Rings))));
   begin
      for J in -1 .. Rings - 1 loop
         for K in 0 .. Segs - 1 loop
            Sky_Tri (B, P (K, J), P (K + 1, J), P (K + 1, J + 1), C (J), C (J), C (J + 1));
            Sky_Tri (B, P (K, J), P (K + 1, J + 1), P (K, J + 1), C (J), C (J + 1), C (J + 1));
         end loop;
      end loop;
   end Sky_Dome;

   --  A flat round thing in the sky, turned to the middle of the world
   procedure Sky_Disc (B : in out Buffer; Center : V3; R : Float; C, Edge : Color) is
      D : constant V3 := Normal (Middle - Center);
      Right : constant V3 := Normal (Cross (D, Up));
      Upv : constant V3 := Cross (Right, D);
      N : constant := 28;
   begin
      for K in 0 .. N - 1 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / Float (N);
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / Float (N);
         begin
            Sky_Tri (B, Center, Center + (R * Cos (A0)) * Right + (R * Sin (A0)) * Upv,
                     Center + (R * Cos (A1)) * Right + (R * Sin (A1)) * Upv, C, Edge, Edge);
         end;
      end loop;
   end Sky_Disc;

   --  A ball in the sky, its colour by where its skin faces: a planet, a cloud
   type Shade_Fn is access function (N : V3) return Color;
   procedure Sky_Ball (B : in out Buffer; Center : V3; RX, RY, RZ : Float; Shade_Of : Shade_Fn) is
      Rings : constant := 10;
      Segs : constant := 20;
      function N (K, J : Integer) return V3 is
         Lat : constant Float := -Pi / 2.0 + Pi * Float (J) / Float (Rings);
         Lon : constant Float := 2.0 * Pi * Float (K) / Float (Segs);
      begin
         return (Cos (Lat) * Cos (Lon), Sin (Lat), Cos (Lat) * Sin (Lon));
      end N;
      function P (K, J : Integer) return V3 is
        (Center + (RX * N (K, J).X, RY * N (K, J).Y, RZ * N (K, J).Z));
   begin
      for J in 0 .. Rings - 1 loop
         for K in 0 .. Segs - 1 loop
            Sky_Tri (B, P (K, J), P (K + 1, J), P (K + 1, J + 1),
                     Shade_Of (N (K, J)), Shade_Of (N (K + 1, J)), Shade_Of (N (K + 1, J + 1)));
            Sky_Tri (B, P (K, J), P (K + 1, J + 1), P (K, J + 1),
                     Shade_Of (N (K, J)), Shade_Of (N (K + 1, J + 1)), Shade_Of (N (K, J + 1)));
         end loop;
      end loop;
   end Sky_Ball;

   function Cloud_Shade (N : V3) return Color is
     (Mixed ((0.78, 0.80, 0.86, 1.0), (1.0, 1.0, 1.0, 1.0), 0.5 + 0.5 * N.Y));

   function Night_Cloud_Shade (N : V3) return Color is
     (Mixed ((0.10, 0.08, 0.16, 1.0), (0.25, 0.22, 0.32, 1.0), 0.5 + 0.5 * N.Y));

   function Earth_Shade (N : V3) return Color is
      --  seas, land and clouds, after a fashion; the side away from the sun dark
      Land : constant Float := Sin (N.X * 5.0 + 1.3) * Sin (N.Z * 4.0) + 0.4 * Sin (N.Y * 7.0);
      Cloud : constant Float := Sin (N.X * 11.0 + N.Y * 7.0) * Sin (N.Z * 9.0);
      Lit : constant Float := Geom.Clamp (0.25 + 0.9 * (0.6 * N.X + 0.5 * N.Y - 0.6 * N.Z), 0.08, 1.0);
      Base : constant Color :=
        (if Cloud > 0.55 then (0.95, 0.95, 0.97, 1.0)
         elsif Land > 0.35 then (0.25, 0.55, 0.22, 1.0)
         else (0.12, 0.30, 0.72, 1.0));
   begin
      return (Base.R * Lit, Base.G * Lit, Base.B * Lit, 1.0);
   end Earth_Shade;

   procedure Clouds (B : in out Buffer; Count : Natural; Low, High_Y : Float; Night : Boolean := False) is
   begin
      for K in 1 .. Count loop
         declare
            A : constant Float := 2.0 * Pi * Rnd;
            D : constant Float := Sky_Radius * (0.55 + 0.3 * Rnd);
            C : constant V3 := (Middle.X + D * Cos (A), Low + (High_Y - Low) * Rnd, Middle.Z + D * Sin (A));
            Size : constant Float := 300.0 + 500.0 * Rnd;
         begin
            for P in 1 .. 4 loop
               Sky_Ball (B, C + (Spr * Size, Rnd * Size * 0.3, Spr * Size * 0.5),
                         Size * (0.6 + 0.5 * Rnd), Size * (0.35 + 0.2 * Rnd), Size * (0.6 + 0.5 * Rnd),
                         (if Night then Night_Cloud_Shade'Access else Cloud_Shade'Access));
            end loop;
         end;
      end loop;
   end Clouds;

   procedure Stars (B : in out Buffer; Count : Natural; Base_Y : Float) is
   begin
      for K in 1 .. Count loop
         declare
            Lon : constant Float := 2.0 * Pi * Rnd;
            Lat : constant Float := Arcsin (0.05 + 0.95 * Rnd);
            R : constant Float := Sky_Radius * 0.97;
            P : constant V3 := (Middle.X + R * Cos (Lat) * Cos (Lon), Base_Y + R * Sin (Lat),
                                Middle.Z + R * Cos (Lat) * Sin (Lon));
            Br : constant Float := 0.5 + 0.5 * Rnd;
         begin
            Sky_Disc (B, P, 8.0 + 14.0 * Rnd, (Br, Br, Br * (0.9 + 0.1 * Rnd), 1.0), (Br, Br, Br, 1.0));
         end;
      end loop;
   end Stars;

   ---------------------------------------------------------------------------
   --  Things on the ground far off
   ---------------------------------------------------------------------------

   --  A spot round the world, Near to Far beyond its edge
   function Around (Near, Far : Float) return V3 is
      A : constant Float := 2.0 * Pi * Rnd;
      D : constant Float := Near + (Far - Near) * Rnd;
      E : constant Float := Float'Max (W, H) * 0.5;
   begin
      return (Middle.X + (E + D) * Cos (A) * (W / Float'Max (W, H)), 0.0,
              Middle.Z + (E + D) * Sin (A) * (H / Float'Max (W, H)) + D * 0.4 * Sin (A));
   end Around;

   function At_Y (P : V3; Y : Float) return V3 is ((P.X, Y, P.Z));

   procedure Leafy_Tree (B : in out Buffer; Base : V3; Size : Float; Leaf : Color) is
   begin
      Cylinder (B, Base, Size * 0.08, Size * 0.08, 0.0, Base.Y, Base.Y + Size * 0.6, Dark_Wood, 0.0, 8);
      for K in 1 .. 3 loop
         Sphere (B, Base + (Spr * Size * 0.15, Size * (0.65 + 0.12 * Float (K)), Spr * Size * 0.15),
                 Size * (0.42 - 0.06 * Float (K)), Shade (Leaf, 0.85 + 0.1 * Float (K)), 10);
      end loop;
   end Leafy_Tree;

   procedure Fir (B : in out Buffer; Base : V3; Size : Float; Green : Color; Snow : Boolean) is
   begin
      Cylinder (B, Base, Size * 0.05, Size * 0.05, 0.0, Base.Y, Base.Y + Size * 0.2, Dark_Wood, 0.0, 6);
      for K in 0 .. 2 loop
         declare
            Y0 : constant Float := Base.Y + Size * (0.15 + 0.25 * Float (K));
            R : constant Float := Size * (0.32 - 0.07 * Float (K));
         begin
            Cylinder (B, At_Y (Base, Y0), R, R, 0.0, Y0, Y0 + Size * 0.4, Green, 0.0, 10, Cap => False, Taper => 0.0);
            if Snow then
               Cylinder (B, At_Y (Base, Y0 + Size * 0.24), R * 0.42, R * 0.42, 0.0, Y0 + Size * 0.24, Y0 + Size * 0.41,
                         (0.95, 0.96, 1.0, 1.0), 0.0, 10, Cap => False, Taper => 0.0);
            end if;
         end;
      end loop;
   end Fir;

   procedure Hills (B : in out Buffer; Count : Natural; Near, Far, Size, Y : Float; C : Color) is
   begin
      for K in 1 .. Count loop
         declare
            P : constant V3 := At_Y (Around (Near, Far), Y);
            R : constant Float := Size * (0.6 + 0.8 * Rnd);
         begin
            Dome (B, P, R, R * (0.6 + 0.6 * Rnd), 2.0 * Pi * Rnd, R * (0.25 + 0.25 * Rnd),
                  Shade (C, 0.85 + 0.25 * Rnd), 0.0, 18);
         end;
      end loop;
   end Hills;

   procedure Mountains (B : in out Buffer; Count : Natural; Near, Far, Y : Float; Rock, Cap : Color) is
   begin
      for K in 1 .. Count loop
         declare
            P : constant V3 := At_Y (Around (Near, Far), Y);
            R : constant Float := 900.0 + 900.0 * Rnd;
            Ht : constant Float := R * (0.7 + 0.6 * Rnd);
         begin
            Cylinder (B, P, R, R, 0.0, Y, Y + Ht, Shade (Rock, 0.85 + 0.25 * Rnd), 0.0, 12, Cap => False, Taper => 0.0);
            Cylinder (B, At_Y (P, Y + Ht * 0.62), R * 0.385, R * 0.385, 0.0, Y + Ht * 0.62, Y + Ht + 2.0, Cap,
                      0.0, 12, Cap => False, Taper => 0.0);
         end;
      end loop;
   end Mountains;

   ---------------------------------------------------------------------------
   --  Rooms
   ---------------------------------------------------------------------------

   type Room_Box is record
      X0, X1, Z0, Z1, Fy : Float;   --  the walls, and the floor
   end record;

   function Flat (A : Float) return V3 is ((Cos (A), 0.0, Sin (A)));

   --  A window in the far wall (Z0), with the sky behind it
   procedure North_Window (B : in out Buffer; R : Room_Box; X_Mid, Half : Float; Top, Low, Frame : Color) is
      Z : constant Float := R.Z0 + 1.0;
      Y0 : constant Float := R.Fy + 380.0;
      Y1 : constant Float := R.Fy + 860.0;
   begin
      Sky_Vertex (B, (X_Mid - Half, Y0, Z), Low);
      Sky_Vertex (B, (X_Mid + Half, Y0, Z), Low);
      Sky_Vertex (B, (X_Mid + Half, Y1, Z), Top);
      Sky_Vertex (B, (X_Mid - Half, Y0, Z), Low);
      Sky_Vertex (B, (X_Mid + Half, Y1, Z), Top);
      Sky_Vertex (B, (X_Mid - Half, Y1, Z), Top);
      --  the frame, the bars across, and the sill
      Block (B, (X_Mid, Y0 - 6.0, Z + 6.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, Half + 24.0, 10.0, 18.0, Frame);
      Block (B, (X_Mid, Y1 + 6.0, Z + 6.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, Half + 20.0, 10.0, 8.0, Frame);
      Block (B, (X_Mid - Half - 8.0, (Y0 + Y1) / 2.0, Z + 6.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 10.0, (Y1 - Y0) / 2.0,
             8.0, Frame);
      Block (B, (X_Mid + Half + 8.0, (Y0 + Y1) / 2.0, Z + 6.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 10.0, (Y1 - Y0) / 2.0,
             8.0, Frame);
      Block (B, (X_Mid, (Y0 + Y1) / 2.0, Z + 5.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 6.0, (Y1 - Y0) / 2.0, 5.0, Frame);
      Block (B, (X_Mid, Y0 + (Y1 - Y0) * 0.6, Z + 5.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, Half, 6.0, 5.0, Frame);
   end North_Window;

   procedure West_Door (B : in out Buffer; R : Room_Box; Z_Mid : Float; Door : Color) is
      X : constant Float := R.X0 + 4.0;
   begin
      Block (B, (X, R.Fy + 400.0, Z_Mid), (0.0, 0.0, 1.0), 0.0, 0.0, 0.0, 180.0, 400.0, 4.0, Door);
      Block (B, (X, R.Fy + 405.0, Z_Mid), (0.0, 0.0, 1.0), 0.0, 0.0, 0.0, 196.0, 410.0, 2.0, White);
      for K in 0 .. 1 loop   --  panels
         Block (B, (X + 4.0, R.Fy + 200.0 + 400.0 * Float (K), Z_Mid), (0.0, 0.0, 1.0), 0.0, 0.0, 0.0, 130.0, 150.0,
                3.0, Shade (Door, 0.9));
      end loop;
      Sphere (B, (X + 14.0, R.Fy + 380.0, Z_Mid + 140.0), 10.0, (0.85, 0.75, 0.35, 1.0), 8);
   end West_Door;

   procedure Room (B : in out Buffer; R : Room_Box; Wall, Skirting, Ceiling : Color) is
      T : constant Float := R.Fy + Room_H;
      Cx : constant Float := (R.X0 + R.X1) / 2.0;
      Cz : constant Float := (R.Z0 + R.Z1) / 2.0;
   begin
      Quad (B, (R.X0, R.Fy, R.Z0), (R.X1, R.Fy, R.Z0), (R.X1, T, R.Z0), (R.X0, T, R.Z0), Wall);
      Quad (B, (R.X0, R.Fy, R.Z1), (R.X1, R.Fy, R.Z1), (R.X1, T, R.Z1), (R.X0, T, R.Z1), Shade (Wall, 0.95));
      Quad (B, (R.X0, R.Fy, R.Z0), (R.X0, R.Fy, R.Z1), (R.X0, T, R.Z1), (R.X0, T, R.Z0), Shade (Wall, 0.92));
      Quad (B, (R.X1, R.Fy, R.Z0), (R.X1, R.Fy, R.Z1), (R.X1, T, R.Z1), (R.X1, T, R.Z0), Shade (Wall, 0.97));
      Quad (B, (R.X0, T, R.Z0), (R.X1, T, R.Z0), (R.X1, T, R.Z1), (R.X0, T, R.Z1), Ceiling);
      --  the skirting boards
      Block (B, (Cx, R.Fy + 18.0, R.Z0 + 5.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, (R.X1 - R.X0) / 2.0, 18.0, 5.0, Skirting);
      Block (B, (Cx, R.Fy + 18.0, R.Z1 - 5.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, (R.X1 - R.X0) / 2.0, 18.0, 5.0, Skirting);
      Block (B, (R.X0 + 5.0, R.Fy + 18.0, Cz), (0.0, 0.0, 1.0), 0.0, 0.0, 0.0, (R.Z1 - R.Z0) / 2.0, 18.0, 5.0, Skirting);
      Block (B, (R.X1 - 5.0, R.Fy + 18.0, Cz), (0.0, 0.0, 1.0), 0.0, 0.0, 0.0, (R.Z1 - R.Z0) / 2.0, 18.0, 5.0, Skirting);
      --  a lamp under the ceiling
      Cylinder (B, (Cx, T - 60.0, Cz), 3.0, 3.0, 0.0, T - 160.0, T, (0.2, 0.2, 0.2, 1.0), 0.0, 6);
      Cylinder (B, (Cx, T - 230.0, Cz), 110.0, 110.0, 0.0, T - 230.0, T - 160.0, (0.95, 0.9, 0.75, 1.0), 0.0, 20,
                Cap => False, Taper => 0.45);
      Sphere (B, (Cx, T - 215.0, Cz), 35.0, (1.0, 0.97, 0.85, 1.0), 10);
   end Room;

   --  A table: its top at Top, its legs to the floor
   procedure Table (B : in out Buffer; X0, X1, Z0, Z1, Top, Floor_Level, Thick : Float; Top_C, Leg_C : Color;
                    Legs_In : Float := 40.0) is
   begin
      Block (B, ((X0 + X1) / 2.0, Top - Thick / 2.0, (Z0 + Z1) / 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0,
             (X1 - X0) / 2.0, Thick / 2.0, (Z1 - Z0) / 2.0, Top_C);
      for K in 0 .. 3 loop
         declare
            X : constant Float := (if K mod 2 = 0 then X0 + Legs_In else X1 - Legs_In);
            Z : constant Float := (if K < 2 then Z0 + Legs_In else Z1 - Legs_In);
         begin
            Block (B, (X, (Top - Thick + Floor_Level) / 2.0, Z), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 16.0,
                   (Top - Thick - Floor_Level) / 2.0, 16.0, Leg_C);
         end;
      end loop;
   end Table;

   procedure Chair (B : in out Buffer; X, Z, Floor_Level, A : Float; C : Color) is
      F : constant V3 := Flat (A);
      O : constant V3 := (X, Floor_Level, Z);
   begin
      Block (B, O, F, 0.0, 180.0, 0.0, 170.0, 10.0, 170.0, C);
      for K in 0 .. 3 loop
         Block (B, O, F, (if K mod 2 = 0 then -150.0 else 150.0), 90.0, (if K < 2 then -150.0 else 150.0),
                11.0, 90.0, 11.0, Shade (C, 0.8));
      end loop;
      Block (B, O, F, -160.0, 380.0, 0.0, 10.0, 200.0, 170.0, C);
   end Chair;

   procedure Shelves (B : in out Buffer; X_Mid, Z, Floor_Level, Width : Float; Wood_C : Color; Toward : Float) is
   begin
      for Level in 0 .. 3 loop
         declare
            Y : constant Float := Floor_Level + 120.0 + 220.0 * Float (Level);
            X : Float := X_Mid - Width / 2.0 + 20.0;
         begin
            Block (B, (X_Mid, Y, Z), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, Width / 2.0, 6.0, 70.0, Wood_C);
            while X < X_Mid + Width / 2.0 - 40.0 loop
               declare
                  Bw : constant Float := 10.0 + 14.0 * Rnd;
                  Bh : constant Float := 110.0 + 70.0 * Rnd;
                  Hue : constant Float := 6.0 * Rnd;
               begin
                  Block (B, (X + Bw, Y + 6.0 + Bh / 2.0, Z + Toward * 6.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0,
                         Bw, Bh / 2.0, 55.0,
                         (0.45 + 0.35 * Sin (Hue), 0.35 + 0.3 * Sin (Hue + 2.0), 0.3 + 0.3 * Sin (Hue + 4.0), 1.0));
                  X := X + 2.0 * Bw + 2.0;
               end;
            end loop;
         end;
      end loop;
      Block (B, (X_Mid - Width / 2.0, Floor_Level + 450.0, Z), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 8.0, 450.0, 72.0, Wood_C);
      Block (B, (X_Mid + Width / 2.0, Floor_Level + 450.0, Z), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 8.0, 450.0, 72.0, Wood_C);
   end Shelves;

   --  The furniture each room has round the track
   procedure Furnish (B : in out Buffer; R : Room_Box) is
      Fy : constant Float := R.Fy;
      Cx : constant Float := (R.X0 + R.X1) / 2.0;
      Cz : constant Float := (R.Z0 + R.Z1) / 2.0;
   begin
      case Theme is
         when Kitchen =>
            --  cupboards and a worktop along the far wall, a fridge, a table with chairs
            declare
               Unit : constant Color := (0.85, 0.82, 0.74, 1.0);
               X : Float := R.X0 + 200.0;
            begin
               Block (B, (Cx, Fy + 180.0, R.Z0 + 125.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, (R.X1 - R.X0) / 2.0 - 400.0,
                      180.0, 120.0, Unit);
               Block (B, (Cx, Fy + 372.0, R.Z0 + 130.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, (R.X1 - R.X0) / 2.0 - 390.0,
                      12.0, 130.0, (0.35, 0.32, 0.30, 1.0));
               Block (B, (Cx, Fy + 780.0, R.Z0 + 70.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, (R.X1 - R.X0) / 2.0 - 400.0,
                      150.0, 70.0, Unit);
               while X < R.X1 - 300.0 loop
                  Block (B, (X + 100.0, Fy + 180.0, R.Z0 + 247.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 92.0, 160.0, 2.0,
                         Shade (Unit, 0.92));
                  Sphere (B, (X + 170.0, Fy + 300.0, R.Z0 + 252.0), 7.0, (0.6, 0.6, 0.62, 1.0), 6);
                  X := X + 200.0;
               end loop;
               Block (B, (R.X1 - 160.0, Fy + 450.0, R.Z0 + 140.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 140.0, 450.0, 130.0,
                      (0.94, 0.94, 0.96, 1.0));
               Table (B, R.X1 - 900.0, R.X1 - 150.0, Cz - 300.0, Cz + 300.0, Fy + 300.0, Fy, 16.0, Wood, Dark_Wood);
               Chair (B, R.X1 - 1050.0, Cz, Fy, 0.0, Wood);
            end;
         when Bedroom =>
            --  a bed, a wardrobe, a poster
            Block (B, (R.X1 - 300.0, Fy + 110.0, Cz), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 280.0, 60.0, 420.0, Wood);
            Block (B, (R.X1 - 300.0, Fy + 200.0, Cz + 60.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 275.0, 40.0, 340.0,
                   (0.35, 0.5, 0.85, 1.0));
            Block (B, (R.X1 - 300.0, Fy + 190.0, Cz - 340.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 230.0, 35.0, 60.0, White);
            Block (B, (R.X1 - 10.0, Fy + 300.0, Cz), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 12.0, 300.0, 430.0, Dark_Wood);
            Block (B, (R.X0 + 160.0, Fy + 480.0, R.Z1 - 300.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 140.0, 480.0, 250.0,
                   Wood);
            Block (B, (Cx + 400.0, Fy + 620.0, R.Z0 + 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 160.0, 220.0, 2.0,
                   (0.9, 0.5, 0.2, 1.0));
         when Garage =>
            --  a roller door, shelves of tins and boxes
            for K in 0 .. 30 loop
               Block (B, (Cx, Fy + 15.0 + 26.0 * Float (K), R.Z1 - 6.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 700.0, 11.0, 6.0,
                      (0.62, 0.63, 0.66, 1.0));
            end loop;
            Shelves (B, Cx - 400.0, R.Z0 + 80.0, Fy, 1200.0, (0.45, 0.45, 0.48, 1.0), 1.0);
            Shelves (B, Cx + 1000.0, R.Z0 + 80.0, Fy, 900.0, (0.45, 0.45, 0.48, 1.0), 1.0);
         when Xmas =>
            --  a fireplace with a fire, and stockings
            Block (B, (Cx, Fy + 300.0, R.Z0 + 60.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 420.0, 300.0, 60.0,
                   (0.62, 0.30, 0.22, 1.0));
            Block (B, (Cx, Fy + 610.0, R.Z0 + 80.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 470.0, 14.0, 80.0, White);
            Block (B, (Cx, Fy + 170.0, R.Z0 + 121.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 220.0, 170.0, 1.0,
                   (0.06, 0.04, 0.04, 1.0));
            for K in 0 .. 5 loop
               Quad (B, (Cx - 150.0 + 60.0 * Float (K), Fy + 20.0, R.Z0 + 110.0),
                     (Cx - 110.0 + 60.0 * Float (K), Fy + 20.0, R.Z0 + 110.0),
                     (Cx - 130.0 + 60.0 * Float (K), Fy + 120.0 + 60.0 * Rnd, R.Z0 + 110.0),
                     (Cx - 130.0 + 60.0 * Float (K), Fy + 120.0, R.Z0 + 110.0),
                     (1.0, 0.55 + 0.3 * Rnd, 0.15, 1.0), Lit => False);
            end loop;
            for K in 0 .. 3 loop
               Block (B, (Cx - 300.0 + 200.0 * Float (K), Fy + 520.0, R.Z0 + 165.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0,
                      28.0, 60.0, 8.0, (if K mod 2 = 0 then (0.85, 0.1, 0.1, 1.0) else (0.1, 0.6, 0.2, 1.0)));
            end loop;
         when Attic =>
            --  old trunks and boxes along the walls
            for K in 0 .. 6 loop
               declare
                  P : constant V3 := (R.X0 + 300.0 + (R.X1 - R.X0 - 600.0) * Rnd, Fy,
                                      (if K mod 2 = 0 then R.Z0 + 150.0 else R.Z1 - 150.0));
                  S : constant Float := 60.0 + 80.0 * Rnd;
               begin
                  Block (B, P, Flat (Spr * 0.3), 0.0, S, 0.0, S * 1.3, S, S, Shade ((0.5, 0.4, 0.28, 1.0), 0.7 + 0.4 * Rnd));
               end;
            end loop;
         when Pool =>
            --  a dartboard, a lamp over the table
            for K in 0 .. 3 loop
               Block (B, (Cx + 600.0, Fy + 600.0, R.Z0 + 4.0 + Float (K)), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0,
                      90.0 - 20.0 * Float (K), 90.0 - 20.0 * Float (K), 1.0,
                      (if K mod 2 = 0 then (0.1, 0.1, 0.1, 1.0) else (0.85, 0.15, 0.1, 1.0)));
            end loop;
            Block (B, (Cx, Fy + Room_H - 280.0, Cz), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 700.0, 30.0, 120.0,
                   (0.1, 0.35, 0.15, 1.0));
         when Desk =>
            --  a blackboard and other desks
            Block (B, (Cx, Fy + 600.0, R.Z0 + 4.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 900.0, 240.0, 4.0,
                   (0.12, 0.22, 0.15, 1.0));
            Block (B, (Cx, Fy + 600.0, R.Z0 + 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 930.0, 270.0, 2.0, Wood);
            for K in 0 .. 1 loop
               Table (B, R.X0 + 120.0, R.X0 + 700.0, Cz - 900.0 + 1000.0 * Float (K), Cz - 400.0 + 1000.0 * Float (K),
                      Fy + Table_Drop, Fy, 14.0, (0.75, 0.62, 0.42, 1.0), (0.4, 0.4, 0.42, 1.0));
            end loop;
         when Chess =>
            Shelves (B, Cx, R.Z0 + 80.0, Fy, 2000.0, Dark_Wood, 1.0);
            Chair (B, R.X1 - 500.0, Cz, Fy, Pi, (0.45, 0.15, 0.12, 1.0));
         when Party =>
            --  bunting across the room, balloons by the walls
            for Line in 0 .. 2 loop
               declare
                  Z : constant Float := R.Z0 + (R.Z1 - R.Z0) * (0.25 + 0.25 * Float (Line));
                  Y : constant Float := Fy + Room_H - 120.0;
                  N : constant := 24;
               begin
                  for K in 0 .. N - 1 loop
                     declare
                        X0 : constant Float := R.X0 + (R.X1 - R.X0) * Float (K) / Float (N);
                        X1 : constant Float := R.X0 + (R.X1 - R.X0) * Float (K + 1) / Float (N);
                        Sag : constant Float := 140.0 * Sin (Pi * (Float (K) + 0.5) / Float (N));
                        Hue : constant Float := Float (K) * 1.3;
                     begin
                        Quad (B, (X0, Y - Sag, Z), (X1, Y - Sag, Z), ((X0 + X1) / 2.0, Y - Sag - 70.0, Z),
                              ((X0 + X1) / 2.0, Y - Sag - 70.0, Z),
                              (0.6 + 0.4 * Sin (Hue), 0.6 + 0.4 * Sin (Hue + 2.1), 0.6 + 0.4 * Sin (Hue + 4.2), 1.0));
                     end;
                  end loop;
               end;
            end loop;
            for K in 1 .. 10 loop
               declare
                  P : constant V3 := (R.X0 + 150.0 + (R.X1 - R.X0 - 300.0) * Rnd, Fy + 500.0 + 300.0 * Rnd,
                                      (if K mod 2 = 0 then R.Z0 + 150.0 else R.Z1 - 150.0));
                  Hue : constant Float := 6.0 * Rnd;
               begin
                  Sphere (B, P, 70.0, (0.6 + 0.4 * Sin (Hue), 0.6 + 0.4 * Sin (Hue + 2.1), 0.6 + 0.4 * Sin (Hue + 4.2), 1.0),
                          14);
                  Cylinder (B, P, 1.0, 1.0, 0.0, Fy, P.Y - 70.0, White, 0.0, 3, Cap => False);
               end;
            end loop;
         when Toy_Town =>
            --  shelves of toy blocks, a teddy on the floor
            Shelves (B, Cx, R.Z0 + 80.0, Fy, 1600.0, (0.85, 0.65, 0.35, 1.0), 1.0);
            declare
               T : constant V3 := (R.X1 - 300.0, Fy, Cz);
               Fur : constant Color := (0.62, 0.42, 0.22, 1.0);
            begin
               Sphere (B, T + (0.0, 200.0, 0.0), 200.0, Fur, 16);
               Sphere (B, T + (0.0, 520.0, 0.0), 140.0, Fur, 16);
               Sphere (B, T + (0.0, 640.0, 110.0), 50.0, Fur, 10);
               Sphere (B, T + (0.0, 640.0, -110.0), 50.0, Fur, 10);
               Sphere (B, T + (-120.0, 510.0, 0.0), 50.0, (0.85, 0.7, 0.5, 1.0), 10);
               Sphere (B, T + (-130.0, 560.0, 45.0), 14.0, (0.05, 0.05, 0.05, 1.0), 6);
               Sphere (B, T + (-130.0, 560.0, -45.0), 14.0, (0.05, 0.05, 0.05, 1.0), 6);
            end;
         when others =>
            null;
      end case;
   end Furnish;

   --  Wall colours
   function Wall_Of return Color is
     (case Theme is
         when Workbench => (0.62, 0.52, 0.40, 1.0),
         when Bath => (0.82, 0.90, 0.92, 1.0),
         when Bedroom => (0.62, 0.72, 0.88, 1.0),
         when Kitchen => (0.93, 0.87, 0.70, 1.0),
         when Pool => (0.40, 0.28, 0.20, 1.0),
         when Desk => (0.86, 0.85, 0.74, 1.0),
         when Toy_Town => (0.96, 0.86, 0.55, 1.0),
         when Attic => (0.32, 0.24, 0.17, 1.0),
         when Party => (0.96, 0.76, 0.82, 1.0),
         when Garage => (0.62, 0.62, 0.64, 1.0),
         when Xmas => (0.55, 0.16, 0.14, 1.0),
         when Chess => (0.48, 0.34, 0.22, 1.0),
         when Fish_Tank => (0.30, 0.32, 0.38, 1.0),
         when others => (0.8, 0.8, 0.8, 1.0));

   ---------------------------------------------------------------------------

   procedure Build (B, Clear : in out Buffer; Ground_Y : Float; Horizon : Color) is
      Far : constant := 30000.0;
      GC : constant Art.RGB := Art.Ground_Color;
      Around_C : constant Color :=
        (case Theme is
            when Beach => (0.18, 0.48, 0.70, 1.0),
            when Pool | Desk | Chess | Party | Toy_Town | Workbench | Bath => (0.52, 0.38, 0.26, 1.0),
            when Fish_Tank => (0.25, 0.22, 0.2, 1.0),
            when others => (GC.R, GC.G, GC.B, 1.0));
      Fy : constant Float := Floor_Y (Ground_Y);

      procedure Ground (X0, Z0, X1, Z1, Y, Tex : Float; C : Color) is
      begin
         Quad (B, (X0, Y, Z0), (X1, Y, Z0), (X1, Y, Z1), (X0, Y, Z1), C, Tex);
      end Ground;
   begin
      W := Tracks.Width;
      H := Tracks.Height;
      Middle := (W / 2.0, 0.0, H / 2.0);
      Rand := Geom.Seed (Theme_Kind'Pos (Theme) * 7919 + 17);

      --  The floor round it all, and the picture of the track
      Ground (-Far, -Far, Far, Far, Fy - 0.5, 0.0, Around_C);
      if Has_Table then
         Ground (0.0, 0.0, W, H, Fy, 1.0, White);
         Ground (Table_Left, Table_Top, Table_Right, Table_Bottom, 0.0, 1.0, White);
         declare
            L : constant Float := Table_Left;
            R : constant Float := Table_Right;
            T : constant Float := Table_Top;
            Bt : constant Float := Table_Bottom;
            Th : constant := 14.0;
         begin
            Quad (B, (L, 0.0, T), (R, 0.0, T), (R, -Th, T), (L, -Th, T), Wood);
            Quad (B, (L, 0.0, Bt), (R, 0.0, Bt), (R, -Th, Bt), (L, -Th, Bt), Wood);
            Quad (B, (L, 0.0, T), (L, 0.0, Bt), (L, -Th, Bt), (L, -Th, T), Wood);
            Quad (B, (R, 0.0, T), (R, 0.0, Bt), (R, -Th, Bt), (R, -Th, T), Wood);
            for Corner in 0 .. 3 loop
               declare
                  X : constant Float := (if Corner mod 2 = 0 then L + 30.0 else R - 30.0);
                  Z : constant Float := (if Corner < 2 then T + 30.0 else Bt - 30.0);
               begin
                  Block (B, (X, -Table_Drop / 2.0, Z), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 16.0, Table_Drop / 2.0, 16.0,
                         Shade (Wood, 0.8));
               end;
            end loop;
         end;
      else
         Ground (0.0, 0.0, W, H, Ground_Y, 1.0, White);
      end if;

      case Place is
         when Tabletop =>
            --  the track is the top of a table: its edge, its legs, the floor below
            declare
               Edge : constant Color :=
                 (case Theme is
                     when Pool => (0.40, 0.22, 0.10, 1.0),
                     when Party => (0.98, 0.92, 0.95, 1.0),    --  a tablecloth hanging down
                     when Desk => (0.75, 0.62, 0.42, 1.0),
                     when Chess => Dark_Wood,
                     when others => Wood);
               Drop : constant Float := (if Theme = Party then 140.0 elsif Theme = Pool then 110.0 else 30.0);
               Y : constant Float := Ground_Y;
            begin
               Quad (B, (0.0, Y, 0.0), (W, Y, 0.0), (W, Y - Drop, 0.0), (0.0, Y - Drop, 0.0), Edge);
               Quad (B, (0.0, Y, H), (W, Y, H), (W, Y - Drop, H), (0.0, Y - Drop, H), Edge);
               Quad (B, (0.0, Y, 0.0), (0.0, Y, H), (0.0, Y - Drop, H), (0.0, Y - Drop, 0.0), Edge);
               Quad (B, (W, Y, 0.0), (W, Y, H), (W, Y - Drop, H), (W, Y - Drop, 0.0), Edge);
               Quad (B, (0.0, Y - Drop, 0.0), (W, Y - Drop, 0.0), (W, Y - Drop, H), (0.0, Y - Drop, H), Shade (Edge, 0.6));
               for Corner in 0 .. 3 loop
                  declare
                     X : constant Float := (if Corner mod 2 = 0 then 60.0 else W - 60.0);
                     Z : constant Float := (if Corner < 2 then 60.0 else H - 60.0);
                  begin
                     Block (B, (X, (Y - Drop + Fy) / 2.0, Z), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0,
                            (if Theme = Pool then 40.0 else 20.0), (Y - Drop - Fy) / 2.0,
                            (if Theme = Pool then 40.0 else 20.0), (if Theme = Party then Wood else Shade (Edge, 0.85)));
                  end;
               end loop;
            end;
         when Bathtub =>
            --  the rim of the bath round the water, its side down to the floor, the taps
            declare
               Enamel : constant Color := (0.96, 0.96, 0.97, 1.0);
               Rim : constant := 110.0;
               Top : constant Float := Ground_Y + 30.0;
               Chrome : constant Color := (0.8, 0.82, 0.86, 1.0);
            begin
               Block (B, (W / 2.0, (Top + Fy) / 2.0, -Rim / 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, W / 2.0 + Rim,
                      (Top - Fy) / 2.0, Rim / 2.0, Enamel);
               Block (B, (W / 2.0, (Top + Fy) / 2.0, H + Rim / 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, W / 2.0 + Rim,
                      (Top - Fy) / 2.0, Rim / 2.0, Enamel);
               Block (B, (-Rim / 2.0, (Top + Fy) / 2.0, H / 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, Rim / 2.0,
                      (Top - Fy) / 2.0, H / 2.0, Enamel);
               Block (B, (W + Rim / 2.0, (Top + Fy) / 2.0, H / 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, Rim / 2.0,
                      (Top - Fy) / 2.0, H / 2.0, Enamel);
               for K in -1 .. 1 loop
                  if K /= 0 then
                     Cylinder (B, (W / 2.0 + 120.0 * Float (K), Top, -Rim / 2.0), 22.0, 22.0, 0.0, Top, Top + 80.0,
                               Chrome, 0.0, 12);
                     Cylinder (B, (W / 2.0 + 120.0 * Float (K), Top, -Rim / 2.0), 36.0, 36.0, 0.0, Top + 80.0,
                               Top + 95.0, Chrome, 0.0, 12);
                  end if;
               end loop;
               Barrel (B, (W / 2.0, Top + 110.0, -Rim / 2.0 + 40.0), (0.0, 0.0, 1.0), 14.0, 70.0, Chrome, 10);
            end;
         when Tank =>
            --  the glass of the tank, its black rim, the water's face above
            declare
               Top : constant Float := Ground_Y + 520.0;
               Glass : constant Color := (0.70, 0.88, 0.95, 0.14);
               Water : constant Color := (0.55, 0.85, 0.95, 0.30);
               Rim : constant Color := (0.05, 0.05, 0.06, 1.0);
               Y : constant Float := Ground_Y;
            begin
               Quad (Clear, (0.0, Y, 0.0), (W, Y, 0.0), (W, Top, 0.0), (0.0, Top, 0.0), Glass, Lit => False);
               Quad (Clear, (0.0, Y, H), (W, Y, H), (W, Top, H), (0.0, Top, H), Glass, Lit => False);
               Quad (Clear, (0.0, Y, 0.0), (0.0, Y, H), (0.0, Top, H), (0.0, Top, 0.0), Glass, Lit => False);
               Quad (Clear, (W, Y, 0.0), (W, Y, H), (W, Top, H), (W, Top, 0.0), Glass, Lit => False);
               Quad (Clear, (0.0, Top - 60.0, 0.0), (W, Top - 60.0, 0.0), (W, Top - 60.0, H), (0.0, Top - 60.0, H),
                     Water, Lit => False);
               Block (B, (W / 2.0, Top, 0.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, W / 2.0 + 8.0, 12.0, 8.0, Rim);
               Block (B, (W / 2.0, Top, H), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, W / 2.0 + 8.0, 12.0, 8.0, Rim);
               Block (B, (0.0, Top, H / 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 8.0, 12.0, H / 2.0 + 8.0, Rim);
               Block (B, (W, Top, H / 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, 8.0, 12.0, H / 2.0 + 8.0, Rim);
               --  the cabinet it stands on
               Block (B, (W / 2.0, (Y + Fy) / 2.0, H / 2.0), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0, W / 2.0 + 30.0,
                      (Y - Fy) / 2.0, H / 2.0 + 30.0, Dark_Wood);
            end;
         when others =>
            null;
      end case;

      case Place is
         when Room | Tabletop | Bench | Bathtub | Tank =>
            declare
               M : constant Float := (case Place is
                                         when Room => 700.0,
                                         when Tank => 1400.0,
                                         when others => 900.0);
               R : constant Room_Box := (-M, W + M, -M, H + M, Fy);
               Wall : constant Color := Wall_Of;
            begin
               if Theme = Attic then
                  --  low walls, and the roof sloping up to a beam along the middle
                  declare
                     Low : constant Float := Fy + 320.0;
                     Ridge : constant Float := Fy + 1500.0;
                     Zm : constant Float := H / 2.0;
                  begin
                     Quad (B, (R.X0, Fy, R.Z0), (R.X1, Fy, R.Z0), (R.X1, Low, R.Z0), (R.X0, Low, R.Z0), Wall);
                     Quad (B, (R.X0, Fy, R.Z1), (R.X1, Fy, R.Z1), (R.X1, Low, R.Z1), (R.X0, Low, R.Z1), Wall);
                     Quad (B, (R.X0, Low, R.Z0), (R.X1, Low, R.Z0), (R.X1, Ridge, Zm), (R.X0, Ridge, Zm),
                           (0.40, 0.29, 0.20, 1.0));
                     Quad (B, (R.X0, Low, R.Z1), (R.X1, Low, R.Z1), (R.X1, Ridge, Zm), (R.X0, Ridge, Zm),
                           (0.38, 0.28, 0.19, 1.0));
                     for Ends in 0 .. 1 loop
                        declare
                           X : constant Float := (if Ends = 0 then R.X0 else R.X1);
                        begin
                           Quad (B, (X, Fy, R.Z0), (X, Fy, R.Z1), (X, Low, R.Z1), (X, Low, R.Z0), Wall);
                           Tri (B, (X, Low, R.Z0), (X, Low, R.Z1), (X, Ridge, Zm), Shade (Wall, 0.9));
                        end;
                     end loop;
                     --  the rafters, and a round window with the moon in it
                     declare
                        X : Float := R.X0 + 200.0;
                     begin
                        while X < R.X1 loop
                           for Side in 0 .. 1 loop
                              declare
                                 Z0 : constant Float := (if Side = 0 then R.Z0 else R.Z1);
                                 Mid : constant V3 := (X, (Low + Ridge) / 2.0 - 20.0, (Z0 + Zm) / 2.0);
                                 Along : constant V3 := Normal ((0.0, Ridge - Low, Zm - Z0));
                              begin
                                 Quad (B, Mid - 600.0 * Along + (-20.0, 0.0, 0.0), Mid - 600.0 * Along + (20.0, 0.0, 0.0),
                                       Mid + 600.0 * Along + (20.0, 0.0, 0.0), Mid + 600.0 * Along + (-20.0, 0.0, 0.0),
                                       Dark_Wood);
                              end;
                           end loop;
                           X := X + 450.0;
                        end loop;
                     end;
                     Block (B, ((R.X0 + R.X1) / 2.0, Ridge - 30.0, Zm), (1.0, 0.0, 0.0), 0.0, 0.0, 0.0,
                            (R.X1 - R.X0) / 2.0, 30.0, 30.0, Dark_Wood);
                     Sky_Disc (B, (R.X1 - 2.0, Fy + 700.0, Zm), 160.0, (0.05, 0.07, 0.18, 1.0), (0.08, 0.10, 0.25, 1.0));
                     Sky_Disc (B, (R.X1 - 3.0, Fy + 740.0, Zm + 40.0), 45.0, (0.95, 0.95, 0.85, 1.0),
                               (0.9, 0.9, 0.8, 1.0));
                     Block (B, (R.X1 - 4.0, Fy + 700.0, Zm), (0.0, 0.0, 1.0), 0.0, 0.0, 0.0, 165.0, 8.0, 6.0, Dark_Wood);
                     Block (B, (R.X1 - 4.0, Fy + 700.0, Zm), (0.0, 0.0, 1.0), 0.0, 0.0, 0.0, 8.0, 165.0, 6.0, Dark_Wood);
                  end;
               else
                  Room (B, R, Wall, (if Theme in Pool | Chess | Xmas then Dark_Wood else White),
                        (if Theme = Garage then (0.55, 0.55, 0.57, 1.0) else (0.95, 0.95, 0.93, 1.0)));
                  North_Window (B, R, W * 0.3, 260.0, (0.40, 0.62, 0.92, 1.0), (0.78, 0.88, 0.98, 1.0),
                                (if Theme in Garage | Pool then (0.3, 0.3, 0.3, 1.0) else White));
                  West_Door (B, R, H / 2.0, (if Theme = Bath then White else Wood));
                  if Theme = Bath then
                     --  tiles on the walls: lines across them
                     for K in 1 .. 20 loop
                        Block (B, ((R.X0 + R.X1) / 2.0, Fy + 50.0 * Float (K), R.Z0 + 2.0), (1.0, 0.0, 0.0), 0.0, 0.0,
                               0.0, (R.X1 - R.X0) / 2.0, 1.5, 1.0, Shade (Wall, 0.85));
                        Block (B, ((R.X0 + R.X1) / 2.0, Fy + 50.0 * Float (K), R.Z1 - 2.0), (1.0, 0.0, 0.0), 0.0, 0.0,
                               0.0, (R.X1 - R.X0) / 2.0, 1.5, 1.0, Shade (Wall, 0.85));
                     end loop;
                  end if;
               end if;
               Furnish (B, R);
            end;

         when Outside =>
            declare
               Top : constant Color :=
                 (case Theme is
                     when Ice | Arctic => (0.40, 0.58, 0.85, 1.0),
                     when Sky => (0.22, 0.45, 0.90, 1.0),
                     when others => (0.28, 0.50, 0.88, 1.0));
               Base : constant Float := Ground_Y;
            begin
               Sky_Dome (B, Top, Horizon, Base);
               Clouds (B, 14, Base + 1500.0, Base + 4500.0);
               case Theme is
                  when Garden | Easter =>
                     Hills (B, 14, 2500.0, 6000.0, 1800.0, Base, (0.32, 0.55, 0.22, 1.0));
                     for K in 1 .. 26 loop
                        Leafy_Tree (B, At_Y (Around (500.0, 2200.0), Base), 400.0 + 400.0 * Rnd,
                                    (0.20, 0.48 + 0.15 * Rnd, 0.15, 1.0));
                     end loop;
                     --  a house far off
                     declare
                        P : constant V3 := (W * 0.5, Base, -2600.0);
                     begin
                        Block (B, P, (1.0, 0.0, 0.0), 0.0, 450.0, 0.0, 700.0, 450.0, 400.0, (0.85, 0.80, 0.70, 1.0));
                        Quad (B, P + (-720.0, 900.0, -420.0), P + (720.0, 900.0, -420.0), P + (720.0, 1350.0, 0.0),
                              P + (-720.0, 1350.0, 0.0), (0.65, 0.25, 0.20, 1.0));
                        Quad (B, P + (-720.0, 900.0, 420.0), P + (720.0, 900.0, 420.0), P + (720.0, 1350.0, 0.0),
                              P + (-720.0, 1350.0, 0.0), (0.60, 0.22, 0.18, 1.0));
                        for K in 0 .. 2 loop
                           Block (B, P + (-450.0 + 450.0 * Float (K), 0.0, 0.0), (1.0, 0.0, 0.0), 0.0, 520.0, 402.0,
                                  110.0, 120.0, 2.0, (0.45, 0.65, 0.85, 1.0));
                        end loop;
                     end;
                  when Mud =>
                     Hills (B, 16, 2000.0, 6000.0, 2000.0, Base, (0.40, 0.48, 0.25, 1.0));
                     for K in 1 .. 18 loop
                        Leafy_Tree (B, At_Y (Around (600.0, 2500.0), Base), 450.0 + 400.0 * Rnd,
                                    (0.25, 0.42 + 0.1 * Rnd, 0.16, 1.0));
                     end loop;
                     declare
                        P : constant V3 := (W + 1600.0, Base, H * 0.3);
                     begin
                        Block (B, P, (0.0, 0.0, 1.0), 0.0, 500.0, 0.0, 800.0, 500.0, 500.0, (0.65, 0.18, 0.12, 1.0));
                        Quad (B, P + (-520.0, 1000.0, -820.0), P + (-520.0, 1000.0, 820.0), P + (0.0, 1450.0, 820.0),
                              P + (0.0, 1450.0, -820.0), (0.35, 0.33, 0.32, 1.0));
                        Quad (B, P + (520.0, 1000.0, -820.0), P + (520.0, 1000.0, 820.0), P + (0.0, 1450.0, 820.0),
                              P + (0.0, 1450.0, -820.0), (0.33, 0.31, 0.30, 1.0));
                        Block (B, P + (-502.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.0, 280.0, 0.0, 240.0, 280.0, 2.0,
                               (0.95, 0.95, 0.9, 1.0));
                     end;
                  when Beach =>
                     --  the sea, islands, a sailing boat
                     Hills (B, 5, 3500.0, 7000.0, 1500.0, Base - 100.0, (0.75, 0.70, 0.50, 1.0));
                     for K in 1 .. 3 loop
                        declare
                           P : constant V3 := At_Y (Around (1200.0, 3000.0), Base);
                        begin
                           Block (B, P, (1.0, 0.0, 0.0), 0.0, 20.0, 0.0, 140.0, 20.0, 45.0, White);
                           Tri (B, P + (-20.0, 40.0, 0.0), P + (100.0, 40.0, 0.0), P + (-20.0, 380.0, 0.0),
                                (1.0, 0.98, 0.92, 1.0));
                        end;
                     end loop;
                     for K in 1 .. 8 loop
                        Leafy_Tree (B, At_Y (Around (300.0, 900.0), Base), 500.0, (0.25, 0.55, 0.2, 1.0));
                     end loop;
                  when Ice | Arctic =>
                     Mountains (B, 12, 3000.0, 7000.0, Base, (0.55, 0.58, 0.66, 1.0), (0.97, 0.98, 1.0, 1.0));
                     Hills (B, 14, 1000.0, 3500.0, 1500.0, Base, (0.94, 0.96, 1.0, 1.0));
                     for K in 1 .. 30 loop
                        Fir (B, At_Y (Around (300.0, 2500.0), Base), 500.0 + 500.0 * Rnd, (0.15, 0.35, 0.22, 1.0), True);
                     end loop;
                  when Sky =>
                     --  more clouds round the course, at the planes' height and below
                     Clouds (B, 30, Base - 300.0, Base + 600.0);
                  when others =>
                     null;
               end case;
            end;

         when Night_Out =>
            declare
               Base : constant Float := Ground_Y;
            begin
               Sky_Dome (B, (0.02, 0.01, 0.06, 1.0), Horizon, Base);
               Stars (B, 260, Base);
               Sky_Disc (B, (Middle.X - 4000.0, Base + 3800.0, Middle.Z - 6500.0), 700.0, (1.0, 0.95, 0.75, 1.0),
                         (0.95, 0.85, 0.55, 1.0));
               Clouds (B, 6, Base + 2000.0, Base + 3500.0, Night => True);
               Hills (B, 14, 1500.0, 5000.0, 1800.0, Base, (0.10, 0.08, 0.14, 1.0));
               --  bare trees
               for K in 1 .. 20 loop
                  declare
                     P : constant V3 := At_Y (Around (400.0, 2000.0), Base);
                     S : constant Float := 300.0 + 300.0 * Rnd;
                     Bark : constant Color := (0.12, 0.10, 0.12, 1.0);
                  begin
                     Cylinder (B, P, S * 0.06, S * 0.06, 0.0, Base, Base + S, Bark, 0.0, 6, Taper => 0.3);
                     for Br in 1 .. 4 loop
                        declare
                           A : constant Float := 2.0 * Pi * Rnd;
                           Y : constant Float := Base + S * (0.5 + 0.4 * Rnd);
                           D : constant V3 := (Cos (A), 0.7, Sin (A));
                        begin
                           Barrel (B, At_Y (P, Y) + (S * 0.2) * Normal (D), Normal (D), S * 0.02, S * 0.22, Bark, 4);
                        end;
                     end loop;
                  end;
               end loop;
            end;

         when Space =>
            declare
               Base : constant Float := Ground_Y;
            begin
               if Theme = Moon then
                  Sky_Dome (B, (0.0, 0.0, 0.01, 1.0), Horizon, Base);
                  Stars (B, 500, Base);
                  Sky_Ball (B, (Middle.X + 3000.0, Base + 3500.0, Middle.Z - 7000.0), 900.0, 900.0, 900.0,
                            Earth_Shade'Access);
                  Hills (B, 20, 1500.0, 6000.0, 1600.0, Base, (0.45, 0.45, 0.47, 1.0));
                  Mountains (B, 8, 4000.0, 7500.0, Base, (0.42, 0.42, 0.44, 1.0), (0.5, 0.5, 0.52, 1.0));
               else
                  Sky_Dome (B, (0.12, 0.03, 0.22, 1.0), Horizon, Base);
                  Stars (B, 120, Base + 1500.0);
                  Sky_Disc (B, (Middle.X - 5000.0, Base + 3000.0, Middle.Z - 6000.0), 900.0, (0.85, 0.95, 0.6, 1.0),
                            (0.7, 0.85, 0.45, 1.0));
                  Sky_Disc (B, (Middle.X + 4000.0, Base + 4200.0, Middle.Z - 6800.0), 450.0, (0.95, 0.6, 0.85, 1.0),
                            (0.85, 0.45, 0.75, 1.0));
                  Hills (B, 16, 1500.0, 6000.0, 1800.0, Base, (0.35, 0.18, 0.40, 1.0));
                  for K in 1 .. 24 loop
                     declare
                        P : constant V3 := At_Y (Around (400.0, 3000.0), Base);
                        S : constant Float := 300.0 + 900.0 * Rnd;
                        Hue : constant Float := 6.0 * Rnd;
                     begin
                        Cylinder (B, P, S * 0.12, S * 0.12, Rnd, Base, Base + S,
                                  (0.45 + 0.3 * Sin (Hue), 0.3 + 0.3 * Sin (Hue + 2.0), 0.6 + 0.3 * Sin (Hue + 4.0), 1.0),
                                  0.0, 6, Cap => False, Taper => 0.0);
                     end;
                  end loop;
               end if;
            end;
      end case;
   end Build;

end Scenery;
