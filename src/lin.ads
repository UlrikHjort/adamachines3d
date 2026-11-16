--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Three dimensional vectors and the 4x4 matrices of the camera.
--  The race is flat: its X and Y lie on the floor, so a point of the race
--  (X, Y) at height H is (X, H, Y) here, with Y up.  Seen from above, X runs
--  to the right and Z down the screen, as the race's Y does.

with Geom;

package Lin is

   type V3 is record
      X, Y, Z : Float := 0.0;
   end record;

   function "+" (A, B : V3) return V3 is ((A.X + B.X, A.Y + B.Y, A.Z + B.Z));
   function "-" (A, B : V3) return V3 is ((A.X - B.X, A.Y - B.Y, A.Z - B.Z));
   function "*" (S : Float; A : V3) return V3 is ((S * A.X, S * A.Y, S * A.Z));
   function Dot (A, B : V3) return Float is (A.X * B.X + A.Y * B.Y + A.Z * B.Z);
   function Cross (A, B : V3) return V3 is
     ((A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X));
   function Length (A : V3) return Float;
   function Normal (A : V3) return V3;
   function Lerp (A, B : V3; T : Float) return V3 is (A + T * (B - A));

   function To3 (P : Geom.Vec; H : Float := 0.0) return V3 is ((P.X, H, P.Y));
   --  A point of the race, at a height

   Up : constant V3 := (0.0, 1.0, 0.0);

   type Mat4 is array (0 .. 15) of Float with Convention => C;   --  column after column
   function "*" (A, B : Mat4) return Mat4;
   function Perspective (Fov_Y, Aspect, Near, Far : Float) return Mat4;
   function Look_At (Eye, Target, Up_Dir : V3) return Mat4;
   function Ortho (L, R, B, T : Float) return Mat4;
   function Ortho (L, R, B, T, Near, Far : Float) return Mat4;

end Lin;
