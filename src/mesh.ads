--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Triangles gathered into a buffer, sent to the card, and drawn.  Every
--  vertex has a place, a normal, a colour and a share of the picture of the
--  world: that picture is laid over things from straight above, so the top
--  of a mug shows the mug drawn for the 2D game, and its sides the colours
--  of its rim.  A vertex with no normal is not lit (shadows, glows).

with Lin; use Lin;
with GL;

package Mesh is

   type Color is record
      R, G, B : Float := 1.0;
      A : Float := 1.0;
   end record;

   function Shade (C : Color; F : Float) return Color is
     ((Float'Min (1.0, C.R * F), Float'Min (1.0, C.G * F), Float'Min (1.0, C.B * F), C.A));

   --  The world picture lies over 0 .. World_W, 0 .. World_H of the floor
   World_W, World_H : Float := 1000.0;

   --  Where the picture is taken for the sides of a thing: points are pulled
   --  towards Pull_Center by Pull before being looked up (1.0: not at all)
   Pull_Center : V3;
   Pull : Float := 1.0;

   --  Everything made from now on leans: turned Pitch (nose up) about the side of Fwd,
   --  and Roll (to the right) about Fwd, round Origin.  For the vehicles in a turn or a jump
   procedure Set_Tilt (Origin, Fwd : V3; Pitch, Roll : Float);
   procedure No_Tilt;

   type Buffer is limited private;

   procedure Reset (B : in out Buffer);
   function Vertices (B : Buffer) return Natural;

   procedure Vertex (B : in out Buffer; P, N : V3; C : Color; Tex : Float := 0.0);
   procedure Vertex_UV (B : in out Buffer; P : V3; U, V : Float);   --  not lit, all picture
   procedure Vertex_Full (B : in out Buffer; P : V3; C : Color; U, V : Float);   --  not lit, coloured picture

   procedure Tri (B : in out Buffer; P1, P2, P3 : V3; C : Color; Tex : Float := 0.0; Lit : Boolean := True);
   procedure Quad (B : in out Buffer; P1, P2, P3, P4 : V3; C : Color; Tex : Float := 0.0;
                   Lit : Boolean := True);   --  corners in order round it

   --  A box in the frame of something that points along Fwd (flat, unit length):
   --  its middle F ahead, U up and S to the right of O, and half its size each way
   procedure Block (B : in out Buffer; O, Fwd : V3; F, U, S, HF, HU, HS : Float; C : Color;
                  Tex : Float := 0.0);

   --  An upright cylinder, or an elliptic one turned by Angle, from height Y0 to Y1
   procedure Cylinder (B : in out Buffer; Center : V3; RX, RZ, Angle, Y0, Y1 : Float; C : Color;
                       Tex : Float := 0.0; Segments : Positive := 20; Cap : Boolean := True;
                       Taper : Float := 1.0);   --  the top's radius to the bottom's: 0 a cone

   --  A cylinder lying along Fwd, its axis at height Center.Y
   procedure Barrel (B : in out Buffer; Center, Fwd : V3; R, Half_Length : Float; C : Color;
                     Segments : Positive := 12);

   --  Half an ellipsoid on the floor at Center
   procedure Dome (B : in out Buffer; Center : V3; RX, RZ, Angle, H : Float; C : Color;
                   Tex : Float := 0.0; Segments : Positive := 20);

   --  A profile turned round an upright axis: radius and height, from the bottom up
   type Ring_Point is record
      R, Y : Float;
   end record;
   type Profile is array (Positive range <>) of Ring_Point;
   procedure Lathe (B : in out Buffer; Center : V3; P : Profile; Scale_R, Scale_Y : Float; C : Color;
                    Tex : Float := 0.0; Segments : Positive := 20);

   procedure Sphere (B : in out Buffer; Center : V3; R : Float; C : Color; Segments : Positive := 12);

   --  A flat disc, not lit: shadows, oil and glows
   procedure Disc (B : in out Buffer; Center : V3; RX, RZ, Angle : Float; C : Color;
                   Segments : Positive := 16);

   procedure Upload (B : in out Buffer; Static : Boolean);
   procedure Draw (B : Buffer);
   procedure Draw_Range (B : Buffer; First, Count : Natural);   --  some of the vertices sent

private

   type Float_Array is array (Natural range <>) of Float with Convention => C;
   type Float_Access is access Float_Array;

   Stride : constant := 13;

   type Buffer is limited record
      Data  : Float_Access := null;
      Count : Natural := 0;     --  floats
      Vao, Vbo : aliased GL.GLuint := 0;
      Drawn : Natural := 0;     --  vertices sent
   end record;

end Mesh;
