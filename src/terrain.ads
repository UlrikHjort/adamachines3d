--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The lie of the land out of doors: rolling hills, the road banked in its
--  tight bends, and a tunnel or two through a mound over a straight stretch.
--  The race itself stays flat: this is how high things are drawn, so a car
--  goes up a hill and leans with the bank as it drives on as before.

with Geom;

package Terrain is

   procedure Setup;
   --  The track loaded: its hills, its bends, where its tunnels go

   function Active return Boolean;   --  the track has hills at all

   function Height (P : Geom.Vec; Hint : Integer := -1) return Float;
   --  How far the ground stands above the floor of the track; Hint: a sample near P

   function Hills (P : Geom.Vec) return Float;
   --  The hills alone, without the banking: quick, for smoke and rain

   type Tunnel is record
      First, Last : Natural := 0;   --  the samples of the road it covers
   end record;
   Max_Tunnels : constant := 2;
   Tunnels : array (1 .. Max_Tunnels) of Tunnel;
   Tunnel_Count : Natural := 0;

end Terrain;
