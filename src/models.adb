--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Interfaces;
with System;
with Cairo;
with Cairo.Image_Surface;
with Art;

package body Models is

   use Mesh;
   use Tracks;
   use type System.Address;
   use type Geom.Vec;

   Pi : constant := Geom.Pi;

   White : constant Color := (1.0, 1.0, 1.0, 1.0);
   Black : constant Color := (0.05, 0.05, 0.06, 1.0);
   Tyre  : constant Color := (0.10, 0.10, 0.11, 1.0);
   Glass : constant Color := (0.16, 0.22, 0.30, 1.0);
   Lamp  : constant Color := (1.0, 0.97, 0.80, 1.0);
   Metal : constant Color := (0.55, 0.57, 0.60, 1.0);
   Orange : constant Color := (0.98, 0.55, 0.10, 1.0);
   Wood  : constant Color := (0.45, 0.30, 0.18, 1.0);

   function Dir3 (A : Float) return V3 is ((Cos (A), 0.0, Sin (A)));
   function Side_Of (F : V3) return V3 is ((-F.Z, 0.0, F.X));

   ---------------------------------------------------------------------------
   --  The picture of the world
   ---------------------------------------------------------------------------

   World_Data : System.Address := System.Null_Address;
   World_Stride, World_PW, World_PH : Natural := 0;

   procedure Set_Picture is
      use Cairo.Image_Surface;
   begin
      World_Data := Get_Data_Generic (Art.World);
      World_Stride := Natural (Get_Stride (Art.World));
      World_PW := Natural (Get_Width (Art.World));
      World_PH := Natural (Get_Height (Art.World));
   end Set_Picture;

   function Ground_At (P : Geom.Vec) return Color is
      type Bytes is array (Natural range <>) of Interfaces.Unsigned_8;
      X : constant Integer := Integer (P.X * Art.Scale);
      Y : constant Integer := Integer (P.Y * Art.Scale);
   begin
      if World_Data = System.Null_Address or else X not in 0 .. World_PW - 1 or else Y not in 0 .. World_PH - 1 then
         return (0.6, 0.55, 0.5, 1.0);
      end if;
      declare
         Data : Bytes (0 .. World_Stride * World_PH - 1) with Import, Address => World_Data;
         I : constant Natural := Y * World_Stride + X * 4;
      begin
         return (Float (Data (I + 2)) / 255.0, Float (Data (I + 1)) / 255.0, Float (Data (I)) / 255.0, 1.0);
      end;
   end Ground_At;

   --  The colour drawn at a share of the way from the middle of a thing to its edge
   function Color_At (S : Shape; Share : Float) return Color is
     (Ground_At (S.C + Geom.Dir (S.A + 0.6) * (S.RX * Share)));

   ---------------------------------------------------------------------------
   --  The things in the way
   ---------------------------------------------------------------------------

   type Look_Kind is (Prism, Rounded, Ball);

   function Look_Of (K : Item_Kind) return Look_Kind is
     (case K is
         when Stone | Moon_Rock | Pumpkin | Igloo | Dome | Snow_Pile | Bush | Jelly | Pine_Cone
            | Rubber_Duck | Easter_Egg | Bubbles | Sponge | Seal | Choc_Bunny | Egg_Pod
            | Shell | Nest | Alien_Plant | Sandcastle => Rounded,
         when Snooker_Ball | Beach_Ball | Pea | Bauble | Balloon => Ball,
         when others => Prism);

   function Height_Of (It : Tracks.Item) return Float is
      Size : constant Float := Float'Max (It.S.RX, (if It.S.Kind = Circle then It.S.RX else It.S.RY));
   begin
      if It.Mat = Bump then
         return 7.0;
      end if;
      case It.Kind is
         when Pencil | Crayon | Cue | Plank => return 7.0;
         when Ruler | Fork | Spoon | Coin | Paper_Clip | Rubber_Band => return 3.0;
         when Screw => return 5.0;
         when Nut | Bottle_Cap => return 6.0;
         when Battery | Tape_Roll | Soap | Eraser | Chalk_Cube => return 12.0;
         when Book => return 22.0;
         when Mug => return 55.0;
         when Bottle => return 95.0;
         when Salt_Shaker => return 50.0;
         when Pine_Tree => return 130.0;
         when Xmas_Tree => return 230.0;
         when Model_Tree => return 60.0;
         when Candle => return 60.0;
         when Pawn => return 45.0;
         when Rook => return 60.0;
         when Knight_Piece => return 70.0;
         when Bishop => return 82.0;
         when Queen => return 98.0;
         when King => return 112.0;
         when Spire => return 150.0;
         when Crystal => return 70.0;
         when Lander => return 50.0;
         when Flag => return 60.0;
         when Cake => return 65.0;
         when Gravestone => return 45.0;
         when House => return 55.0;
         when Castle => return 70.0;
         when Trunk => return 45.0;
         when Rocking_Horse => return 70.0;
         when Carton => return 55.0;
         when Toolbox => return 40.0;
         when Paint_Tin => return 45.0;
         when Present => return 40.0;
         when Chest => return 30.0;
         when Bucket => return 40.0;
         when Tyre_Stack => return 36.0;
         when Hay_Bale => return 28.0;
         when Pot => return 35.0;
         when Ice_Block => return 22.0;
         when Cauldron => return 35.0;
         when Snowman => return 3.4 * Size;
         when Cupcake => return 30.0;
         when Snooker_Ball | Beach_Ball | Pea | Bauble | Balloon => return 2.0 * Size;
         when others => return Geom.Clamp (1.1 * Size, 6.0, 70.0);
      end case;
   end Height_Of;

   function Is_Solid_Shape (It : Tracks.Item) return Boolean is (It.Mat in Solid | Bump and then not Is_Below (It));

   --  The chess pieces, a profile each, one across and one high
   Pawn_Profile : constant Profile :=
     ((1.0, 0.0), (1.0, 0.08), (0.75, 0.12), (0.45, 0.2), (0.3, 0.52), (0.55, 0.57), (0.3, 0.62),
      (0.42, 0.68), (0.5, 0.78), (0.45, 0.88), (0.3, 0.96), (0.0, 1.0));
   Rook_Profile : constant Profile :=
     ((1.0, 0.0), (1.0, 0.08), (0.72, 0.14), (0.55, 0.3), (0.5, 0.74), (0.72, 0.8), (0.72, 1.0),
      (0.5, 1.0), (0.5, 0.92), (0.0, 0.92));
   Bishop_Profile : constant Profile :=
     ((1.0, 0.0), (1.0, 0.07), (0.7, 0.12), (0.45, 0.2), (0.28, 0.58), (0.52, 0.62), (0.3, 0.66),
      (0.42, 0.76), (0.38, 0.86), (0.2, 0.94), (0.12, 0.96), (0.15, 0.99), (0.0, 1.0));
   Queen_Profile : constant Profile :=
     ((1.0, 0.0), (1.0, 0.07), (0.7, 0.12), (0.45, 0.2), (0.28, 0.6), (0.52, 0.64), (0.3, 0.68),
      (0.55, 0.88), (0.38, 0.9), (0.25, 0.93), (0.15, 0.97), (0.0, 1.0));
   King_Profile : constant Profile :=
     ((1.0, 0.0), (1.0, 0.07), (0.7, 0.12), (0.45, 0.2), (0.3, 0.6), (0.52, 0.64), (0.3, 0.68),
      (0.5, 0.82), (0.45, 0.86), (0.0, 0.88));
   Bottle_Profile : constant Profile :=
     ((1.0, 0.0), (1.0, 0.55), (0.85, 0.64), (0.38, 0.76), (0.32, 0.97), (0.36, 1.0), (0.0, 1.0));
   Shaker_Profile : constant Profile :=
     ((1.0, 0.0), (1.0, 0.72), (0.92, 0.86), (0.65, 0.96), (0.0, 1.0));
   Cup_Profile : constant Profile :=
     ((0.75, 0.0), (1.0, 0.55), (0.0, 0.55));

   procedure Knight_Model (B : in out Buffer; C : V3; R, Ht, A : Float; Col : Color) is
      Fwd : constant V3 := Dir3 (A);
      Sd : constant V3 := Side_Of (Fwd);
      Dark : constant Color := Shade (Col, 0.85);
   begin
      Lathe (B, C, ((1.0, 0.0), (1.0, 0.08), (0.72, 0.13), (0.62, 0.22), (0.66, 0.27), (0.0, 0.27)), R, Ht, Col);
      --  the neck rising and leaning forward, a block at a time
      for K in 0 .. 5 loop
         declare
            T : constant Float := Float (K) / 5.0;
         begin
            Block (B, C, Fwd, R * (-0.15 + 0.25 * T * T), Ht * (0.32 + 0.09 * Float (K)), 0.0,
                   R * (0.42 - 0.05 * T), Ht * 0.06, R * (0.34 - 0.06 * T), Col);
         end;
      end loop;
      --  the head, the muzzle tipped down, the mane behind, the ears and eyes
      Block (B, C, Fwd, R * 0.35, Ht * 0.80, 0.0, R * 0.45, Ht * 0.08, R * 0.26, Col);
      Block (B, C, Fwd, R * 0.72, Ht * 0.72, 0.0, R * 0.2, Ht * 0.07, R * 0.22, Col);
      Block (B, C, Fwd, R * 0.86, Ht * 0.68, 0.0, R * 0.06, Ht * 0.04, R * 0.18, Dark);
      for K in 0 .. 4 loop
         Block (B, C, Fwd, R * (-0.45 + 0.05 * Float (K)), Ht * (0.42 + 0.1 * Float (K)), 0.0, R * 0.08, Ht * 0.06,
                R * 0.1, Dark);
      end loop;
      Block (B, C, Fwd, R * 0.05, Ht * 0.93, R * 0.14, R * 0.07, Ht * 0.07, R * 0.05, Col);
      Block (B, C, Fwd, R * 0.05, Ht * 0.93, -R * 0.14, R * 0.07, Ht * 0.07, R * 0.05, Col);
      Sphere (B, C + (R * 0.5) * Fwd + (R * 0.25) * Sd + (0.0, Ht * 0.83, 0.0), R * 0.05, (0.05, 0.05, 0.05, 1.0), 6);
      Sphere (B, C + (R * 0.5) * Fwd - (R * 0.25) * Sd + (0.0, Ht * 0.83, 0.0), R * 0.05, (0.05, 0.05, 0.05, 1.0), 6);
   end Knight_Model;

   procedure Tree (B : in out Buffer; C : V3; R, Ht : Float; Green : Color; Baubles : Boolean) is
      Rand : Geom.Seed := Geom.Seed (Integer (abs C.X * 7.0 + abs C.Z * 13.0) mod 100_000 + 1);
   begin
      Cylinder (B, C, R * 0.14, R * 0.14, 0.0, C.Y, C.Y + Ht * 0.15, Wood, 0.0, 8);
      for Tier in 0 .. 2 loop
         declare
            Base : constant Float := C.Y + Ht * (0.12 + 0.26 * Float (Tier));
            Width : constant Float := R * (1.0 - 0.24 * Float (Tier));
            Top : constant Float := Base + Ht * (0.46 - 0.04 * Float (Tier));
         begin
            Cylinder (B, (C.X, Base, C.Z), Width, Width, 0.0, Base, Top, Shade (Green, 0.9 + 0.1 * Float (Tier)),
                      0.0, 16, Cap => False, Taper => 0.0);
            if Baubles then
               for K in 1 .. 6 loop
                  declare
                     A : constant Float := 2.0 * Pi * Geom.Random (Rand);
                     H : constant Float := 0.15 + 0.5 * Geom.Random (Rand);
                     Rr : constant Float := Width * (1.0 - H) * 0.96;
                     Hue : constant Float := 6.0 * Geom.Random (Rand);
                  begin
                     Sphere (B, (C.X + Rr * Cos (A), Base + (Top - Base) * H, C.Z + Rr * Sin (A)), R * 0.07,
                             (0.6 + 0.4 * Sin (Hue), 0.6 + 0.4 * Sin (Hue + 2.1), 0.6 + 0.4 * Sin (Hue + 4.2), 1.0), 8);
                  end;
               end loop;
            end if;
         end;
      end loop;
      if Baubles then   --  a star on top
         Sphere (B, (C.X, C.Y + Ht * 1.0, C.Z), R * 0.09, (1.0, 0.85, 0.2, 1.0), 8);
      end if;
   end Tree;

   --  A flame that is not lit but gives light: two crossed leaves
   procedure Flame (B : in out Buffer; P : V3; Size : Float) is
      Fl : constant Color := (1.0, 0.78, 0.3, 1.0);
   begin
      Quad (B, P + (-Size * 0.4, 0.0, 0.0), P + (Size * 0.4, 0.0, 0.0), P + (0.0, Size * 1.6, 0.0),
            P + (0.0, Size * 1.6, 0.0), Fl, Lit => False);
      Quad (B, P + (0.0, 0.0, -Size * 0.4), P + (0.0, 0.0, Size * 0.4), P + (0.0, Size * 1.6, 0.0),
            P + (0.0, Size * 1.6, 0.0), Fl, Lit => False);
   end Flame;

   procedure Item (B : in out Buffer; It : Tracks.Item; Ground_Y, Fly_Height : Float) is
      S  : Shape renames It.S;
      C  : constant V3 := To3 (S.C, Ground_Y);
      Ht : constant Float := Height_Of (It);
      R  : constant Float := (if S.Kind = Circle then S.RX else Float'Min (S.RX, S.RY));
      Side : constant Color := (0.9, 0.9, 0.9, 1.0);
   begin
      if It.Mat in Solid | Bump and then not Is_Below (It) then
         Pull_Center := C;
         Pull := 0.82;
         if Vehicle = Plane and then It.Mat = Solid then
            --  up in the air with the planes: a floating lump
            declare
               Mid : constant V3 := (C.X, Fly_Height, C.Z);
               RZ  : constant Float := (if S.Kind = Circle then S.RX else S.RY);
               Thick : constant Float := Float'Max (10.0, Float'Min (S.RX, RZ) * 0.5);
            begin
               Pull := 1.0;
               Dome (B, Mid, S.RX, RZ, S.A, Thick, White, 1.0);
               Dome (B, Mid, S.RX, RZ, S.A, -Thick, Shade (White, 0.85), 1.0);
            end;
         elsif It.Kind in Pawn | Rook | Bishop | Queen | King then
            declare
               Col : constant Color := Color_At (S, 0.75);
            begin
               case It.Kind is
                  when Pawn => Lathe (B, C, Pawn_Profile, R, Ht, Col);
                  when Rook => Lathe (B, C, Rook_Profile, R, Ht, Col);
                  when Bishop => Lathe (B, C, Bishop_Profile, R, Ht, Col);
                  when Queen => Lathe (B, C, Queen_Profile, R, Ht, Col);
                  when others =>
                     Lathe (B, C, King_Profile, R, Ht, Col);
                     Block (B, C, Dir3 (S.A), 0.0, Ht * 0.95, 0.0, R * 0.08, Ht * 0.08, R * 0.08, Col);
                     Block (B, C, Dir3 (S.A), 0.0, Ht * 0.96, 0.0, R * 0.22, Ht * 0.025, R * 0.08, Col);
               end case;
            end;
         elsif It.Kind = Knight_Piece then
            Knight_Model (B, C, R, Ht, S.A, Color_At (S, 0.75));
         elsif It.Kind in Pine_Tree | Xmas_Tree | Model_Tree then
            Tree (B, C, R, Ht, Color_At (S, 0.55), Baubles => It.Kind = Xmas_Tree);
         elsif It.Kind = Tyre_Stack then
            --  tyres, one on another, the picture on the top one
            declare
               N : constant Positive := 4;
               H : constant Float := Ht / Float (N);
            begin
               for K in 0 .. N - 1 loop
                  Cylinder (B, C, R, R, 0.0, C.Y + Float (K) * H, C.Y + Float (K) * H + H * 0.88, Tyre, 0.0, 18,
                            Cap => False);
                  Cylinder (B, C, R * 0.9, R * 0.9, 0.0, C.Y + Float (K) * H + H * 0.85, C.Y + Float (K + 1) * H,
                            Shade (Tyre, 0.7), 0.0, 18, Cap => False);
               end loop;
               Pull := 1.0;
               Cylinder (B, C, R, R, 0.0, C.Y + Ht - 0.1, C.Y + Ht, White, 1.0, 18);
            end;
         elsif It.Kind = Snowman then
            declare
               R1 : constant Float := R * 0.95;
               R2 : constant Float := R * 0.68;
               R3 : constant Float := R * 0.46;
               Fwd : constant V3 := Dir3 (S.A);
               Head : constant V3 := C + (0.0, 2.0 * R1 + 1.7 * R2 + R3 * 0.8, 0.0);
               Snow : constant Color := (0.96, 0.97, 1.0, 1.0);
            begin
               Sphere (B, C + (0.0, R1, 0.0), R1, Snow, 14);
               Sphere (B, C + (0.0, 2.0 * R1 + R2 * 0.8, 0.0), R2, Snow, 14);
               Sphere (B, Head, R3, Snow, 12);
               Barrel (B, Head + (R3 * 1.2) * Fwd, Fwd, R3 * 0.14, R3 * 0.45, Orange, 6);
               Sphere (B, Head + (R3 * 0.8) * Fwd + (R3 * 0.35) * Side_Of (Fwd) + (0.0, R3 * 0.3, 0.0), R3 * 0.12, Black, 6);
               Sphere (B, Head + (R3 * 0.8) * Fwd - (R3 * 0.35) * Side_Of (Fwd) + (0.0, R3 * 0.3, 0.0), R3 * 0.12, Black, 6);
               Cylinder (B, Head, R3 * 0.75, R3 * 0.75, 0.0, Head.Y + R3 * 0.7, Head.Y + R3 * 1.6, Black, 0.0, 12);
               Cylinder (B, Head, R3 * 1.1, R3 * 1.1, 0.0, Head.Y + R3 * 0.7, Head.Y + R3 * 0.8, Black, 0.0, 12);
            end;
         elsif It.Kind = Candle then
            declare
               Wax : constant Color := Color_At (S, 0.7);
            begin
               Cylinder (B, C, R * 0.8, R * 0.8, 0.0, C.Y, C.Y + Ht, Wax, 0.0, 16);
               Flame (B, C + (0.0, Ht + 1.0, 0.0), R * 0.4);
            end;
         elsif It.Kind = Bottle then
            Lathe (B, C, Bottle_Profile, R, Ht, Color_At (S, 0.8));
         elsif It.Kind = Salt_Shaker then
            Lathe (B, C, Shaker_Profile, R, Ht, Color_At (S, 0.7));
         elsif It.Kind = Cupcake then
            Lathe (B, C, Cup_Profile, R, Ht, Color_At (S, 0.95));
            Pull := 1.0;
            Dome (B, C + (0.0, Ht * 0.55, 0.0), R, R, 0.0, Ht * 0.45, White, 1.0);
         elsif It.Kind = Cake then
            --  two tiers, cream round their edges, candles alight on top
            declare
               Icing : constant Color := Color_At (S, 0.5);
               Sponge : constant Color := Color_At (S, 0.97);
               Cream : constant Color := (0.98, 0.96, 0.92, 1.0);
               Top : constant Float := C.Y + Ht;
            begin
               Lathe (B, C, ((1.0, 0.0), (1.0, 0.55), (0.0, 0.55)), R, Ht, Sponge);
               Lathe (B, C, ((0.62, 0.55), (0.62, 1.0), (0.0, 1.0)), R, Ht, Icing);
               for K in 0 .. 23 loop
                  declare
                     A : constant Float := 2.0 * Pi * Float (K) / 24.0;
                  begin
                     Sphere (B, C + (R * Cos (A), Ht * 0.55, R * Sin (A)), R * 0.09, Cream, 6);
                     if K mod 2 = 0 then
                        Sphere (B, C + (R * 0.62 * Cos (A), Ht, R * 0.62 * Sin (A)), R * 0.07, Cream, 6);
                     end if;
                  end;
               end loop;
               for K in 0 .. 5 loop
                  declare
                     A : constant Float := 2.0 * Pi * Float (K) / 6.0 + 0.3;
                     P : constant V3 := C + (R * 0.38 * Cos (A), 0.0, R * 0.38 * Sin (A));
                     Hue : constant Float := Float (K) * 1.1;
                  begin
                     Cylinder (B, P, R * 0.035, R * 0.035, 0.0, Top, Top + Ht * 0.3,
                               (0.6 + 0.4 * Sin (Hue), 0.6 + 0.4 * Sin (Hue + 2.1), 0.6 + 0.4 * Sin (Hue + 4.2), 1.0),
                               0.0, 6);
                     Flame (B, (P.X, Top + Ht * 0.3 + 0.5, P.Z), R * 0.05);
                  end;
               end loop;
            end;
         elsif It.Kind = Mug then
            declare
               Rim : constant Color := Color_At (S, 0.97);
            begin
               Pull := 0.97;
               Cylinder (B, C, S.RX, S.RX, 0.0, C.Y, C.Y + Ht, White, 1.0);
               Block (B, C, Dir3 (S.A), S.RX + 4.0, Ht * 0.55, 0.0, 4.0, Ht * 0.28, 2.5, Rim);
            end;
         elsif It.Kind = Pumpkin then
            Pull := 1.0;
            Dome (B, C, S.RX, (if S.Kind = Circle then S.RX else S.RY), S.A, Ht, White, 1.0);
            Cylinder (B, C, R * 0.1, R * 0.1, 0.0, C.Y + Ht * 0.9, C.Y + Ht * 1.15, (0.3, 0.4, 0.15, 1.0), 0.0, 6);
         elsif It.Kind = Spire then
            Pull := 0.5;
            Cylinder (B, C, R, R, 0.0, C.Y, C.Y + Ht, White, 1.0, Taper => 0.0);
         elsif Look_Of (It.Kind) = Ball then
            Sphere (B, C + (0.0, S.RX, 0.0), S.RX, (0.85, 0.85, 0.85, 1.0), 16);
            Pull := 1.0;
            Dome (B, C + (0.0, S.RX * 1.02, 0.0), S.RX * 0.999, S.RX * 0.999, 0.0, S.RX * 0.999, White, 1.0, 16);
         elsif Look_Of (It.Kind) = Rounded and then S.Kind /= Tracks.Box then
            Pull := 1.0;
            Dome (B, C, S.RX, (if S.Kind = Circle then S.RX else S.RY), S.A, Ht, White, 1.0);
         else
            case S.Kind is
               when Circle =>
                  Pull := 0.95;
                  Cylinder (B, C, S.RX, S.RX, 0.0, C.Y, C.Y + Ht, White, 1.0,
                            Taper => (if It.Kind = Party_Hat then 0.0 else 1.0));
               when Ellipse =>
                  Cylinder (B, C, S.RX, S.RY, S.A, C.Y, C.Y + Ht, White, 1.0);
               when Tracks.Box =>
                  declare
                     Fwd : constant V3 := Dir3 (S.A);
                  begin
                     --  the sides first, their picture pulled in from the edge; then the top
                     Block (B, C, Fwd, 0.0, Ht / 2.0, 0.0, S.RX, Ht / 2.0, S.RY, Side, 1.0);
                     Pull := 1.0;
                     Block (B, C, Fwd, 0.0, Ht + 0.05, 0.0, S.RX, 0.05, S.RY, White, 1.0);
                  end;
            end case;
         end if;
         Pull := 1.0;
      elsif It.Mat = Ramp and then It.S.Kind = Tracks.Box then
         --  a wedge across the road, rising the way the cars go
         declare
            Along : constant Geom.Vec := Tracks.Get (Tracks.Nearest (S.C)).T;
            Turn : constant Float := (if Along.X * Cos (S.A) + Along.Y * Sin (S.A) < 0.0 then S.A + Pi else S.A);
            Fwd : constant V3 := Dir3 (Turn);
            Sd  : constant V3 := Side_Of (Fwd);
            Rise : constant V3 := (0.0, 10.0, 0.0);
            A0 : constant V3 := C - S.RX * Fwd;
            A1 : constant V3 := C + S.RX * Fwd;
            Edge : constant Color := (0.62, 0.45, 0.28, 1.0);
         begin
            Quad (B, A0 - S.RY * Sd, A0 + S.RY * Sd, A1 + S.RY * Sd + Rise, A1 - S.RY * Sd + Rise, White, 1.0);
            Quad (B, A1 - S.RY * Sd, A1 + S.RY * Sd, A1 + S.RY * Sd + Rise, A1 - S.RY * Sd + Rise, Edge);
            Tri (B, A0 + S.RY * Sd, A1 + S.RY * Sd, A1 + S.RY * Sd + Rise, Shade (Edge, 0.9));
            Tri (B, A0 - S.RY * Sd, A1 - S.RY * Sd, A1 - S.RY * Sd + Rise, Shade (Edge, 0.9));
         end;
      end if;
   end Item;

   ---------------------------------------------------------------------------
   --  The vehicles
   ---------------------------------------------------------------------------

   procedure Vehicle (B, Glow : in out Buffer; O : V3; H : Float; Paint : Color; Alpha : Float := 1.0) is
      Fwd : constant V3 := Dir3 (H);
      function K (C : Color) return Color is ((C.R, C.G, C.B, C.A * Alpha));
      P : constant Color := K (Paint);
      Dark : constant Color := K (Shade (Paint, 0.6));
      Ty : constant Color := K (Tyre);
      Gl : constant Color := K (Glass);
      La : constant Color := K (Lamp);
      Me : constant Color := K (Metal);

      procedure Wheel (Along, Across, R, W : Float) is
         Sd : constant V3 := Side_Of (Fwd);
      begin
         Barrel (B, O + Along * Fwd + Across * Sd + (0.0, R, 0.0), Sd, R, W, Ty, 10);
      end Wheel;
   begin
      case Vehicle is
         when Car | Rover =>
            Block (B, O, Fwd, 0.0, 5.0, 0.0, 12.0, 2.8, 6.0, P);
            Block (B, O, Fwd, -2.0, 9.6, 0.0, 6.0, 1.8, 5.0, Gl);
            Block (B, O, Fwd, -2.0, 11.6, 0.0, 6.2, 0.4, 5.2, P);
            Block (B, O, Fwd, 11.6, 5.6, 3.8, 0.6, 1.0, 1.4, La);
            Block (B, O, Fwd, 11.6, 5.6, -3.8, 0.6, 1.0, 1.4, La);
            for Side in -1 .. 1 loop
               if Side /= 0 then
                  Wheel (7.5, Float (Side) * 6.2, 3.0, 1.4);
                  Wheel (-7.5, Float (Side) * 6.2, 3.0, 1.4);
                  if Vehicle = Rover then
                     Wheel (0.0, Float (Side) * 6.2, 3.0, 1.4);
                  end if;
               end if;
            end loop;
            if Vehicle = Rover then
               Barrel (B, O + (-4.0) * Fwd + (0.0, 14.0, 0.0), Side_Of (Fwd), 0.4, 4.0, Me, 6);
            end if;
         when Kart =>
            Block (B, O, Fwd, 0.0, 2.5, 0.0, 11.0, 1.2, 5.0, P);
            Block (B, O, Fwd, -6.0, 5.5, 0.0, 2.0, 3.0, 3.0, Dark);
            Sphere (B, O + (-2.0) * Fwd + (0.0, 9.0, 0.0), 3.0, K ((0.95, 0.95, 0.95, 1.0)), 8);
            Wheel (7.5, 6.0, 2.5, 1.5);
            Wheel (7.5, -6.0, 2.5, 1.5);
            Wheel (-7.5, 6.0, 2.8, 2.0);
            Wheel (-7.5, -6.0, 2.8, 2.0);
         when Monster_Truck =>
            Block (B, O, Fwd, 0.0, 12.0, 0.0, 12.0, 3.0, 6.5, P);
            Block (B, O, Fwd, -2.0, 17.0, 0.0, 6.0, 2.0, 5.5, Gl);
            Block (B, O, Fwd, -2.0, 19.2, 0.0, 6.2, 0.4, 5.6, P);
            Wheel (8.0, 8.0, 6.0, 2.8);
            Wheel (8.0, -8.0, 6.0, 2.8);
            Wheel (-8.0, 8.0, 6.0, 2.8);
            Wheel (-8.0, -8.0, 6.0, 2.8);
         when Tank =>
            Block (B, O, Fwd, 0.0, 3.5, 5.5, 12.5, 3.5, 2.2, Ty);
            Block (B, O, Fwd, 0.0, 3.5, -5.5, 12.5, 3.5, 2.2, Ty);
            Block (B, O, Fwd, 0.0, 6.5, 0.0, 11.0, 2.5, 4.0, P);
            Cylinder (B, O + (-1.0) * Fwd, 4.5, 4.5, 0.0, O.Y + 9.0, O.Y + 12.5, Dark, 0.0, 12);
            Barrel (B, O + 9.0 * Fwd + (0.0, 10.8, 0.0), Fwd, 1.0, 8.0, Dark, 8);
         when Boat =>
            Block (B, O, Fwd, -2.0, 3.0, 0.0, 10.0, 3.0, 6.0, P);
            Block (B, O, Fwd, 10.0, 3.5, 0.0, 3.0, 2.5, 3.5, P);
            Block (B, O, Fwd, -1.0, 7.5, 0.0, 3.0, 1.5, 4.5, Gl);
            Block (B, O, Fwd, -11.0, 4.0, 0.0, 1.5, 3.0, 2.0, Ty);
         when Plane =>
            if Theme = Halloween then
               Barrel (B, O + (0.0, 4.0, 0.0), Fwd, 0.8, 13.0, K ((0.45, 0.30, 0.15, 1.0)), 6);
               Cylinder (B, O + (-13.0) * Fwd, 3.0, 3.0, 0.0, O.Y + 1.0, O.Y + 7.0, K ((0.70, 0.55, 0.20, 1.0)), 0.0, 8);
               Sphere (B, O + (-2.0) * Fwd + (0.0, 9.0, 0.0), 3.0, K ((0.15, 0.10, 0.20, 1.0)), 8);
               Cylinder (B, O + (-2.0) * Fwd, 3.5, 3.5, 0.0, O.Y + 11.0, O.Y + 12.0, K ((0.10, 0.08, 0.12, 1.0)), 0.0, 10);
               Cylinder (B, O + (-2.0) * Fwd, 1.5, 1.5, 0.0, O.Y + 12.0, O.Y + 18.0, K ((0.10, 0.08, 0.12, 1.0)), 0.0, 8,
                         Taper => 0.0);
            else
               Barrel (B, O + (0.0, 4.0, 0.0), Fwd, 3.2, 11.0, P, 10);
               Block (B, O, Fwd, 2.0, 4.0, 0.0, 3.5, 0.5, 17.0, Dark);
               Block (B, O, Fwd, 2.0, 9.0, 0.0, 3.5, 0.5, 17.0, Dark);
               Block (B, O, Fwd, -10.0, 5.0, 0.0, 2.0, 0.4, 6.0, Dark);
               Block (B, O, Fwd, -10.0, 8.0, 0.0, 2.0, 3.5, 0.4, Dark);
               Block (B, O, Fwd, 11.5, 4.0, 0.0, 0.4, 5.0, 0.6, Me);   --  the propeller
            end if;
         when Bike_Kind | Snowmobile =>
            if Vehicle = Snowmobile then
               Block (B, O, Fwd, 0.0, 1.0, 4.0, 11.0, 0.6, 1.0, Me);
               Block (B, O, Fwd, 0.0, 1.0, -4.0, 11.0, 0.6, 1.0, Me);
               Block (B, O, Fwd, 0.0, 5.0, 0.0, 9.0, 3.0, 4.0, P);
            else
               Wheel (8.0, 0.0, 3.5, 1.0);
               Wheel (-8.0, 0.0, 3.5, 1.0);
               Block (B, O, Fwd, 0.0, 6.5, 0.0, 7.0, 2.0, 1.8, P);
            end if;
            Block (B, O, Fwd, -2.0, 11.0, 0.0, 2.0, 3.5, 2.5, Dark);   --  the rider
            Sphere (B, O + (-1.0) * Fwd + (0.0, 16.0, 0.0), 2.6, P, 8);
         when Hovercraft =>
            if Theme = Alien then
               Dome (B, O + (0.0, 4.0, 0.0), 12.0, 12.0, 0.0, 3.0, Me, 0.0, 16);
               Dome (B, O + (0.0, 4.0, 0.0), 12.0, 12.0, 0.0, -2.5, K (Shade (Metal, 0.7)), 0.0, 16);
               Dome (B, O + (0.0, 6.0, 0.0), 5.0, 5.0, 0.0, 5.0, K ((0.6, 0.9, 0.7, 1.0)), 0.0, 12);
               Disc (Glow, O + (0.0, 1.5, 0.0), 10.0, 10.0, 0.0, (Paint.R, Paint.G, Paint.B, 0.6 * Alpha));
            else
               Cylinder (B, O, 12.0, 7.0, H, O.Y + 1.0, O.Y + 4.0, Ty, 0.0, 16);
               Block (B, O, Fwd, 0.0, 6.0, 0.0, 10.0, 2.0, 5.5, P);
               Block (B, O, Fwd, 0.0, 9.0, 0.0, 4.0, 1.5, 4.0, Gl);
               Cylinder (B, O + (-10.0) * Fwd, 3.0, 3.0, 0.0, O.Y + 6.0, O.Y + 13.0, Dark, 0.0, 10);
            end if;
         when Submarine =>
            Barrel (B, O + (0.0, 5.0, 0.0), Fwd, 4.5, 10.0, P, 12);
            Sphere (B, O + 10.0 * Fwd + (0.0, 5.0, 0.0), 4.5, P, 10);
            Block (B, O, Fwd, 1.0, 11.0, 0.0, 3.0, 2.5, 1.5, Dark);
            Block (B, O, Fwd, -11.0, 5.0, 0.0, 1.0, 4.0, 0.4, Dark);
      end case;
   end Vehicle;

   function Eye_Height return Float is
     (case Vehicle is
         when Monster_Truck => 18.5,
         when Kart => 9.0,
         when Bike_Kind | Snowmobile => 15.0,
         when Tank => 13.0,
         when Plane => (if Theme = Halloween then 11.0 else 9.0),
         when Boat | Hovercraft => 10.0,
         when Submarine => 12.5,
         when others => 10.0);

   procedure Cockpit (B : in out Buffer; O : V3; H : Float; Paint : Color) is
      Fwd : constant V3 := Dir3 (H);
      Sd : constant V3 := Side_Of (Fwd);
      Lift : constant Float := Eye_Height - 10.0;   --  for the cars: all of it raised with the driver
      Dash : constant Color := (0.12, 0.12, 0.13, 1.0);
      E : constant V3 := O + (0.0, Lift, 0.0);
   begin
      case Vehicle is
         when Bike_Kind | Snowmobile =>
            --  the handlebars and their grips, low in the view; the tank between the knees
            Block (B, O, Fwd, 4.0, 9.0, 0.0, 3.0, 1.2, 1.6, Paint);
            Barrel (B, O + 4.6 * Fwd + (0.0, 12.0, 0.0), Sd, 0.3, 3.6, Dash, 6);
            Block (B, O, Fwd, 4.4, 12.0, 3.4, 0.5, 0.5, 0.6, (0.3, 0.3, 0.3, 1.0));
            Block (B, O, Fwd, 4.4, 12.0, -3.4, 0.5, 0.5, 0.6, (0.3, 0.3, 0.3, 1.0));
            Block (B, O, Fwd, 5.4, 12.6, 0.0, 0.4, 0.6, 1.0, Dash);   --  the speedometer
         when Plane =>
            if Theme = Halloween then
               Barrel (B, O + (0.0, 4.0, 0.0) + 7.0 * Fwd, Fwd, 0.8, 7.0, (0.45, 0.30, 0.15, 1.0), 6);
            else
               Barrel (B, O + (0.0, 4.0, 0.0) + 7.0 * Fwd, Fwd, 3.2, 5.0, Paint, 10);
               Block (B, O, Fwd, 3.0, 9.0, 0.0, 3.5, 0.4, 17.0, Shade (Paint, 0.6));
               Block (B, O, Fwd, 12.5, 4.0, 0.0, 0.3, 5.0, 0.6, (0.55, 0.57, 0.60, 1.0));
            end if;
         when others =>
            --  the bonnet low ahead, the top of the dashboard, the windscreen's pillars, the wheel
            Block (B, E, Fwd, 8.5, 5.4, 0.0, 4.5, 0.6, 5.8, Paint);
            Block (B, E, Fwd, 3.4, 6.8, 0.0, 0.8, 0.9, 5.6, Dash);
            Block (B, E, Fwd, 4.6, 10.0, 5.4, 0.25, 3.2, 0.25, Shade (Paint, 0.8));
            Block (B, E, Fwd, 4.6, 10.0, -5.4, 0.25, 3.2, 0.25, Shade (Paint, 0.8));
            Block (B, E, Fwd, 2.0, 13.4, 0.0, 2.6, 0.2, 5.6, Shade (Paint, 0.8));
            for K in 0 .. 11 loop
               declare
                  A : constant Float := 2.0 * Pi * Float (K) / 12.0;
               begin
                  Block (B, E, Fwd, 2.3, 7.4 + 1.1 * Sin (A), -2.4 + 1.1 * Cos (A), 0.12, 0.3, 0.3, Dash);
               end;
            end loop;
      end case;
   end Cockpit;

   ---------------------------------------------------------------------------
   --  The things that cross the road
   ---------------------------------------------------------------------------

   --  A body along Fwd, a head in front, legs under it
   procedure Critter (B : in out Buffer; O, Fwd : V3; R : Float; Fur, Head : Color; Legs : Natural;
                      Leg_Color : Color; Clock : Float)
   is
      Sd : constant V3 := Side_Of (Fwd);
      Hip : constant Float := R * 0.6;
      Step : constant Float := Sin (Clock * 12.0) * R * 0.15;
   begin
      Barrel (B, O + (0.0, Hip + R * 0.45, 0.0), Fwd, R * 0.45, R * 0.55, Fur, 10);
      Sphere (B, O + (R * 0.75) * Fwd + (0.0, Hip + R * 0.75, 0.0), R * 0.35, Head, 10);
      Sphere (B, O + (R * 1.0) * Fwd + (R * 0.15) * Sd + (0.0, Hip + R * 0.85, 0.0), R * 0.07, Black, 6);
      Sphere (B, O + (R * 1.0) * Fwd - (R * 0.15) * Sd + (0.0, Hip + R * 0.85, 0.0), R * 0.07, Black, 6);
      if Legs = 2 then
         Block (B, O, Fwd, Step, Hip / 2.0, R * 0.2, R * 0.06, Hip / 2.0, R * 0.06, Leg_Color);
         Block (B, O, Fwd, -Step, Hip / 2.0, -R * 0.2, R * 0.06, Hip / 2.0, R * 0.06, Leg_Color);
      elsif Legs = 4 then
         for F in -1 .. 1 loop
            if F /= 0 then
               Block (B, O, Fwd, Float (F) * R * 0.35 + Step, Hip / 2.0, R * 0.28, R * 0.09, Hip / 2.0, R * 0.09, Leg_Color);
               Block (B, O, Fwd, Float (F) * R * 0.35 - Step, Hip / 2.0, -R * 0.28, R * 0.09, Hip / 2.0, R * 0.09, Leg_Color);
            end if;
         end loop;
      end if;
   end Critter;

   procedure Wings (B : in out Buffer; O, Fwd : V3; Span, Up : Float; C : Color; Clock : Float) is
      Sd : constant V3 := Side_Of (Fwd);
      Flap : constant Float := Sin (Clock * 14.0) * Span * 0.5;
      Root_L : constant V3 := O + (0.0, Up, 0.0) + (Span * 0.15) * Sd;
      Root_R : constant V3 := O + (0.0, Up, 0.0) - (Span * 0.15) * Sd;
   begin
      Quad (B, Root_L + (Span * 0.25) * Fwd, Root_L + (-Span * 0.25) * Fwd,
            Root_L + Span * Sd + (0.0, Flap, 0.0) + (-Span * 0.1) * Fwd, Root_L + Span * Sd + (0.0, Flap, 0.0), C);
      Quad (B, Root_R + (Span * 0.25) * Fwd, Root_R + (-Span * 0.25) * Fwd,
            Root_R - Span * Sd + (0.0, Flap, 0.0) + (-Span * 0.1) * Fwd, Root_R - Span * Sd + (0.0, Flap, 0.0), C);
   end Wings;

   procedure Mover (B, Glow : in out Buffer; M : Tracks.Mover; P : Geom.Vec; Heading, Lift, Ground_Y,
                    Clock : Float)
   is
      O : constant V3 := (P.X, Ground_Y + Lift, P.Y);
      Fwd : constant V3 := Dir3 (Heading);
      Sd : constant V3 := Side_Of (Fwd);
      R : constant Float := M.Radius;
      Hue : constant Float := Float (Mover_Kind'Pos (M.Kind)) * 0.37;
      Bright : constant Color := (0.5 + 0.4 * Sin (Hue), 0.5 + 0.4 * Sin (Hue + 2.1), 0.5 + 0.4 * Sin (Hue + 4.2), 1.0);
   begin
      case M.Kind is
         when Marble =>
            Sphere (B, O + (0.0, R, 0.0), R, (0.30, 0.55, 0.95, 1.0), 16);
            Sphere (Glow, O + (0.0, R, 0.0), R * 1.04, (0.8, 0.9, 1.0, 0.25), 16);
         when Tennis_Ball =>
            Sphere (B, O + (0.0, R, 0.0), R, (0.80, 0.90, 0.20, 1.0), 16);
         when Pool_Ball | Bouncy_Ball =>
            Sphere (B, O + (0.0, R, 0.0), R, Bright, 16);
            Sphere (B, O + (0.0, R, 0.0) + (R * 0.92) * Fwd, R * 0.35, White, 8);
         when Rolling_Bauble =>
            Sphere (B, O + (0.0, R, 0.0), R, (0.85, 0.12, 0.15, 1.0), 16);
            Cylinder (B, O, R * 0.25, R * 0.25, 0.0, O.Y + 1.9 * R, O.Y + 2.15 * R, (0.9, 0.75, 0.3, 1.0), 0.0, 8);
         when Puck =>
            Cylinder (B, O, R, R, 0.0, O.Y, O.Y + 5.0, (0.08, 0.08, 0.08, 1.0), 0.0, 16);
         when Frog =>
            Dome (B, O, R, R * 0.85, Heading, R * 0.8, (0.25, 0.65, 0.20, 1.0), 0.0, 14);
            Sphere (B, O + (R * 0.5) * Fwd + (R * 0.35) * Sd + (0.0, R * 0.75, 0.0), R * 0.22, White, 8);
            Sphere (B, O + (R * 0.5) * Fwd - (R * 0.35) * Sd + (0.0, R * 0.75, 0.0), R * 0.22, White, 8);
            Sphere (B, O + (R * 0.62) * Fwd + (R * 0.35) * Sd + (0.0, R * 0.8, 0.0), R * 0.11, Black, 6);
            Sphere (B, O + (R * 0.62) * Fwd - (R * 0.35) * Sd + (0.0, R * 0.8, 0.0), R * 0.11, Black, 6);
         when Drifting_Duck =>
            Dome (B, O, R, R * 0.75, Heading, R * 0.8, (1.0, 0.85, 0.15, 1.0), 0.0, 14);
            Sphere (B, O + (R * 0.5) * Fwd + (0.0, R * 1.0, 0.0), R * 0.42, (1.0, 0.85, 0.15, 1.0), 10);
            Block (B, O, Fwd, R * 0.95, R * 0.95, 0.0, R * 0.2, R * 0.08, R * 0.15, Orange);
         when Paper_Plane =>
            Tri (B, O + (R * 1.2) * Fwd + (0.0, R * 0.3, 0.0), O + (-R) * Fwd + (R * 0.9) * Sd + (0.0, R * 0.4, 0.0),
                 O + (-R) * Fwd + (0.0, R * 0.2, 0.0), White);
            Tri (B, O + (R * 1.2) * Fwd + (0.0, R * 0.3, 0.0), O + (-R) * Fwd - (R * 0.9) * Sd + (0.0, R * 0.4, 0.0),
                 O + (-R) * Fwd + (0.0, R * 0.2, 0.0), Shade (White, 0.92));
            Tri (B, O + (R * 1.2) * Fwd + (0.0, R * 0.3, 0.0), O + (-R) * Fwd + (0.0, R * 0.2, 0.0),
                 O + (-R) * Fwd + (0.0, -R * 0.1, 0.0), Shade (White, 0.85));
         when Bird | Bat =>
            declare
               Col : constant Color := (if M.Kind = Bat then (0.12, 0.10, 0.14, 1.0) else (0.35, 0.45, 0.75, 1.0));
            begin
               Barrel (B, O + (0.0, R * 0.5, 0.0), Fwd, R * 0.28, R * 0.5, Col, 8);
               Sphere (B, O + (R * 0.55) * Fwd + (0.0, R * 0.6, 0.0), R * 0.25, Col, 8);
               if M.Kind = Bird then
                  Block (B, O, Fwd, R * 0.85, R * 0.58, 0.0, R * 0.15, R * 0.05, R * 0.06, Orange);
               end if;
               Wings (B, O, Fwd, R * 1.1, R * 0.55, Shade (Col, 0.8), Clock);
            end;
         when Chicken =>
            Critter (B, O, Fwd, R, (0.96, 0.94, 0.88, 1.0), (0.96, 0.94, 0.88, 1.0), 2, Orange, Clock);
            Block (B, O, Fwd, R * 0.75, R * 1.5, 0.0, R * 0.12, R * 0.12, R * 0.04, (0.9, 0.15, 0.1, 1.0));
            Block (B, O, Fwd, R * 1.1, R * 1.32, 0.0, R * 0.12, R * 0.05, R * 0.06, Orange);
         when Mouse =>
            Critter (B, O, Fwd, R, (0.6, 0.58, 0.58, 1.0), (0.6, 0.58, 0.58, 1.0), 4, (0.9, 0.7, 0.7, 1.0), Clock);
            Cylinder (B, O + (R * 0.7) * Fwd + (R * 0.28) * Sd, R * 0.18, R * 0.18, 0.0, O.Y + R * 1.05, O.Y + R * 1.12,
                      (0.9, 0.7, 0.7, 1.0), 0.0, 10);
            Cylinder (B, O + (R * 0.7) * Fwd - (R * 0.28) * Sd, R * 0.18, R * 0.18, 0.0, O.Y + R * 1.05, O.Y + R * 1.12,
                      (0.9, 0.7, 0.7, 1.0), 0.0, 10);
            Barrel (B, O + (-R * 1.1) * Fwd + (0.0, R * 0.7, 0.0), Fwd, R * 0.04, R * 0.5, (0.9, 0.7, 0.7, 1.0), 4);
         when Bunny =>
            Critter (B, O, Fwd, R, (0.48, 0.30, 0.18, 1.0), (0.48, 0.30, 0.18, 1.0), 4, (0.48, 0.30, 0.18, 1.0), Clock);
            Block (B, O, Fwd, R * 0.65, R * 1.45, R * 0.12, R * 0.05, R * 0.35, R * 0.08, (0.48, 0.30, 0.18, 1.0));
            Block (B, O, Fwd, R * 0.65, R * 1.45, -R * 0.12, R * 0.05, R * 0.35, R * 0.08, (0.48, 0.30, 0.18, 1.0));
            Sphere (B, O + (-R * 0.6) * Fwd + (0.0, R * 1.0, 0.0), R * 0.18, White, 8);
         when Polar_Bear =>
            Critter (B, O, Fwd, R, (0.94, 0.94, 0.90, 1.0), (0.94, 0.94, 0.90, 1.0), 4, (0.90, 0.90, 0.86, 1.0), Clock);
            Sphere (B, O + (R * 1.08) * Fwd + (0.0, R * 1.3, 0.0), R * 0.08, Black, 6);
         when Penguin =>
            Dome (B, O, R * 0.6, R * 0.55, Heading, R * 1.9, (0.08, 0.08, 0.10, 1.0), 0.0, 14);
            Dome (B, O + (R * 0.12) * Fwd, R * 0.5, R * 0.42, Heading, R * 1.7, White, 0.0, 14);
            Block (B, O, Fwd, R * 0.62, R * 1.45, 0.0, R * 0.18, R * 0.06, R * 0.08, Orange);
            Block (B, O, Fwd, 0.0, R * 0.9, R * 0.62, R * 0.2, R * 0.4, R * 0.05, (0.08, 0.08, 0.10, 1.0));
            Block (B, O, Fwd, 0.0, R * 0.9, -R * 0.62, R * 0.2, R * 0.4, R * 0.05, (0.08, 0.08, 0.10, 1.0));
            Block (B, O, Fwd, R * 0.2, R * 0.05, R * 0.2, R * 0.2, R * 0.05, R * 0.1, Orange);
            Block (B, O, Fwd, R * 0.2, R * 0.05, -R * 0.2, R * 0.2, R * 0.05, R * 0.1, Orange);
         when Crab =>
            Dome (B, O + (0.0, R * 0.3, 0.0), R, R * 0.75, Heading, R * 0.5, (0.85, 0.25, 0.15, 1.0), 0.0, 14);
            for S in -1 .. 1 loop
               if S /= 0 then
                  Sphere (B, O + (R * 0.9) * Fwd + (Float (S) * R * 0.7) * Sd + (0.0, R * 0.45, 0.0), R * 0.25,
                          (0.85, 0.25, 0.15, 1.0), 8);
                  for L in 0 .. 2 loop
                     Block (B, O, Fwd, R * (0.3 - 0.3 * Float (L)), R * 0.2, Float (S) * R * 0.95, R * 0.05, R * 0.2,
                            R * 0.25, (0.75, 0.2, 0.12, 1.0));
                  end loop;
               end if;
            end loop;
         when Fish =>
            Dome (B, O + (0.0, R * 0.6, 0.0), R, R * 0.35, Heading, R * 0.45, Orange, 0.0, 12);
            Dome (B, O + (0.0, R * 0.6, 0.0), R, R * 0.35, Heading, -R * 0.45, Orange, 0.0, 12);
            Block (B, O, Fwd, -R * 1.1, R * 0.6, 0.0, R * 0.2, R * 0.4, R * 0.05,
                   (1.0, 0.75, 0.3, 1.0));
         when Robot =>
            Block (B, O, Fwd, 0.0, R * 0.9, 0.0, R * 0.45, R * 0.5, R * 0.55, Metal);
            Block (B, O, Fwd, 0.0, R * 1.65, 0.0, R * 0.32, R * 0.25, R * 0.35, Shade (Metal, 1.2));
            Block (B, O, Fwd, R * 0.33, R * 1.7, R * 0.15, R * 0.02, R * 0.06, R * 0.07, (1.0, 0.2, 0.1, 1.0));
            Block (B, O, Fwd, R * 0.33, R * 1.7, -R * 0.15, R * 0.02, R * 0.06, R * 0.07, (1.0, 0.2, 0.1, 1.0));
            Barrel (B, O + (0.0, R * 0.25, 0.0) + (R * 0.4) * Sd, Fwd, R * 0.25, R * 0.4, Tyre, 8);
            Barrel (B, O + (0.0, R * 0.25, 0.0) - (R * 0.4) * Sd, Fwd, R * 0.25, R * 0.4, Tyre, 8);
            Cylinder (B, O, R * 0.03, R * 0.03, 0.0, O.Y + R * 1.9, O.Y + R * 2.3, Metal, 0.0, 4);
         when RC_Car =>
            Block (B, O, Fwd, 0.0, R * 0.35, 0.0, R, R * 0.22, R * 0.5, Bright);
            Block (B, O, Fwd, -R * 0.1, R * 0.65, 0.0, R * 0.45, R * 0.15, R * 0.4, Glass);
            for F in -1 .. 1 loop
               if F /= 0 then
                  Barrel (B, O + (Float (F) * R * 0.6) * Fwd + (R * 0.5) * Sd + (0.0, R * 0.25, 0.0), Sd, R * 0.25,
                          R * 0.1, Tyre, 8);
                  Barrel (B, O + (Float (F) * R * 0.6) * Fwd - (R * 0.5) * Sd + (0.0, R * 0.25, 0.0), Sd, R * 0.25,
                          R * 0.1, Tyre, 8);
               end if;
            end loop;
            Cylinder (B, O + (-R * 0.7) * Fwd, R * 0.02, R * 0.02, 0.0, O.Y + R * 0.5, O.Y + R * 1.4, Black, 0.0, 4);
         when Astronaut =>
            Block (B, O, Fwd, 0.0, R * 0.9, 0.0, R * 0.3, R * 0.45, R * 0.4, (0.95, 0.95, 0.95, 1.0));
            Block (B, O, Fwd, -R * 0.38, R * 0.95, 0.0, R * 0.12, R * 0.35, R * 0.32, Metal);
            Sphere (B, O + (0.0, R * 1.65, 0.0), R * 0.33, (0.95, 0.95, 0.95, 1.0), 10);
            Sphere (B, O + (R * 0.14) * Fwd + (0.0, R * 1.65, 0.0), R * 0.24, (0.85, 0.65, 0.2, 1.0), 10);
            Block (B, O, Fwd, 0.0, R * 0.22, R * 0.18, R * 0.12, R * 0.22, R * 0.12, (0.95, 0.95, 0.95, 1.0));
            Block (B, O, Fwd, 0.0, R * 0.22, -R * 0.18, R * 0.12, R * 0.22, R * 0.12, (0.95, 0.95, 0.95, 1.0));
         when Knight_Hop =>
            Knight_Model (B, O, R * 0.7, R * 2.6, Heading, (0.92, 0.88, 0.78, 1.0));
         when Blob =>
            Dome (Glow, O, R, R, 0.0, R * (0.8 + 0.1 * Sin (Clock * 5.0)), (0.35, 0.9, 0.35, 0.65), 0.0, 14);
            Sphere (B, O + (R * 0.55) * Fwd + (R * 0.25) * Sd + (0.0, R * 0.6, 0.0), R * 0.12, Black, 6);
            Sphere (B, O + (R * 0.55) * Fwd - (R * 0.25) * Sd + (0.0, R * 0.6, 0.0), R * 0.12, Black, 6);
         when Ghost =>
            declare
               Top : constant V3 := O + (0.0, 30.0 + 4.0 * Sin (Clock * 2.0), 0.0);
            begin
               Dome (Glow, Top, R, R, 0.0, R * 1.1, (0.95, 0.95, 1.0, 0.6), 0.0, 14);
               Cylinder (Glow, Top + (0.0, -R * 0.9, 0.0), R, R, 0.0, Top.Y - R * 0.9, Top.Y, (0.95, 0.95, 1.0, 0.45),
                         0.0, 14, Cap => False);
               Sphere (B, Top + (R * 0.85) * Fwd + (R * 0.3) * Sd + (0.0, R * 0.4, 0.0), R * 0.14, Black, 6);
               Sphere (B, Top + (R * 0.85) * Fwd - (R * 0.3) * Sd + (0.0, R * 0.4, 0.0), R * 0.14, Black, 6);
            end;
         when Sleigh =>
            declare
               Red : constant Color := (0.8, 0.1, 0.1, 1.0);
               Gold : constant Color := (0.9, 0.75, 0.25, 1.0);
               Deer : constant Color := (0.55, 0.36, 0.2, 1.0);
            begin
               Block (B, O, Fwd, 0.0, R * 0.55, 0.0, R * 0.8, R * 0.3, R * 0.45, Red);
               Block (B, O, Fwd, -R * 0.6, R * 0.95, 0.0, R * 0.2, R * 0.25, R * 0.45, Red);
               Block (B, O, Fwd, 0.0, R * 0.1, R * 0.4, R * 0.95, R * 0.05, R * 0.04, Gold);
               Block (B, O, Fwd, 0.0, R * 0.1, -R * 0.4, R * 0.95, R * 0.05, R * 0.04, Gold);
               Sphere (B, O + (0.0, R * 1.05, 0.0), R * 0.3, Red, 10);          --  Santa
               Sphere (B, O + (0.0, R * 1.45, 0.0), R * 0.18, (0.95, 0.8, 0.7, 1.0), 8);
               Sphere (B, O + (R * 0.1) * Fwd + (0.0, R * 1.32, 0.0), R * 0.16, White, 8);
               for K in 1 .. 2 loop
                  declare
                     D : constant V3 := O + (R * (1.0 + 1.1 * Float (K))) * Fwd;
                  begin
                     Critter (B, D, Fwd, R * 0.7, Deer, Deer, 4, Shade (Deer, 0.7), Clock + Float (K));
                     Block (B, D, Fwd, R * 0.5, R * 1.25, R * 0.15, R * 0.15, R * 0.2, R * 0.02, Shade (Deer, 0.6));
                     Block (B, D, Fwd, R * 0.5, R * 1.25, -R * 0.15, R * 0.15, R * 0.2, R * 0.02, Shade (Deer, 0.6));
                  end;
               end loop;
               Sphere (B, O + (R * 3.6) * Fwd + (0.0, R * 0.9, 0.0), R * 0.08, (1.0, 0.1, 0.1, 1.0), 6);
            end;
         when Train | Circle_Train =>
            declare
               Len : constant Float := Train_Length;
               Wd : constant Float := R;
               Loco : constant Color := (0.15, 0.35, 0.20, 1.0);
               Red : constant Color := (0.80, 0.15, 0.12, 1.0);
               Front : constant Float := Len / 2.0 - 25.0;   --  the middle of the engine
            begin
               --  the engine at the front: a boiler, a cab, a chimney
               Block (B, O, Fwd, Front, 6.0, 0.0, 25.0, 3.0, Wd, Black);
               Barrel (B, O + (Front + 5.0) * Fwd + (0.0, 9.0 + Wd * 0.55, 0.0), Fwd, Wd * 0.62, 18.0, Loco, 12);
               Block (B, O, Fwd, Front - 18.0, 14.0 + Wd * 0.6, 0.0, 7.0, 8.0 + Wd * 0.6, Wd, Red);
               Block (B, O, Fwd, Front - 18.0, 23.0 + Wd * 1.2, 0.0, 8.5, 1.0, Wd * 1.1, Black);
               Cylinder (B, O + (Front + 16.0) * Fwd, Wd * 0.22, Wd * 0.22, 0.0, O.Y + 9.0 + Wd, O.Y + 20.0 + Wd * 1.5,
                         Black, 0.0, 10);
               --  two carriages behind it
               for K in 0 .. 1 loop
                  declare
                     Mid : constant Float := Front - 50.0 - 46.0 * Float (K);
                     Col : constant Color := (if K = 0 then (0.2, 0.35, 0.8, 1.0) else (0.9, 0.7, 0.15, 1.0));
                  begin
                     Block (B, O, Fwd, Mid, 6.0, 0.0, 21.0, 3.0, Wd, Black);
                     Block (B, O, Fwd, Mid, 14.0 + Wd * 0.5, 0.0, 20.0, 5.0 + Wd * 0.5, Wd * 0.95, Col);
                     Block (B, O, Fwd, Mid, 18.0 + Wd * 0.5, 0.0, 16.0, 2.5, Wd * 0.97, Glass);
                     Block (B, O, Fwd, Mid, 20.0 + Wd, 0.0, 21.0, 1.0, Wd * 1.02, Shade (Col, 0.7));
                  end;
               end loop;
               --  the wheels
               for K in 0 .. 5 loop
                  declare
                     Along : constant Float := Front + 15.0 - 26.0 * Float (K);
                  begin
                     Barrel (B, O + Along * Fwd + Wd * Sd + (0.0, 4.5, 0.0), Sd, 4.5, 1.2, Red, 10);
                     Barrel (B, O + Along * Fwd - Wd * Sd + (0.0, 4.5, 0.0), Sd, 4.5, 1.2, Red, 10);
                  end;
               end loop;
            end;
      end case;
   end Mover;

end Models;
