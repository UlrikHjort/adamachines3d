--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The checks, without a window: on every built-in track a race of AI
--  drivers is run for a while, every car must get round, the land must
--  stand where it should, and the race run again from what was pressed
--  must end exactly as it did (the replays depend on it).

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Geom; use Geom;
with Race; use Race;
with Terrain;
with Tracks;

procedure Racetest is
   Failed : Natural := 0;
   Steps : constant := 120 * 45;   --  three quarters of a minute of racing

   procedure Fail (Why : String) is
   begin
      Put_Line ("  FAILED: " & Why);
      Failed := Failed + 1;
   end Fail;

   type Places is array (Car_Index) of Vec;
begin
   for Id in 1 .. Tracks.Built_In_Count loop
      declare
         First : Places;
         Least : Integer := Integer'Last;
      begin
         Race.Setup (Id, Single, 5, 3, Normal);
         Terrain.Setup;
         for K in 1 .. Steps loop
            Race.Step ((others => <>), Autopilot => True);
         end loop;
         for I in 1 .. State.Count loop
            First (I) := State.Racers (I).Car.P;
            Least := Integer'Min (Least, State.Racers (I).Progress);
         end loop;
         --  every car well on its way: a quarter of a lap at least
         if Least < Tracks.Count / 4 then
            Fail (Tracks.Name (Id) & ": a car got only" & Integer'Image (Least) & " samples round");
         end if;
         --  the hills: none off the edge of the world, none too high
         if abs Terrain.Hills ((0.0, 0.0)) > 0.01 or else abs Terrain.Hills ((Tracks.Width, Tracks.Height)) > 0.01 then
            Fail (Tracks.Name (Id) & ": the land does not come down to the edge");
         end if;
         --  the same race again: the same places
         Race.Setup (Id, Single, 5, 3, Normal);
         for K in 1 .. Steps loop
            Race.Step ((others => <>), Autopilot => True);
         end loop;
         for I in 1 .. State.Count loop
            if Distance (First (I), State.Racers (I).Car.P) > 0.0 then
               Fail (Tracks.Name (Id) & ": run again, car" & Integer'Image (I) & " ends somewhere else");
            end if;
         end loop;
         Put_Line ((if Failed = 0 then "ok   " else "     ") & Tracks.Name (Id) & "  " & Terrain.Tunnel_Count'Image
                   & " tunnels");
      end;
   end loop;
   if Failed > 0 then
      Put_Line (Natural'Image (Failed) & " checks failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("all the checks passed");
   end if;
end Racetest;
