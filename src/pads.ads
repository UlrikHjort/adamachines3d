--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Game controllers, read from Linux's joystick devices (/dev/input/js*).
--  Pads, wheels and joysticks may come and go while the game runs.  A
--  controller belongs to no one until something is pressed on it; then it
--  is the first player's, or, if they have one, the second's.
--
--  A pad (Xbox and the like): left stick or the cross to steer, the right
--  trigger or A to drive, the left trigger or X to brake, B or a shoulder
--  button to fire, Y for the camera, Start to pause, Back to race again.
--  A wheel: the wheel, the pedals, and its buttons to fire.  A joystick:
--  push it forward to drive, back to brake, and fire with the button.

package Pads is

   Max_Players : constant := 2;
   subtype Player_Number is Positive range 1 .. Max_Players;

   type Reading is record
      Steer    : Float := 0.0;    --  -1 left .. 1 right
      Throttle : Float := 0.0;    --  0 .. 1
      Brake    : Float := 0.0;    --  0 .. 1
   end record;

   type Action is (Fire, Camera, Pause, Restart, Up, Down, Left, Right, Ok, Back);

   procedure Poll;
   --  Reads every controller; looks for new ones now and then

   function Has (P : Player_Number) return Boolean;   --  the player has a controller
   function Get (P : Player_Number) return Reading;
   function Name (P : Player_Number) return String;

   function Next (P : out Natural; A : out Action) return Boolean;
   --  The next thing pressed since the last call, and whose controller it was on
   --  (0: a controller nobody has; pressing it gave it to a player if one is free)

   function Count return Natural;   --  controllers plugged in

   procedure Release_All;   --  nobody has a controller: the next press decides

   --  Feeling the race through the controller: a pad rumbles, a wheel pulls back to
   --  the middle harder the faster the car goes, and shakes when it is knocked
   procedure Feel (P : Player_Number; Kick, Rough, Speed_Share : Float);
   --  Kick 0 .. 1: a knock just now; Rough 0 .. 1: going over rough ground;
   --  Speed_Share 0 .. 1 of the top speed

   procedure Quiet;      --  no rumble, a wheel gently centred: in the menus
   procedure Shut_Down;  --  the game ends: everything stopped, the wheel let go

end Pads;
