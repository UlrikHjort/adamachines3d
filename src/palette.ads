--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The paints of the cars, shared by the world and the HUD

package Palette is

   type RGB is record
      R, G, B : Float;
   end record;

   Paints : constant array (0 .. 7) of RGB :=
     ((0.88, 0.12, 0.10),    --  red, the first player
      (0.12, 0.38, 0.92),    --  blue, the second
      (0.98, 0.78, 0.08),    --  yellow
      (0.10, 0.70, 0.30),    --  green
      (0.62, 0.25, 0.85),    --  purple
      (0.98, 0.50, 0.08),    --  orange
      (0.94, 0.94, 0.94),    --  white
      (0.10, 0.75, 0.80));   --  teal

   function Paint (N : Natural) return RGB is (Paints (N mod Paints'Length));

end Palette;
