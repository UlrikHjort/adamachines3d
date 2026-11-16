--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Everything drawn flat over the 3D picture, with cairo: the laps and
--  places, the map of the track in the corner, the menus and the results.
--  It is all drawn into one picture the size of the window, which the view
--  lays over the 3D one.

with Cairo;
with Race;

package Overlay is

   procedure Begin_Frame (W, H : Natural);
   --  A clear picture of this size to draw on

   function Surface return Cairo.Cairo_Surface;
   function Context return Cairo.Cairo_Context;   --  to draw on it with cairo directly
   function Width return Natural;
   function Height return Natural;

   procedure Race_Hud (X, Y, W, H : Float; Car : Race.Car_Index; Camera_Name : String;
                       Show_Fps : Boolean; Fps : Float);
   --  The laps, place, time and pick-up of a player's car, in that part of the window

   procedure Minimap (X, Y, Size : Float; Car : Race.Car_Index);
   --  The track, and every car on it, in a square Size across at X, Y; Car stands out

   procedure Countdown (X, Y, W, H : Float);   --  the lights, and GO

   procedure Duel_Hud;
   --  The eight lights of a duel, coloured by who holds them; who took the last one

   --  A menu: a title, lines of a label and a value, one chosen
   procedure Clear_Menu;
   procedure Add_Item (Label : String; Value : String := ""; Arrows : Boolean := False);
   procedure Add_Note (Text : String);   --  small lines under the menu
   procedure Draw_Menu (Title : String; Chosen : Positive; Subtitle : String := "");

   procedure Results (Title : String);
   --  The places, times and best laps of the race

   type Point_List is array (Race.Car_Index) of Natural;
   procedure Standings (Title, Subtitle : String; Points : Point_List; Final : Boolean);
   --  The points of a championship so far, the most first

   procedure Banner (Text : String; Y_Share : Float := 0.42; Size : Float := 80.0);
   --  Big words across the window

   function Time_Img (T : Float) return String;

end Overlay;
