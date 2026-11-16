--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The race seen in 3D.  The floor is the picture the 2D game paints of the
--  track; the things in the way rise out of it, with that picture over their
--  tops; the cars, the things that move and the pick-ups are made of boxes,
--  cylinders and balls each frame, with smoke, dust and sparks about them.
--  Each player has a view and a camera of their own: behind the car, on its
--  bumper, or high above it as in the 2D game.

with Geom;
with Race;

package View is

   type Camera_Kind is (Chase, Bumper, Cockpit, High, TV);
   subtype Player_Camera is Camera_Kind range Chase .. High;   --  TV: beside the track, for replays
   subtype Slot is Positive range 1 .. 2;   --  a player's view

   procedure Init;
   --  With the GL context current, once

   procedure New_Track;
   --  The race was set up again: build its world

   procedure Hear (E : Race.Event);
   --  Something happened: sparks, splashes and the like

   procedure Begin_Frame (Alpha, Dt : Float);
   --  Alpha 0 .. 1: how far the race is between its last step and the next

   procedure Render_View (X, Y, W, H : Natural; S : Slot; Car : Race.Car_Index; Kind : Camera_Kind;
                          Orbit : Boolean; Dt : Float; Shared : Boolean := False);
   --  The race seen from Car, in that part of the window (GL's, from the bottom).
   --  Orbit: the camera goes slowly round the car, for the title.  Shared: high over the
   --  race's own camera, which both players of a duel share

   Shared_Height : constant := 500.0;   --  how high the shared camera is, and how far back
   Shared_Back   : constant := 200.0;

   procedure Draw_Overlay (W, H : Natural);
   --  What Overlay drew, over it all

   procedure Shake (S : Slot; Amount : Float);

   procedure New_Race;
   --  The race began again on the same track: no marks, no smoke, the cameras behind their cars

   --  The ghost of the best lap, in a time trial
   Ghost_On : Boolean := False;
   Ghost_P  : Geom.Vec;
   Ghost_H  : Float := 0.0;

   function Ear return Geom.Vec;          --  where the first camera is, on the floor
   function Ear_Right return Geom.Vec;    --  its right, on the floor, for the pan of sounds

   function Fps return Float;

   Shadows_On : Boolean := True;

   --  The body of each car (on the car tracks), as chosen or given
   Styles : array (Race.Car_Index) of Natural := (0, 1, 2, 3, 0, 1, 2, 3);   --  the sun's shadows; off for a slow machine

end View;
