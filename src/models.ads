--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The shapes of things, made of boxes, cylinders, balls and turned
--  profiles: the things in the way on every track, the vehicles, and the
--  creatures and toys that cross the road.  Their colours mostly come from
--  the picture the 2D game paints of the world, so a white rook is white and
--  a fir tree the green it was drawn.

with Geom;
with Lin; use Lin;
with Mesh;
with Tracks;

package Models is

   procedure Set_Picture;
   --  The world's picture was painted again: colours are looked up in it

   function Ground_At (P : Geom.Vec) return Mesh.Color;
   --  The colour of the picture at a place of the world

   function Is_Solid_Shape (It : Tracks.Item) return Boolean;
   --  Something that rises out of the floor

   procedure Item (B : in out Mesh.Buffer; It : Tracks.Item; Ground_Y, Fly_Height : Float);
   --  The thing standing on the floor at Ground_Y (or floating at Fly_Height, among planes)

   Styles : constant := 4;
   subtype Car_Style is Natural range 0 .. Styles - 1;   --  racer, beetle, van, sports car
   function Style_Name (S : Car_Style) return String is
     (case S is when 0 => "RACER", when 1 => "BEETLE", when 2 => "VAN", when others => "SPORTS CAR");

   procedure Vehicle (B, Glow : in out Mesh.Buffer; O : V3; H : Float; Paint : Mesh.Color;
                      Alpha : Float := 1.0; Style : Car_Style := 0; Number : Natural := 0);
   --  The vehicle of the track loaded, at O, pointing along H; Glow takes its see-through parts.
   --  Alpha below 1: a ghost.  Style: the body of a car; Number: on its roof (0: none)

   procedure Cockpit (B : in out Mesh.Buffer; O : V3; H : Float; Paint : Mesh.Color);
   --  What the driver sees of their own vehicle: the bonnet, the dashboard, the wheel

   function Eye_Height return Float;   --  the driver's eyes above the ground, in the vehicle loaded

   procedure Mover (B, Glow : in out Mesh.Buffer; M : Tracks.Mover; P : Geom.Vec; Heading, Lift, Ground_Y,
                    Clock : Float);
   --  A thing crossing the road, where it is now

end Models;
