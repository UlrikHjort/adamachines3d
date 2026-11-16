--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Tracks; use Tracks;

package body Terrain is

   use type Geom.Vec;

   Amp : Float := 0.0;            --  how high the hills go
   Bank : Boolean := False;
   Phase : array (1 .. 4) of Float := (others => 0.0);
   W, H : Float := 1000.0;

   Max_Samples : constant := 4000;
   Turns : array (0 .. Max_Samples - 1) of Float := (others => 0.0);   --  the road's bend, smoothed
   N : Natural := 0;

   Bank_Per_Turn : constant := 11.0;   --  the slope of the road per unit of bend
   Most_Bank : constant := 0.22;

   function Active return Boolean is (Amp > 0.0);

   function Hills (P : Geom.Vec) return Float is
      Edge : constant Float := Float'Min (Float'Min (P.X, W - P.X), Float'Min (P.Y, H - P.Y));
      Fade : constant Float := Geom.Clamp (Edge / 350.0, 0.0, 1.0);
   begin
      if Amp = 0.0 then
         return 0.0;
      end if;
      return Amp * Fade * Fade *
        (0.5 + 0.5 * Sin (P.X / 430.0 + Phase (1)) * Cos (P.Y / 370.0 + Phase (2))
         + 0.30 * Sin ((P.X + P.Y) / 610.0 + Phase (3))
         + 0.20 * Cos ((P.X - P.Y) / 260.0 + Phase (4)));
   end Hills;

   function Height (P : Geom.Vec; Hint : Integer := -1) return Float is
      Base : constant Float := Hills (P);
   begin
      if not Bank or else N = 0 then
         return Base;
      end if;
      declare
         I : constant Natural := Nearest (P, Hint);
         S : constant Sample := Get (I);
         D : constant Float := Geom.Dot (P - S.P, Geom.Perp (S.T));   --  across the road, to the right
         Half : constant Float := S.Width / 2.0;
         Slope : constant Float := Geom.Clamp (-Bank_Per_Turn * Turns (I mod N), -Most_Bank, Most_Bank);
         Fade : constant Float := 1.0 - Geom.Clamp ((abs D - Half) / 70.0, 0.0, 1.0);
      begin
         return Base + Slope * Geom.Clamp (D, -Half, Half) * Fade;
      end;
   end Height;

   procedure Find_Tunnels is
      Length : constant := 44;   --  samples: about 350 units of road
      Best_Score : Float;
      Best_At : Integer;
      function Clear_Of_Things (From : Natural) return Boolean is
      begin
         for I in 1 .. Item_Count loop
            declare
               It : constant Item := Get_Item (I);
            begin
               if It.Mat /= Floor or else It.Kind in Ramp_Piece | Boost_Pad then
                  for K in From .. From + Length loop
                     if Geom.Distance (It.S.C, Get (K).P) < Get (K).Width / 2.0 + Float'Max (It.S.RX, It.S.RY) + 30.0 then
                        return False;
                     end if;
                  end loop;
               end if;
            end;
         end loop;
         return True;
      end Clear_Of_Things;
   begin
      Tunnel_Count := 0;
      for T in 1 .. Max_Tunnels loop
         Best_Score := Float'Last;
         Best_At := -1;
         for From in 60 .. Integer (N) - Length - 60 loop
            if From mod 4 = 0 then
               declare
                  Bend : Float := 0.0;
                  Near_Other : Boolean := False;
               begin
                  for K in From .. From + Length loop
                     Bend := Bend + abs Turns (K);
                  end loop;
                  for Other in 1 .. Tunnel_Count loop
                     if abs (From - Integer (Tunnels (Other).First)) < Integer (N) / 3 then
                        Near_Other := True;
                     end if;
                  end loop;
                  if not Near_Other and then Bend < Best_Score and then Bend / Float (Length) < 1.0 / 220.0 then
                     if Clear_Of_Things (From) then
                        Best_Score := Bend;
                        Best_At := From;
                     end if;
                  end if;
               end;
            end if;
         end loop;
         exit when Best_At < 0;
         Tunnel_Count := Tunnel_Count + 1;
         Tunnels (Tunnel_Count) := (Natural (Best_At), Natural (Best_At + Length));
      end loop;
   end Find_Tunnels;

   procedure Setup is
      Tunnels_Here : Boolean;
   begin
      W := Tracks.Width;
      H := Tracks.Height;
      N := Natural'Min (Count, Max_Samples);
      Amp := (case Theme is
                 when Garden => 26.0,
                 when Easter => 22.0,
                 when Mud => 40.0,
                 when Arctic => 30.0,
                 when Moon => 34.0,
                 when Alien => 30.0,
                 when Halloween => 0.0,   --  broomsticks: they fly over it
                 when others => 0.0);
      Bank := Amp > 0.0;
      Tunnels_Here := Theme in Garden | Easter | Mud | Arctic | Moon | Alien | Toy_Town;
      for K in Phase'Range loop
         Phase (K) := Float ((Track_Id'Pos (Current) * 37 + K * 11) mod 63) / 10.0;
      end loop;
      for I in 0 .. N - 1 loop
         declare
            T : Float := 0.0;
         begin
            for K in -3 .. 3 loop
               T := T + Get (I + K).Turn;
            end loop;
            Turns (I) := T / 7.0;
         end;
      end loop;
      Tunnel_Count := 0;
      if Tunnels_Here and then N > 200 then
         Find_Tunnels;
      end if;
   end Setup;

end Terrain;
