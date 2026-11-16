--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Surface;
with Glib; use Glib;
with Gtkada.Types;
with Cars;
with Geom; use Geom;
with Palette;
with Race; use Race;
with Records;
with Tracks;

package body Overlay is

   function G (X : Float) return Gdouble is (Gdouble (X));

   Pic : Cairo_Surface := Null_Surface;
   Cr  : Cairo_Context;
   Pic_W, Pic_H : Natural := 0;
   S   : Float := 1.0;   --  the size of things: 1 in a window 900 high

   function Surface return Cairo_Surface is (Pic);
   function Context return Cairo_Context is (Cr);
   function Width return Natural is (Pic_W);
   function Height return Natural is (Pic_H);

   procedure Begin_Frame (W, H : Natural) is
   begin
      if Pic = Null_Surface or else W /= Pic_W or else H /= Pic_H then
         if Pic /= Null_Surface then
            Destroy (Cr);
            Cairo.Surface.Destroy (Pic);
         end if;
         Pic := Cairo.Image_Surface.Create (Cairo.Image_Surface.Cairo_Format_ARGB32,
                                            Gint (Natural'Max (1, W)), Gint (Natural'Max (1, H)));
         Cr := Create (Pic);
         Pic_W := W;
         Pic_H := H;
      end if;
      Save (Cr);
      Set_Operator (Cr, Cairo_Operator_Clear);
      Paint (Cr);
      Restore (Cr);
      Select_Font_Face (Cr, "DejaVu Sans", Cairo_Font_Slant_Normal, Cairo_Font_Weight_Bold);
      S := Float (H) / 900.0;
   end Begin_Frame;

   ---------------------------------------------------------------------------

   function Img (N : Integer) return String is
      T : constant String := Integer'Image (N);
   begin
      return (if N < 0 then T else T (T'First + 1 .. T'Last));
   end Img;

   function Time_Img (T : Float) return String is
      Hundredths : constant Natural := Natural (Float'Max (0.0, T) * 100.0);
      Sec : constant Natural := Hundredths / 100 mod 60;
      Min : constant Natural := Hundredths / 6000;
      Hs  : constant Natural := Hundredths mod 100;
   begin
      return Img (Min) & ":" & (if Sec < 10 then "0" else "") & Img (Sec) & "."
        & (if Hs < 10 then "0" else "") & Img (Hs);
   end Time_Img;

   function Ordinal (N : Positive) return String is
     (Img (N) & (case N mod 10 is
                   when 1 => (if N mod 100 = 11 then "TH" else "ST"),
                   when 2 => (if N mod 100 = 12 then "TH" else "ND"),
                   when 3 => (if N mod 100 = 13 then "TH" else "RD"),
                   when others => "TH"));

   function Width_Of (T : String) return Float is
      P : Gtkada.Types.Chars_Ptr := Gtkada.Types.New_String (T);
      E : aliased Cairo_Text_Extents;
   begin
      Text_Extents (Cr, P, E'Access);
      Gtkada.Types.Free (P);
      return Float (E.X_Advance);
   end Width_Of;

   --  Letters with a dark edge, Align -1 left, 0 middle, 1 right
   procedure Say (T : String; X, Y, Size : Float; Align : Integer := -1;
                  R : Float := 1.0; Gr : Float := 1.0; B : Float := 1.0; A : Float := 1.0) is
      X0 : Float;
   begin
      Set_Font_Size (Cr, G (Size));
      X0 := (case Align is when -1 => X, when 0 => X - Width_Of (T) / 2.0, when others => X - Width_Of (T));
      New_Path (Cr);
      Move_To (Cr, G (X0), G (Y));
      Text_Path (Cr, T);
      Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, G (0.75 * A));
      Set_Line_Width (Cr, G (Float'Max (2.0, Size / 9.0)));
      Stroke_Preserve (Cr);
      Set_Source_Rgba (Cr, G (R), G (Gr), G (B), G (A));
      Fill (Cr);
   end Say;

   procedure Panel (X, Y, W, H : Float; A : Float := 0.55) is
      R : constant Float := 14.0 * S;
   begin
      New_Path (Cr);
      Arc (Cr, G (X + W - R), G (Y + R), G (R), G (-Pi / 2.0), 0.0);
      Arc (Cr, G (X + W - R), G (Y + H - R), G (R), 0.0, G (Pi / 2.0));
      Arc (Cr, G (X + R), G (Y + H - R), G (R), G (Pi / 2.0), G (Pi));
      Arc (Cr, G (X + R), G (Y + R), G (R), G (Pi), G (1.5 * Pi));
      Close_Path (Cr);
      Set_Source_Rgba (Cr, 0.05, 0.06, 0.10, G (A));
      Fill (Cr);
   end Panel;

   ---------------------------------------------------------------------------

   procedure Race_Hud (X, Y, W, H : Float; Car : Race.Car_Index; Camera_Name : String;
                       Show_Fps : Boolean; Fps : Float)
   is
      St : State_Type renames Race.State;
      R  : Racer renames St.Racers (Car);
      K  : constant Float := Float'Max (H / 900.0, S * 0.7);
      Map : constant Float := Float'Min (W, H) * (if H < Float (Pic_H) * 0.75 then 0.36 else 0.30);
   begin
      Say ("LAP " & Img (Lap_Shown (Car)) & "/" & Img (St.Laps), X + 30.0 * K, Y + 60.0 * K, 40.0 * K);
      Say (Ordinal (R.Place) & " OF " & Img (St.Count), X + 30.0 * K, Y + 110.0 * K, 40.0 * K,
           R => 1.0, Gr => 0.85, B => 0.3);
      if R.Holding /= None then
         Say (Weapon_Name (R.Holding), X + 30.0 * K, Y + 155.0 * K, 30.0 * K, R => 0.5, Gr => 1.0, B => 0.6);
      end if;
      Say ((if R.Finished then Time_Img (R.Finish_T) else Time_Img (St.Time)),
           X + W - 30.0 * K, Y + 60.0 * K, 34.0 * K, 1);
      if R.Best_Lap > 0.0 then
         Say ("BEST " & Time_Img (R.Best_Lap), X + W - 30.0 * K, Y + 98.0 * K, 24.0 * K, 1);
      end if;
      if Records.Best_Lap (Tracks.Current) > 0.0 then
         Say ("RECORD " & Time_Img (Records.Best_Lap (Tracks.Current)), X + W - 30.0 * K, Y + 130.0 * K, 20.0 * K, 1,
              1.0, 0.85, 0.3);
      end if;
      if Show_Fps then
         Say (Img (Integer (Fps)) & " FPS", X + W - 30.0 * K, Y + 160.0 * K, 20.0 * K, 1);
      end if;
      Say (Camera_Name, X + W - 30.0 * K, Y + H - 24.0 * K, 17.0 * K, 1, 0.9, 0.9, 0.9, 0.8);
      Minimap (X + 20.0 * K, Y + H - Map - 20.0 * K, Map, Car);
      if R.Finished then
         Say ("FINISHED " & Ordinal (R.Place), X + W / 2.0, Y + H * 0.40, 70.0 * K, 0, 1.0, 0.85, 0.2);
      end if;
   end Race_Hud;

   procedure Countdown (X, Y, W, H : Float) is
      St : State_Type renames Race.State;
      K  : constant Float := Float'Max (H / 900.0, S * 0.7);
   begin
      if St.Phase = Race.Countdown and then St.Count_T < 3.0 then
         Say (Img (Integer (Float'Ceiling (St.Count_T))), X + W / 2.0, Y + H * 0.45, 140.0 * K, 0, 1.0, 0.85, 0.2);
      elsif St.Phase = Running and then St.Time < 1.0 then
         Say ("GO!", X + W / 2.0, Y + H * 0.45, 140.0 * K, 0, 0.3, 1.0, 0.4, 1.0 - St.Time * 0.6);
      end if;
   end Countdown;

   procedure Duel_Hud is
      St : State_Type renames Race.State;
      A : Racer renames St.Racers (Player (1));
      Bp : Racer renames St.Racers (Player (2));
      CA : constant Palette.RGB := Palette.Paint (A.Paint);
      CB : constant Palette.RGB := Palette.Paint (Bp.Paint);
      R : constant Float := 16.0 * S;
      Gap : constant Float := 44.0 * S;
      X0 : constant Float := Float (Pic_W) / 2.0 - Gap * Float (Duel_Points - 1) / 2.0;
      Y : constant Float := 56.0 * S;
   begin
      Panel (X0 - 100.0 * S, Y - 36.0 * S, Gap * Float (Duel_Points - 1) + 200.0 * S, 72.0 * S);
      Say ("P1", X0 - 80.0 * S, Y + 10.0 * S, 28.0 * S, -1, CA.R, CA.G, CA.B);
      Say ("P2", X0 + Gap * Float (Duel_Points - 1) + 80.0 * S, Y + 10.0 * S, 28.0 * S, 1, CB.R, CB.G, CB.B);
      for K in 1 .. Duel_Points loop
         declare
            C : constant Palette.RGB := (if K <= A.Points then CA else CB);
         begin
            New_Path (Cr);
            Arc (Cr, G (X0 + Gap * Float (K - 1)), G (Y), G (R), 0.0, G (2.0 * Pi));
            Set_Source_Rgb (Cr, G (C.R), G (C.G), G (C.B));
            Fill_Preserve (Cr);
            Set_Line_Width (Cr, G (2.5 * S));
            Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.7);
            Stroke (Cr);
         end;
      end loop;
      if St.Phase = Round_Over and then St.Round_Leader in Car_Index then
         declare
            C : constant Palette.RGB := Palette.Paint (St.Racers (St.Round_Leader).Paint);
         begin
            Say ("P" & Img (St.Racers (St.Round_Leader).Human) & " TAKES A LIGHT", Float (Pic_W) / 2.0,
                 Float (Pic_H) * 0.4, 72.0 * S, 0, C.R, C.G, C.B);
         end;
      elsif St.Phase = Over and then St.Winner in Car_Index then
         declare
            C : constant Palette.RGB := Palette.Paint (St.Racers (St.Winner).Paint);
         begin
            Say ("P" & Img (St.Racers (St.Winner).Human) & " WINS THE DUEL!", Float (Pic_W) / 2.0,
                 Float (Pic_H) * 0.4, 84.0 * S, 0, C.R, C.G, C.B);
         end;
      end if;
   end Duel_Hud;

   procedure Minimap (X, Y, Size : Float; Car : Race.Car_Index) is
      N : constant Positive := Tracks.Count;
      X0, Y0 : Float := Float'Last;
      X1, Y1 : Float := Float'First;
      Pad : constant Float := Size * 0.08;
      Sc, Ox, Oy : Float;
      function MX (P : Vec) return Gdouble is (G (Ox + (P.X - X0) * Sc));
      function MY (P : Vec) return Gdouble is (G (Oy + (P.Y - Y0) * Sc));
   begin
      for I in 0 .. N - 1 loop
         declare
            P : constant Vec := Tracks.Get (I).P;
         begin
            X0 := Float'Min (X0, P.X);
            Y0 := Float'Min (Y0, P.Y);
            X1 := Float'Max (X1, P.X);
            Y1 := Float'Max (Y1, P.Y);
         end;
      end loop;
      Sc := (Size - 2.0 * Pad) / Float'Max (X1 - X0, Y1 - Y0);
      Ox := X + Pad + ((Size - 2.0 * Pad) - (X1 - X0) * Sc) / 2.0;
      Oy := Y + Pad + ((Size - 2.0 * Pad) - (Y1 - Y0) * Sc) / 2.0;
      Panel (X, Y, Size, Size, 0.42);

      --  the road, an edge and then its middle
      Set_Line_Join (Cr, Cairo_Line_Join_Round);
      Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
      for Pass in 1 .. 2 loop
         New_Path (Cr);
         for I in 0 .. N loop
            declare
               P : constant Vec := Tracks.Get (I).P;
            begin
               if I = 0 then
                  Move_To (Cr, MX (P), MY (P));
               else
                  Line_To (Cr, MX (P), MY (P));
               end if;
            end;
         end loop;
         Close_Path (Cr);
         if Pass = 1 then
            Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.6);
            Set_Line_Width (Cr, G (Float'Max (5.0, Size * 0.045)));
         else
            Set_Source_Rgba (Cr, 0.92, 0.92, 0.92, 0.95);
            Set_Line_Width (Cr, G (Float'Max (2.5, Size * 0.022)));
         end if;
         Stroke (Cr);
      end loop;

      --  the start line
      declare
         P : constant Vec := Tracks.Get (0).P;
         Across : constant Vec := Perp (Tracks.Get (0).T) * (Size * 0.035 / Sc);
      begin
         New_Path (Cr);
         Move_To (Cr, MX (P - Across), MY (P - Across));
         Line_To (Cr, MX (P + Across), MY (P + Across));
         Set_Source_Rgb (Cr, 0.95, 0.2, 0.15);
         Set_Line_Width (Cr, G (Float'Max (2.0, Size * 0.014)));
         Stroke (Cr);
      end;

      --  the cars, the one this map is for drawn last, on top
      for Pass in 1 .. 2 loop
         for I in 1 .. Race.State.Count loop
            declare
               R : Racer renames Race.State.Racers (I);
               Mine : constant Boolean := I = Car;
               Human : constant Boolean := R.Human > 0;
               C : constant Palette.RGB := Palette.Paint (R.Paint);
               Rad : constant Float := Size * (if Mine then 0.032 elsif Human then 0.026 else 0.021);
            begin
               if (Pass = 2) = Mine and then not Cars.Falling (R.Car) then
                  New_Path (Cr);
                  Arc (Cr, MX (R.Car.P), MY (R.Car.P), G (Rad + Float'Max (1.5, Size * 0.008)), 0.0, G (2.0 * Pi));
                  if Human then
                     Set_Source_Rgb (Cr, 1.0, 1.0, 1.0);
                  else
                     Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.8);
                  end if;
                  Fill (Cr);
                  New_Path (Cr);
                  Arc (Cr, MX (R.Car.P), MY (R.Car.P), G (Rad), 0.0, G (2.0 * Pi));
                  Set_Source_Rgb (Cr, G (C.R), G (C.G), G (C.B));
                  Fill (Cr);
               end if;
            end;
         end loop;
      end loop;
   end Minimap;

   ---------------------------------------------------------------------------
   --  Menus
   ---------------------------------------------------------------------------

   type Item is record
      Label, Value : Unbounded_String;
      Arrows : Boolean := False;
   end record;
   Items : array (1 .. 16) of Item;
   Item_Count : Natural := 0;
   Notes : array (1 .. 6) of Unbounded_String;
   Note_Count : Natural := 0;

   procedure Clear_Menu is
   begin
      Item_Count := 0;
      Note_Count := 0;
   end Clear_Menu;

   procedure Add_Item (Label : String; Value : String := ""; Arrows : Boolean := False) is
   begin
      if Item_Count < Items'Last then
         Item_Count := Item_Count + 1;
         Items (Item_Count) := (To_Unbounded_String (Label), To_Unbounded_String (Value), Arrows);
      end if;
   end Add_Item;

   procedure Add_Note (Text : String) is
   begin
      if Note_Count < Notes'Last then
         Note_Count := Note_Count + 1;
         Notes (Note_Count) := To_Unbounded_String (Text);
      end if;
   end Add_Note;

   procedure Draw_Menu (Title : String; Chosen : Positive; Subtitle : String := "") is
      W : constant Float := Float (Pic_W);
      Line : constant Float := 50.0 * S;
      Box_W : constant Float := Float'Min (W - 40.0 * S, 900.0 * S);
      Box_H : constant Float := 170.0 * S + Line * Float (Item_Count) + 34.0 * S * Float (Note_Count);
      Bx : constant Float := (W - Box_W) / 2.0;
      By : constant Float := Float'Max (20.0 * S, (Float (Pic_H) - Box_H) / 2.0 + 40.0 * S);
      Mid : constant Float := W / 2.0;
   begin
      Say (Title, Mid, By - 30.0 * S, 84.0 * S, 0, 1.0, 0.82, 0.2);
      Panel (Bx, By, Box_W, Box_H, 0.6);
      if Subtitle /= "" then
         Say (Subtitle, Mid, By + 50.0 * S, 24.0 * S, 0, 0.8, 0.85, 0.95);
      end if;
      for I in 1 .. Item_Count loop
         declare
            Y : constant Float := By + 110.0 * S + Line * Float (I - 1);
            On : constant Boolean := I = Chosen;
            L : constant String := To_String (Items (I).Label);
            V : constant String := To_String (Items (I).Value);
            Br : constant Float := (if On then 1.0 else 0.85);
            Bg : constant Float := (if On then 0.85 else 0.85);
            Bb : constant Float := (if On then 0.25 else 0.85);
         begin
            if On then
               New_Path (Cr);
               Rectangle (Cr, G (Bx + 16.0 * S), G (Y - Line * 0.72), G (Box_W - 32.0 * S), G (Line * 0.95));
               Set_Source_Rgba (Cr, 1.0, 1.0, 1.0, 0.10);
               Fill (Cr);
            end if;
            if V = "" then
               Say (L, Mid, Y, 32.0 * S, 0, Br, Bg, Bb);
            else
               Say (L, Mid - 30.0 * S, Y, 30.0 * S, 1, Br, Bg, Bb);
               Say ((if Items (I).Arrows and then On then "<  " & V & "  >" else V),
                    Mid + 30.0 * S, Y, 30.0 * S, -1, Br, Bg, Bb);
            end if;
         end;
      end loop;
      for I in 1 .. Note_Count loop
         Say (To_String (Notes (I)), Mid, By + 110.0 * S + Line * Float (Item_Count) + 34.0 * S * Float (I - 1) + 6.0 * S,
              19.0 * S, 0, 0.75, 0.8, 0.9);
      end loop;
   end Draw_Menu;

   procedure Results (Title : String) is
      St : State_Type renames Race.State;
      W : constant Float := Float (Pic_W);
      Line : constant Float := 46.0 * S;
      Box_W : constant Float := Float'Min (W - 40.0 * S, 860.0 * S);
      Box_H : constant Float := 150.0 * S + Line * Float (St.Count);
      Bx : constant Float := (W - Box_W) / 2.0;
      By : constant Float := (Float (Pic_H) - Box_H) / 2.0 + 30.0 * S;
   begin
      Say (Title, W / 2.0, By - 30.0 * S, 78.0 * S, 0, 1.0, 0.82, 0.2);
      Panel (Bx, By, Box_W, Box_H, 0.65);
      Say ("TIME", Bx + Box_W * 0.66, By + 50.0 * S, 20.0 * S, 1, 0.7, 0.75, 0.85);
      Say ("BEST LAP", Bx + Box_W - 30.0 * S, By + 50.0 * S, 20.0 * S, 1, 0.7, 0.75, 0.85);
      for K in 1 .. St.Count loop
         declare
            I : constant Car_Index := In_Place (K);
            R : Racer renames St.Racers (I);
            Y : constant Float := By + 100.0 * S + Line * Float (K - 1);
            C : constant Palette.RGB := Palette.Paint (R.Paint);
            Human : constant Boolean := R.Human > 0;
            Who : constant String := (if Human and then St.Mode /= Race.Net then "PLAYER " & Img (R.Human) else R.Name);
         begin
            Say (Ordinal (K), Bx + 30.0 * S, Y, 28.0 * S, -1, 1.0, 0.85, 0.3);
            New_Path (Cr);
            Arc (Cr, G (Bx + 130.0 * S), G (Y - 10.0 * S), G (11.0 * S), 0.0, G (2.0 * Pi));
            Set_Source_Rgb (Cr, G (C.R), G (C.G), G (C.B));
            Fill (Cr);
            Say (Who, Bx + 155.0 * S, Y, 28.0 * S, -1, 1.0, (if Human then 1.0 else 0.9), (if Human then 0.6 else 0.9));
            Say ((if R.Finished then Time_Img (R.Finish_T) else "-"), Bx + Box_W * 0.66, Y, 26.0 * S, 1);
            Say ((if R.Best_Lap > 0.0 then Time_Img (R.Best_Lap) else "-"), Bx + Box_W - 30.0 * S, Y, 26.0 * S, 1);
         end;
      end loop;
   end Results;

   procedure Standings (Title, Subtitle : String; Points : Point_List; Final : Boolean) is
      St : State_Type renames Race.State;
      W : constant Float := Float (Pic_W);
      Line : constant Float := 46.0 * S;
      Box_W : constant Float := Float'Min (W - 40.0 * S, 760.0 * S);
      Box_H : constant Float := 150.0 * S + Line * Float (St.Count);
      Bx : constant Float := (W - Box_W) / 2.0;
      By : constant Float := (Float (Pic_H) - Box_H) / 2.0 + 30.0 * S;
      Order : array (1 .. St.Count) of Car_Index;
   begin
      for K in Order'Range loop
         Order (K) := K;
      end loop;
      for I in Order'Range loop   --  the most points first; on equal points, the better place in the last race
         for J in I + 1 .. Order'Last loop
            if Points (Order (J)) > Points (Order (I))
              or else (Points (Order (J)) = Points (Order (I))
                       and then St.Racers (Order (J)).Place < St.Racers (Order (I)).Place)
            then
               declare
                  T : constant Car_Index := Order (I);
               begin
                  Order (I) := Order (J);
                  Order (J) := T;
               end;
            end if;
         end loop;
      end loop;
      Say (Title, W / 2.0, By - 30.0 * S, 70.0 * S, 0, 1.0, 0.82, 0.2);
      Panel (Bx, By, Box_W, Box_H, 0.65);
      Say (Subtitle, W / 2.0, By + 50.0 * S, 24.0 * S, 0, 0.8, 0.85, 0.95);
      for K in Order'Range loop
         declare
            R : Racer renames St.Racers (Order (K));
            Y : constant Float := By + 100.0 * S + Line * Float (K - 1);
            C : constant Palette.RGB := Palette.Paint (R.Paint);
            Human : constant Boolean := R.Human > 0;
            Who : constant String := (if Human then "PLAYER " & Img (R.Human) else R.Name);
            Gold : constant Boolean := Final and then K = 1;
         begin
            Say (Ordinal (K), Bx + 30.0 * S, Y, 28.0 * S, -1, 1.0, 0.85, 0.3);
            New_Path (Cr);
            Arc (Cr, G (Bx + 130.0 * S), G (Y - 10.0 * S), G (11.0 * S), 0.0, G (2.0 * Pi));
            Set_Source_Rgb (Cr, G (C.R), G (C.G), G (C.B));
            Fill (Cr);
            Say (Who & (if Gold then "  - CHAMPION!" else ""), Bx + 155.0 * S, Y, 28.0 * S, -1,
                 1.0, (if Human or Gold then 1.0 else 0.9), (if Gold then 0.3 elsif Human then 0.6 else 0.9));
            Say (Img (Points (Order (K))) & " PTS", Bx + Box_W - 30.0 * S, Y, 28.0 * S, 1);
         end;
      end loop;
   end Standings;

   procedure Banner (Text : String; Y_Share : Float := 0.42; Size : Float := 80.0) is
   begin
      Say (Text, Float (Pic_W) / 2.0, Float (Pic_H) * Y_Share, Size * S, 0);
   end Banner;

end Overlay;
