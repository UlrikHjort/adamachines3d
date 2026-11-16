--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The world round the track: the room it is in, with its walls, window,
--  door and furniture far bigger than the cars; the table it stands on; or
--  the sky, hills and trees round it out of doors, the stars and the Earth
--  over the moon, the glass of the fish tank.  One world unit is about two
--  and a half millimetres: a room is a thousand units high.

with Mesh;

package Scenery is

   function Floor_Y (Ground_Y : Float) return Float;
   --  Where the floor of the room is: under a table, far below the track

   procedure Build (B, Clear : in out Mesh.Buffer; Ground_Y : Float; Horizon : Mesh.Color);
   --  The track's picture on the floor at Ground_Y, and everything round it: the solid
   --  things into B, the see-through ones (glass, water) into Clear.  Horizon: the colour
   --  of the air far off, which the sky meets

   function Indoors return Boolean;   --  the track loaded is in a room

end Scenery;
