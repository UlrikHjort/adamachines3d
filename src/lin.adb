--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Lin is

   function Length (A : V3) return Float is (Sqrt (Dot (A, A)));

   function Normal (A : V3) return V3 is
      L : constant Float := Length (A);
   begin
      return (if L < 1.0E-9 then (0.0, 0.0, 0.0) else (1.0 / L) * A);
   end Normal;

   function "*" (A, B : Mat4) return Mat4 is
      R : Mat4 := (others => 0.0);
   begin
      for Col in 0 .. 3 loop
         for Row in 0 .. 3 loop
            for K in 0 .. 3 loop
               R (Col * 4 + Row) := R (Col * 4 + Row) + A (K * 4 + Row) * B (Col * 4 + K);
            end loop;
         end loop;
      end loop;
      return R;
   end "*";

   function Perspective (Fov_Y, Aspect, Near, Far : Float) return Mat4 is
      F : constant Float := 1.0 / Tan (Fov_Y / 2.0);
      M : Mat4 := (others => 0.0);
   begin
      M (0) := F / Aspect;
      M (5) := F;
      M (10) := (Far + Near) / (Near - Far);
      M (11) := -1.0;
      M (14) := 2.0 * Far * Near / (Near - Far);
      return M;
   end Perspective;

   function Look_At (Eye, Target, Up_Dir : V3) return Mat4 is
      F : constant V3 := Normal (Target - Eye);
      S : constant V3 := Normal (Cross (F, Up_Dir));
      U : constant V3 := Cross (S, F);
   begin
      return (S.X, U.X, -F.X, 0.0,
              S.Y, U.Y, -F.Y, 0.0,
              S.Z, U.Z, -F.Z, 0.0,
              -Dot (S, Eye), -Dot (U, Eye), Dot (F, Eye), 1.0);
   end Look_At;

   function Ortho (L, R, B, T : Float) return Mat4 is
     (2.0 / (R - L), 0.0, 0.0, 0.0,
      0.0, 2.0 / (T - B), 0.0, 0.0,
      0.0, 0.0, -1.0, 0.0,
      -(R + L) / (R - L), -(T + B) / (T - B), 0.0, 1.0);

   function Ortho (L, R, B, T, Near, Far : Float) return Mat4 is
     (2.0 / (R - L), 0.0, 0.0, 0.0,
      0.0, 2.0 / (T - B), 0.0, 0.0,
      0.0, 0.0, -2.0 / (Far - Near), 0.0,
      -(R + L) / (R - L), -(T + B) / (T - B), -(Far + Near) / (Far - Near), 1.0);

end Lin;
