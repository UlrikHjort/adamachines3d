--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Exceptions;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces.C;
with System;
with Gdk.Event;
with Gdk.Frame_Clock;
with Gdk.Types;
with Gdk.Types.Keysyms;
with Glib; use Glib;
with Glib.Object;
with Gtk.Handlers;
with Gtk.Main;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Window;
with Audio;
with Cars;
with Editor;
with Geom; use Geom;
with GL;
with Overlay;
with Net;
with Models;
with Palette;
with Pads;
with Race;
with Air;
with Records;
with Speech;
with Tracks;
with View;

package body App is

   use type Gdk.Types.Gdk_Key_Type;
   use type View.Camera_Kind;
   use type Tracks.Theme_Kind;
   use type Race.Phase_Kind;
   use type Race.Difficulty;
   use type Race.Game_Mode;
   use type Editor.Action;
   use type Pads.Action;
   use type Net.Role_Kind;
   use type Net.Join_State;

   Window : Gtk.Window.Gtk_Window;
   Area   : Gtk_Widget;
   Area_C : System.Address := System.Null_Address;

   function GL_Area_New return System.Address
     with Import, Convention => C, External_Name => "gtk_gl_area_new";
   procedure GL_Area_Set_Required_Version (A : System.Address; Major, Minor : Gint)
     with Import, Convention => C, External_Name => "gtk_gl_area_set_required_version";
   procedure GL_Area_Set_Has_Depth_Buffer (A : System.Address; Yes : Gboolean)
     with Import, Convention => C, External_Name => "gtk_gl_area_set_has_depth_buffer";
   procedure GL_Area_Make_Current (A : System.Address)
     with Import, Convention => C, External_Name => "gtk_gl_area_make_current";
   function GL_Area_Get_Error (A : System.Address) return System.Address
     with Import, Convention => C, External_Name => "gtk_gl_area_get_error";

   package Render_Cb is new Gtk.Handlers.Return_Callback (Gtk_Widget_Record, Boolean);

   function Env (N : String) return String is
     (if Ada.Environment_Variables.Exists (N) then Ada.Environment_Variables.Value (N) else "");

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   ---------------------------------------------------------------------------
   --  The choices, kept between games
   ---------------------------------------------------------------------------

   Track     : Tracks.Track_Id := 1;
   Laps      : Positive := 3;
   Opponents : Natural := 5;
   Level     : Race.Difficulty := Race.Normal;
   Players_Choice : Positive range 1 .. 2 := 1;   --  as chosen; a time trial is for one
   Items_On  : Boolean := True;
   Cameras   : array (View.Slot) of View.Camera_Kind := (others => View.Chase);
   Muted     : Boolean := False;
   Car_Choice : array (1 .. 2) of Natural := (0, 0);     --  each player's car body
   Paint_Choice : array (1 .. 2) of Natural := (0, 1);   --  and colour
   Sound_Volume : Natural range 0 .. 10 := 8;
   Music_Volume : Natural range 0 .. 10 := 5;
   type Voice_Choice is (Voice_Off, Voice_Woman, Voice_Man);
   Voice : Voice_Choice := Voice_Woman;

   --  The ways to play
   type Play_Kind is (Single_Race, Championship, Time_Trial, Duel_Play, Net_Play);
   Play : Play_Kind := Single_Race;

   function Play_Name (P : Play_Kind) return String is
     (case P is
         when Single_Race => "RACE",
         when Championship => "CHAMPIONSHIP",
         when Time_Trial => "TIME TRIAL",
         when Duel_Play => "DUEL",
         when Net_Play => "NETWORK GAME");

   --  The cups of the championship, as in the 2D game
   type Cup_Kind is (Car_Cup, House_Cup, Speed_Cup, Water_Air_Cup, Holiday_Cup, Strange_Cup, Frozen_Cup,
                     Grand_Tour);
   type Track_List is array (Positive range <>) of Tracks.Track_Id;
   Car_Tracks : constant Track_List := (1, 2, 3, 4, 14, 15);
   House_Tracks : constant Track_List := (11, 16, 20, 15);
   Frozen_Tracks : constant Track_List := (3, 16, 29, 23);
   Holiday_Tracks : constant Track_List := (21, 25, 23, 26);
   Odd_Tracks : constant Track_List := (27, 28, 24, 20);
   Speed_Tracks : constant Track_List := (9, 10, 12, 13, 22, 24);
   Water_Air_Tracks : constant Track_List := (5, 6, 17, 19, 7, 8, 18);
   All_Tracks : constant Track_List :=
     (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26,
      27, 28, 29);

   function Cup_Tracks (C : Cup_Kind) return Track_List is
     (case C is
         when Car_Cup => Car_Tracks,
         when House_Cup => House_Tracks,
         when Holiday_Cup => Holiday_Tracks,
         when Strange_Cup => Odd_Tracks,
         when Frozen_Cup => Frozen_Tracks,
         when Speed_Cup => Speed_Tracks,
         when Water_Air_Cup => Water_Air_Tracks,
         when Grand_Tour => All_Tracks);

   function Cup_Name (C : Cup_Kind) return String is
     (case C is
         when Car_Cup => "CAR CUP",
         when House_Cup => "HOUSE CUP",
         when Holiday_Cup => "HOLIDAY CUP",
         when Strange_Cup => "STRANGE WORLDS CUP",
         when Frozen_Cup => "SNOW AND ICE CUP",
         when Speed_Cup => "SPEED CUP",
         when Water_Air_Cup => "WATER AND AIR CUP",
         when Grand_Tour => "GRAND TOUR");

   Cup : Cup_Kind := Car_Cup;
   Round : Positive := 1;                --  the race of the cup being run
   Points : Overlay.Point_List := (others => 0);
   Scored : Boolean := False;            --  the points of this round are given
   Champ_Points : constant array (1 .. 6) of Natural := (10, 7, 5, 3, 2, 1);

   function Players return Positive is
     (case Play is when Time_Trial | Net_Play => 1, when Duel_Play => 2, when others => Players_Choice);

   --  The network game: who you are, where you joined last
   Player_Name : Race.Name_String := "PLAYER";
   Join_Address : Unbounded_String;

   function Trim_Name (N : String) return String is
      L : Natural := N'Last;
   begin
      while L >= N'First and then N (L) = ' ' loop
         L := L - 1;
      end loop;
      return N (N'First .. L);
   end Trim_Name;

   function As_Name (S : String) return Race.Name_String is
      N : Race.Name_String := (others => ' ');
   begin
      for K in 1 .. Natural'Min (S'Length, N'Length) loop
         N (K) := S (S'First + K - 1);
      end loop;
      return N;
   end As_Name;

   function Max_Opponents return Natural is (if Players = 2 then 4 else 5);

   function Rc_File return String is (Env ("HOME") & "/.adamachines3drc");

   procedure Save_Choices is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Rc_File);
      Put_Line (F, "track=" & Img (Track));
      Put_Line (F, "laps=" & Img (Laps));
      Put_Line (F, "opponents=" & Img (Opponents));
      Put_Line (F, "level=" & Race.Difficulty'Image (Level));
      Put_Line (F, "players=" & Img (Players_Choice));
      Put_Line (F, "play=" & Play_Kind'Image (Play));
      Put_Line (F, "cup=" & Cup_Kind'Image (Cup));
      Put_Line (F, "items=" & (if Items_On then "1" else "0"));
      Put_Line (F, "camera1=" & View.Camera_Kind'Image (Cameras (1)));
      Put_Line (F, "camera2=" & View.Camera_Kind'Image (Cameras (2)));
      Put_Line (F, "name=" & Trim_Name (Player_Name));
      Put_Line (F, "sound=" & Img (Sound_Volume));
      Put_Line (F, "time=" & Air.Time_Kind'Image (Air.Time));
      Put_Line (F, "weather=" & Air.Weather_Kind'Image (Air.Weather));
      Put_Line (F, "car1=" & Img (Car_Choice (1)));
      Put_Line (F, "car2=" & Img (Car_Choice (2)));
      Put_Line (F, "paint1=" & Img (Paint_Choice (1)));
      Put_Line (F, "paint2=" & Img (Paint_Choice (2)));
      Put_Line (F, "music=" & Img (Music_Volume));
      Put_Line (F, "voice=" & Voice_Choice'Image (Voice));
      Put_Line (F, "shadows=" & (if View.Shadows_On then "1" else "0"));
      Put_Line (F, "address=" & To_String (Join_Address));
      Close (F);
   exception
      when others => null;   --  nowhere to keep them: no matter
   end Save_Choices;

   procedure Load_Choices is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Open (F, In_File, Rc_File);
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
            Eq : constant Natural := Ada.Strings.Fixed.Index (L, "=");
         begin
            if Eq > 0 then
               declare
                  K : constant String := L (L'First .. Eq - 1);
                  V : constant String := L (Eq + 1 .. L'Last);
               begin
                  if K = "track" then Track := Tracks.Track_Id'Value (V);
                  elsif K = "laps" then Laps := Positive'Value (V);
                  elsif K = "opponents" then Opponents := Natural'Value (V);
                  elsif K = "level" then Level := Race.Difficulty'Value (V);
                  elsif K = "players" then Players_Choice := Positive'Value (V);
                  elsif K = "play" then Play := Play_Kind'Value (V);
                  elsif K = "cup" then Cup := Cup_Kind'Value (V);
                  elsif K = "items" then Items_On := V = "1";
                  elsif K = "camera1" then Cameras (1) := View.Camera_Kind'Value (V);
                  elsif K = "camera2" then Cameras (2) := View.Camera_Kind'Value (V);
                  elsif K = "name" and then V'Length > 0 then Player_Name := As_Name (V);
                  elsif K = "sound" then Sound_Volume := Natural'Value (V);
                  elsif K = "time" then Air.Time := Air.Time_Kind'Value (V);
                  elsif K = "weather" then Air.Weather := Air.Weather_Kind'Value (V);
                  elsif K = "car1" then Car_Choice (1) := Natural'Value (V) mod Models.Styles;
                  elsif K = "car2" then Car_Choice (2) := Natural'Value (V) mod Models.Styles;
                  elsif K = "paint1" then Paint_Choice (1) := Natural'Value (V) mod 8;
                  elsif K = "paint2" then Paint_Choice (2) := Natural'Value (V) mod 8;
                  elsif K = "music" then Music_Volume := Natural'Value (V);
                  elsif K = "voice" then Voice := Voice_Choice'Value (V);
                  elsif K = "shadows" then View.Shadows_On := V = "1";
                  elsif K = "address" then Join_Address := To_Unbounded_String (V);
                  end if;
               exception
                  when others => null;
               end;
            end if;
         end;
      end loop;
      Close (F);
      Laps := Positive'Min (Laps, 9);
      Opponents := Natural'Min (Opponents, Max_Opponents);
   exception
      when others => null;
   end Load_Choices;

   ---------------------------------------------------------------------------
   --  Where the game is
   ---------------------------------------------------------------------------

   type Mode_Kind is (Title, Racing, Paused, Results, Standings, Net_Menu, Host_Lobby, Browse, Client_Lobby,
                      Editing_Track, Options, Replay);
   Mode   : Mode_Kind := Title;
   Choice : Positive := 1;      --  the line chosen in the menu
   Ready  : Boolean := False;   --  the GL context is made, the world built
   Is_Fullscreen : Boolean := False;
   Show_Fps : Boolean := False;
   Autopilot : Boolean := False;
   World_Track : Tracks.Track_Id := 1;   --  the track the world was built for
   Change_T : Float := 0.0;    --  a track chosen on the title: built when the choosing stops
   Done_T : Float := 0.0;      --  every player over the line: seconds since
   From_Editor : Boolean := False;   --  a test drive: back to the editor after it
   Shift_Held : Boolean := False;

   Shot_Off : Boolean := True;   --  no screenshot being taken: the announcer may speak

   --  A few words across the screen for a moment: a lap, a record
   Message : String (1 .. 40) := (others => ' ');
   Message_Len : Natural := 0;
   Message_T : Float := 0.0;

   procedure Announce (Text : String) is
   begin
      if Voice /= Voice_Off and then not Muted and then Sound_Volume > 0 and then not Race.State.Attract
        and then Shot_Off
      then
         Speech.Voice := (if Voice = Voice_Man then Speech.Man else Speech.Woman);
         Speech.Loudness := 30 + 17 * Sound_Volume;
         Speech.Say (Text);
      end if;
   end Announce;

   function Spoken_Place (N : Positive) return String is
     (case N is
         when 1 => "first", when 2 => "second", when 3 => "third",
         when 4 => "fourth", when 5 => "fifth", when 6 => "sixth", when 7 => "seventh", when others => "eighth");

   procedure Say (Text : String; Seconds : Float := 1.8) is
   begin
      Message_Len := Natural'Min (Text'Length, Message'Length);
      Message (1 .. Message_Len) := Text (Text'First .. Text'First + Message_Len - 1);
      Message_T := Seconds;
   end Say;

   --  The network game, as it goes
   type Edit_Kind is (Not_Editing, Editing_Name, Editing_Address);
   Editing : Edit_Kind := Not_Editing;
   Edit_Text : Unbounded_String;
   Net_Steps : Natural := 0;
   Players_Seen : Natural := 0;
   Alone_Asked : Boolean := False;

   function Hosting return Boolean is (Net.Role = Net.Hosting);
   function Client return Boolean is (Net.Role = Net.Joined);
   function In_Net_Race return Boolean is (Race.State.Mode = Race.Net and then not Race.State.Attract);

   --  How hard each player's controller was just knocked: it fades
   Kicks : array (Pads.Player_Number) of Float := (others => 0.0);

   procedure Kick (Car : Natural; Amount : Float) is
      Who : Natural;
   begin
      if Car in 1 .. Race.State.Count then
         Who := Race.State.Racers (Car).Human;
         if In_Net_Race then
            Who := (if Who = Race.Local then 1 else 0);   --  only this machine's player feels it
         end if;
         if Who in Pads.Player_Number then
            Kicks (Who) := Float'Max (Kicks (Who), Float'Min (1.0, Amount));
         end if;
      end if;
   end Kick;

   procedure Update_Feel (Dt : Float) is
   begin
      if Mode /= Racing or else Race.State.Attract then
         Pads.Quiet;
         Kicks := (others => 0.0);
         return;
      end if;
      for P in 1 .. Players loop
         declare
            C : Cars.Car renames Race.State.Racers ((if In_Net_Race then Race.Focus else Race.Player (P))).Car;
            Rough : constant Float :=
              (if C.Air or else Cars.Falling (C) then 0.0
               elsif C.Under in Tracks.Floor | Tracks.Sand then Float'Min (1.0, C.Speed / 250.0)
               elsif C.Boost_T > 0.0 then 0.5
               else 0.0);
         begin
            Pads.Feel (P, Kicks (P), Rough, C.Speed / Cars.Top_Speed);
            Kicks (P) := Float'Max (0.0, Kicks (P) - 3.0 * Dt);
         end;
      end loop;
   end Update_Feel;

   --  The time trial: the laps kept, the ghost of the best one shown
   Seen_Lap : Natural := 0;
   Was_Running : Boolean := False;
   Ghost_Step : Natural := 0;

   --  Screenshots, to look at the game without playing it
   Shot_File : access String := null;
   Shot_At   : Float := 6.0;   --  seconds of race
   Shot_After : Float := 0.0;  --  or: seconds of the game running as it would, then the picture
   Run_T : Float := 0.0;
   Auto_Host : Natural := 0;   --  host, and start once this many players are in

   type Pad is record
      Left, Right, Up, Down : Boolean := False;
   end record;
   Arrows, Letters : Pad;
   Fire_Pending : array (View.Slot) of Boolean := (others => False);

   Accum   : Float := 0.0;
   Last_T  : Time := Clock;
   Events_Read : Natural := 0;

   procedure Build_World is
   begin
      if Ready then
         GL_Area_Make_Current (Area_C);
         View.New_Track;
      end if;
      World_Track := Tracks.Current;
   end Build_World;

   procedure Start_Attract is
   begin
      Race.Split_Screen := False;
      View.Ghost_On := False;
      Race.Setup ((if Play = Championship then Cup_Tracks (Cup) (1) else Track), Race.Single, 5, 3, Race.Normal, Attract => True);
      Events_Read := Race.Event_Serial;
      Accum := 0.0;
      Build_World;
      --  a little way into the race, so the cars are not all on the line
      for K in 1 .. 600 loop
         Race.Step ((others => <>), Autopilot => True);
      end loop;
      View.New_Race;
   end Start_Attract;

   --  Each player's car as they chose it: its body, and its colour (swapped with whoever had it)
   procedure Dress_Cars is
      St : Race.State_Type renames Race.State;
   begin
      for I in Race.Car_Index loop
         View.Styles (I) := (I - 1) mod Models.Styles;
      end loop;
      for P in 1 .. Players loop
         declare
            Me : constant Race.Car_Index := Race.Player (P);
            Want : constant Natural := Paint_Choice (P);
         begin
            View.Styles (Me) := Car_Choice (P);
            if P = 1 or else Want /= Paint_Choice (1) then
               for J in 1 .. St.Count loop
                  if J /= Me and then St.Racers (J).Paint = Want then
                     St.Racers (J).Paint := St.Racers (Me).Paint;
                  end if;
               end loop;
               St.Racers (Me).Paint := Want;
            end if;
         end;
      end loop;
   end Dress_Cars;

   --  The race as it was run, to be run again for the replay: how it was set up,
   --  and what was pressed at every step of it
   package Input_Lists is new Ada.Containers.Vectors (Natural, Race.Input, Race."=");
   Recording : Input_Lists.Vector;
   type Setup_Record is record
      Id : Tracks.Track_Id := 1;
      Mode : Race.Game_Mode := Race.Single;
      Opponents : Natural := 0;
      Laps : Positive := 3;
      Level : Race.Difficulty := Race.Normal;
      Items : Boolean := True;
      View_W, View_H : Float := 1000.0;
      Split : Boolean := False;
   end record;
   Rec : Setup_Record;
   Can_Replay : Boolean := False;   --  a race was run here that can be watched again
   Replay_Pos : Natural := 0;
   Replay_Car : Race.Car_Index := 1;
   Replay_Cam : View.Camera_Kind := View.TV;
   Replay_End_T : Float := 0.0;

   function Race_Track return Tracks.Track_Id is
     (if Play = Championship then Cup_Tracks (Cup) (Round) else Track);

   procedure Start_Race is
   begin
      Race.Split_Screen := Players = 2 and then Play /= Duel_Play;
      Rec := (Id => Race_Track,
              Mode => (case Play is
                          when Time_Trial => Race.Trial,
                          when Duel_Play => Race.Duel,
                          when others => (if Players = 2 then Race.Double else Race.Single)),
              Opponents => (if Play in Time_Trial | Duel_Play then 0 else Natural'Min (Opponents, Max_Opponents)),
              Laps => Laps, Level => Level, Items => Items_On and then Play /= Time_Trial,
              View_W => Race.State.View_W, View_H => Race.State.View_H, Split => Race.Split_Screen);
      Race.Setup (Rec.Id, Rec.Mode, Rec.Opponents, Rec.Laps, Rec.Level, Items => Rec.Items);
      Recording.Clear;
      Can_Replay := True;
      Dress_Cars;
      Scored := False;
      Seen_Lap := 0;
      Was_Running := False;
      Message_T := 0.0;
      View.Ghost_On := False;
      if Play = Time_Trial then
         Records.Load_Ghost (Race_Track);
      end if;
      Events_Read := Race.Event_Serial;
      Accum := 0.0;
      Done_T := 0.0;
      if World_Track /= Race_Track or else not Ready then
         Build_World;
      else
         View.New_Race;
      end if;
      Mode := Racing;
      Fire_Pending := (others => False);
      Announce ((if Play = Championship and then Round = 1 then Cup_Name (Cup) & ". " else "")
                & (if Play = Duel_Play then "Duel on " else "") & Tracks.Name (Race_Track) & ". Get ready!");
   end Start_Race;

   --  A network race: everyone sets it up the same, from the lobby
   procedure Start_Net_Race is
      L : Net.Lobby_Info renames Net.Lobby;
   begin
      Can_Replay := False;   --  the host runs it: nothing to watch again here
      Race.Split_Screen := False;
      Race.Local := (if Hosting then 1 else Natural'Max (1, Net.Me));
      Race.Setup_Net (L.Track, Natural'Max (1, L.Players), L.Names, L.AIs, L.Laps, L.Level, L.Items);
      Track := L.Track;
      Seen_Lap := 0;
      Message_T := 0.0;
      View.Ghost_On := False;
      Events_Read := Race.Event_Serial;
      Accum := 0.0;
      Done_T := 0.0;
      Net_Steps := 0;
      Editing := Not_Editing;
      if World_Track /= L.Track or else not Ready then
         Build_World;
      else
         View.New_Race;
      end if;
      Mode := Racing;
      Fire_Pending := (others => False);
      Announce (Tracks.Name (L.Track) & ". Get ready!");
   end Start_Net_Race;

   --  The race behind the lobby: on the track chosen there
   procedure Lobby_Attract is
   begin
      if Track /= Net.Lobby.Track or else not Race.State.Attract then
         Track := Net.Lobby.Track;
         Start_Attract;
      end if;
   end Lobby_Attract;

   procedure Begin_Hosting is
      L : Net.Lobby_Info renames Net.Lobby;
   begin
      if not Net.Host (Player_Name) then
         Say ("A GAME IS HOSTED HERE ALREADY", 3.0);
         return;
      end if;
      L.Track := Track;
      L.Laps := Laps;
      L.Level := Level;
      L.Items := Items_On;
      L.AIs := Natural'Min (3, Race.Max_Cars - 1);
      Alone_Asked := False;
      Players_Seen := 1;
      Net.Changed;
      Mode := Host_Lobby;
      Choice := 1;
      Lobby_Attract;
   end Begin_Hosting;

   procedure Leave_Net is
   begin
      Net.Stop;
      Editing := Not_Editing;
      Mode := Net_Menu;
      Choice := 1;
      if not Race.State.Attract then
         Start_Attract;
      end if;
   end Leave_Net;

   --  The race once more, as it was: the same start, the same keys at every step
   procedure Start_Replay is
   begin
      Race.Split_Screen := Rec.Split;
      Race.State.View_W := Rec.View_W;
      Race.State.View_H := Rec.View_H;
      Race.Setup (Rec.Id, Rec.Mode, Rec.Opponents, Rec.Laps, Rec.Level, Items => Rec.Items);
      Dress_Cars;
      View.Ghost_On := False;
      Events_Read := Race.Event_Serial;
      Accum := 0.0;
      Replay_Pos := 0;
      Replay_End_T := 0.0;
      Replay_Car := Race.Player (1);
      Replay_Cam := View.TV;
      View.New_Race;
      Mode := Replay;
   end Start_Replay;

   --  Out of the replay: the rest of it run at once, so the race ends as it did
   procedure End_Replay is
   begin
      while Replay_Pos < Natural (Recording.Length) loop
         Race.Step (Recording (Replay_Pos), Autopilot => Autopilot);
         Replay_Pos := Replay_Pos + 1;
      end loop;
      Events_Read := Race.Event_Serial;
      Mode := Results;
      Choice := 1;
   end End_Replay;

   procedure Start_Game is
   begin
      Round := 1;
      Points := (others => 0);
      Start_Race;
   end Start_Game;

   --  The points of the round, once
   procedure Score_Round is
   begin
      if Play = Championship and then not Scored then
         for K in 1 .. Race.State.Count loop
            if K <= Champ_Points'Last then
               Points (Race.In_Place (K)) := Points (Race.In_Place (K)) + Champ_Points (K);
            end if;
         end loop;
         Scored := True;
      end if;
   end Score_Round;

   procedure To_Title is
   begin
      if Net.Role /= Net.Off then
         Net.Stop;
      end if;
      Editing := Not_Editing;
      if From_Editor then
         --  back from a test drive, to go on with the track
         From_Editor := False;
         Mode := Editing_Track;
         Start_Attract;
         return;
      end if;
      Mode := Title;
      Choice := 1;
      Start_Attract;
   end To_Title;

   ---------------------------------------------------------------------------
   --  The menus
   ---------------------------------------------------------------------------

   type Title_Line is (Go, Line_Play, Line_Players, Line_Track, Line_Laps, Line_Opponents, Line_Level, Line_Items,
                       Line_Time, Line_Weather, Line_Camera_1, Line_Camera_2, Line_Options, Line_Editor, Line_Quit);
   type Option_Line is (Opt_Car_1, Opt_Paint_1, Opt_Car_2, Opt_Paint_2, Opt_Sound, Opt_Music, Opt_Voice, Opt_Shadows,
                        Opt_Pad_1, Opt_Pad_2, Opt_Back);
   Return_To : Mode_Kind := Title;   --  where the options go back to


   --  The tracks in turn: the built-in ones, then those made in the editor and kept
   function Next_Track (T : Tracks.Track_Id; Dir : Integer) return Tracks.Track_Id is
      N : Integer := T;
   begin
      loop
         N := N + Dir;
         if N > Tracks.Track_Count then
            N := 1;
         elsif N < 1 then
            N := Tracks.Track_Count;
         end if;
         exit when not Tracks.Is_Custom (N) or else Tracks.Slots (Tracks.Slot_Of (N)).Saved;
      end loop;
      return N;
   end Next_Track;
   type Pause_Line is (Go_On, Again, Pause_Options, Leave);

   function Lines return Positive is
     (case Mode is
         when Title => Title_Line'Pos (Title_Line'Last) + 1,
         when Paused => (if In_Net_Race then 2 else Pause_Line'Pos (Pause_Line'Last) + 1),
         when Net_Menu => 4,
         when Options => Option_Line'Pos (Option_Line'Last) + 1,
         when Host_Lobby => 7,
         when Browse => Net.N_Found + 2,
         when others => 1);

   function Turn (V, Dir, Lo, Hi : Integer) return Integer is
     (if V + Dir > Hi then Lo elsif V + Dir < Lo then Hi else V + Dir);

   function Title_At return Title_Line is (Title_Line'Val (Choice - 1));

   function Pad_Name (P : Pads.Player_Number) return String is
     (case Pads.Chosen (P) is
         when -1 => "NONE",
         when 0 => "ANY: THE FIRST PRESSED",
         when others => Pads.Device_Name (Pads.Chosen (P)));

   procedure Change (Dir : Integer) is
   begin
      if Mode = Options then
         case Option_Line'Val (Choice - 1) is
            when Opt_Sound =>
               Sound_Volume := Natural'Max (0, Natural'Min (10, Sound_Volume + Dir));
               Audio.Play (Audio.Beep_Low, 0.8);
            when Opt_Music => Music_Volume := Natural'Max (0, Natural'Min (10, Music_Volume + Dir));
            when Opt_Voice =>
               Voice := Voice_Choice'Val ((Voice_Choice'Pos (Voice) + (if Dir > 0 then 1 else 2)) mod 3);
               if Voice /= Voice_Off then
                  Speech.Voice := (if Voice = Voice_Man then Speech.Man else Speech.Woman);
                  Speech.Loudness := 30 + 17 * Sound_Volume;
                  Speech.Say ("Ready to race!");
               end if;
            when Opt_Shadows => View.Shadows_On := not View.Shadows_On;
            when Opt_Pad_1 | Opt_Pad_2 =>
               declare
                  P : constant Pads.Player_Number := (if Option_Line'Val (Choice - 1) = Opt_Pad_1 then 1 else 2);
               begin
                  Pads.Choose (P, Turn (Pads.Chosen (P), Dir, -1, Pads.Device_Count));
               end;
            when Opt_Car_1 => Car_Choice (1) := Turn (Car_Choice (1), Dir, 0, Models.Styles - 1);
            when Opt_Car_2 => Car_Choice (2) := Turn (Car_Choice (2), Dir, 0, Models.Styles - 1);
            when Opt_Paint_1 => Paint_Choice (1) := Turn (Paint_Choice (1), Dir, 0, 7);
            when Opt_Paint_2 => Paint_Choice (2) := Turn (Paint_Choice (2), Dir, 0, 7);
            when Opt_Back => null;
         end case;
         Save_Choices;
         return;
      end if;
      if Mode = Host_Lobby then
         declare
            L : Net.Lobby_Info renames Net.Lobby;
         begin
            case Choice is
               when 2 =>
                  L.Track := Turn (L.Track, Dir, 1, Tracks.Built_In_Count);
                  Change_T := 0.45;
               when 3 => L.Laps := Turn (L.Laps, Dir, 1, 9);
               when 4 =>
                  L.AIs := Turn (L.AIs, Dir, (if L.Players <= 1 then 1 else 0),
                                 Race.Max_Cars - Natural'Max (1, L.Players));
               when 5 => L.Level := Race.Difficulty'Val (Turn (Race.Difficulty'Pos (L.Level), Dir, 0, 2));
               when 6 => L.Items := not L.Items;
               when others => null;
            end case;
            Net.Changed;
            Audio.Play (Audio.Beep_Low, 0.5);
         end;
         return;
      end if;
      if Mode /= Title then
         return;
      end if;
      case Title_At is
         when Line_Play =>
            Play := (if Dir > 0 then (if Play = Play_Kind'Last then Play_Kind'First else Play_Kind'Succ (Play))
                     else (if Play = Play_Kind'First then Play_Kind'Last else Play_Kind'Pred (Play)));
            Change_T := 0.45;
         when Line_Players =>
            if Play in Single_Race | Championship then
               Players_Choice := (if Players_Choice = 1 then 2 else 1);
            end if;
            Opponents := Natural'Min (Opponents, Max_Opponents);
         when Line_Track =>
            if Play = Championship then
               Cup := (if Dir > 0 then (if Cup = Cup_Kind'Last then Cup_Kind'First else Cup_Kind'Succ (Cup))
                       else (if Cup = Cup_Kind'First then Cup_Kind'Last else Cup_Kind'Pred (Cup)));
            else
               Track := Next_Track (Track, Dir);
            end if;
            Change_T := 0.45;
         when Line_Laps =>
            Laps := Positive'Max (1, Positive'Min (9, Laps + Dir));
         when Line_Opponents =>
            Opponents := Natural'Max (0, Natural'Min (Max_Opponents, Opponents + Dir));
         when Line_Level =>
            Level := (if Dir > 0 then (if Level = Race.Difficulty'Last then Race.Difficulty'First
                                       else Race.Difficulty'Succ (Level))
                      else (if Level = Race.Difficulty'First then Race.Difficulty'Last
                            else Race.Difficulty'Pred (Level)));
         when Line_Items =>
            Items_On := not Items_On;
         when Line_Time =>
            Air.Time := Air.Time_Kind'Val (Turn (Air.Time_Kind'Pos (Air.Time), Dir, 0, 2));
            Change_T := 0.45;
         when Line_Weather =>
            Air.Weather := Air.Weather_Kind'Val (Turn (Air.Weather_Kind'Pos (Air.Weather), Dir, 0, 2));
            Change_T := 0.45;
         when Line_Camera_1 | Line_Camera_2 =>
            declare
               S : constant View.Slot := (if Title_At = Line_Camera_1 then 1 else 2);
            begin
               Cameras (S) := View.Camera_Kind'Val
                 (Turn (View.Camera_Kind'Pos (Cameras (S)), Dir, View.Camera_Kind'Pos (View.Player_Camera'First),
                        View.Camera_Kind'Pos (View.Player_Camera'Last)));
            end;
         when Go | Line_Quit | Line_Editor | Line_Options =>
            null;
      end case;
      Audio.Play (Audio.Beep_Low, 0.5);
   end Change;

   procedure Choose is
   begin
      case Mode is
         when Title =>
            case Title_At is
               when Go =>
                  Save_Choices;
                  Audio.Play (Audio.Beep_High, 0.7);
                  if Play = Net_Play then
                     Mode := Net_Menu;
                     Choice := 1;
                  else
                     Start_Game;
                  end if;
               when Line_Quit =>
                  Save_Choices;
                  Gtk.Main.Main_Quit;
               when Line_Options =>
                  Return_To := Title;
                  Mode := Options;
                  Choice := 1;
               when Line_Editor =>
                  Editor.Open ((if Tracks.Is_Custom (Track) then Tracks.Slot_Of (Track) else Editor.Current));
                  Mode := Editing_Track;
               when others =>
                  Change (1);
            end case;
         when Paused =>
            if In_Net_Race then
               if Choice = 1 then
                  Mode := Racing;
               else
                  Leave_Net;
               end if;
               return;
            end if;
            case Pause_Line'Val (Choice - 1) is
               when Go_On => Mode := Racing;
               when Again => Start_Race;
               when Pause_Options =>
                  Return_To := Paused;
                  Mode := Options;
                  Choice := 1;
               when Leave => To_Title;
            end case;
         when Results =>
            if In_Net_Race then
               if Hosting then
                  Net.Host_Lobby;
                  Mode := Host_Lobby;
                  Choice := 1;
                  Start_Attract;
               end if;   --  a player who joined waits for the host
            elsif Play = Championship then
               Score_Round;
               Mode := Standings;
               if Round = Cup_Tracks (Cup)'Last then
                  declare
                     Me : constant Race.Car_Index := Race.Player (1);
                     Ahead : Natural := 0;
                  begin
                     for K in 1 .. Race.State.Count loop
                        if Points (K) > Points (Me) then
                           Ahead := Ahead + 1;
                        end if;
                     end loop;
                     Announce ((if Ahead = 0 then "You are the champion!"
                                else "You finished " & Spoken_Place (Ahead + 1) & " in the " & Cup_Name (Cup) & "."));
                  end;
               end if;
            else
               To_Title;
            end if;
         when Standings =>
            if Round < Cup_Tracks (Cup)'Last then
               Round := Round + 1;
               Start_Race;
            else
               To_Title;
            end if;
         when Racing =>
            null;
         when Net_Menu =>
            case Choice is
               when 1 => Begin_Hosting;
               when 2 =>
                  Net.Browse;
                  Mode := Browse;
                  Choice := 1;
               when 3 =>
                  Editing := Editing_Name;
                  Edit_Text := To_Unbounded_String (Trim_Name (Player_Name));
               when others =>
                  Mode := Title;
                  Choice := 1;
            end case;
         when Host_Lobby =>
            case Choice is
               when 1 =>
                  if Net.Lobby.Players <= 1 and then not Alone_Asked then
                     Alone_Asked := True;
                     Say ("NOBODY HAS JOINED. ENTER AGAIN TO RACE ALONE", 3.0);
                  else
                     Alone_Asked := False;
                     Net.Host_Start;
                     Start_Net_Race;
                  end if;
               when 7 => Leave_Net;
               when others => Change (1);
            end case;
         when Browse =>
            if Choice <= Net.N_Found then
               Net.Join (To_String (Net.Found (Choice).Address), Player_Name);
            elsif Choice = Net.N_Found + 1 then
               Editing := Editing_Address;
               Edit_Text := Join_Address;
            else
               Leave_Net;
            end if;
         when Client_Lobby =>
            Leave_Net;
         when Editing_Track =>
            null;
         when Replay =>
            End_Replay;
         when Options =>
            if Option_Line'Val (Choice - 1) = Opt_Back then
               Mode := Return_To;
               Choice := (if Return_To = Title then Title_Line'Pos (Line_Options) + 1 else 3);
            else
               Change (1);
            end if;
      end case;
   end Choose;

   procedure Menu_Move (Dir : Integer) is
   begin
      Choice := (if Dir < 0 then (if Choice = 1 then Lines else Choice - 1)
                 else (if Choice = Lines then 1 else Choice + 1));
      Audio.Play (Audio.Beep_Low, 0.4);
   end Menu_Move;

   procedure Back is
   begin
      case Mode is
         when Title => Choice := Title_Line'Pos (Line_Quit) + 1;
         when Paused => Mode := Racing;
         when Results =>
            if In_Net_Race and then Client then
               Leave_Net;
            else
               Choose;
            end if;
         when Standings => Choose;
         when Racing => null;
         when Net_Menu => Mode := Title; Choice := 1;
         when Host_Lobby | Browse | Client_Lobby => Leave_Net;
         when Editing_Track => null;
         when Replay => End_Replay;
         when Options =>
            Mode := Return_To;
            Choice := 1;
      end case;
   end Back;

   procedure Pause is
   begin
      if Mode = Racing then
         Mode := Paused;
         Choice := 1;
      elsif Mode = Paused then
         Mode := Racing;
      end if;
   end Pause;

   procedure Next_Camera (S : View.Slot) is
   begin
      Cameras (S) := (if Cameras (S) >= View.Player_Camera'Last then View.Player_Camera'First
                      else View.Camera_Kind'Succ (Cameras (S)));
   end Next_Camera;

   --  Something pressed on a controller
   procedure Pad_Action (P : Natural; A : Pads.Action) is
      S : constant View.Slot := (if P = 2 and then Players = 2 then 2 else 1);
   begin
      case Mode is
         when Title | Paused | Results | Standings | Net_Menu | Host_Lobby | Browse | Client_Lobby | Options =>
            case A is
               when Pads.Up => Menu_Move (-1);
               when Pads.Down => Menu_Move (1);
               when Pads.Left => Change (-1);
               when Pads.Right => Change (1);
               when Pads.Ok => Choose;
               when Pads.Back => Back;
               when Pads.Pause =>
                  if Mode = Title then
                     Choose;
                  else
                     Pause;
                  end if;
               when Pads.Restart =>
                  if Mode in Paused | Results and then Play not in Championship | Net_Play then
                     Start_Race;
                  end if;
               when Pads.Camera =>
                  if Mode = Results and then Can_Replay then
                     Start_Replay;
                  end if;
               when Pads.Fire => null;
            end case;
         when Editing_Track =>
            null;
         when Replay =>
            case A is
               when Pads.Ok | Pads.Back | Pads.Pause => End_Replay;
               when Pads.Left | Pads.Right =>
                  Replay_Car := (if A = Pads.Right then (if Replay_Car >= Race.State.Count then 1 else Replay_Car + 1)
                                 else (if Replay_Car = 1 then Race.State.Count else Replay_Car - 1));
                  View.New_Race;
               when Pads.Camera =>
                  Replay_Cam := (if Replay_Cam = View.Camera_Kind'Last then View.Camera_Kind'First
                                 else View.Camera_Kind'Succ (Replay_Cam));
               when others => null;
            end case;
         when Racing =>
            case A is
               when Pads.Fire => Fire_Pending (S) := True;
               when Pads.Camera => Next_Camera (S);
               when Pads.Pause => Pause;
               when Pads.Restart =>
                  if Play not in Championship | Net_Play then
                     Start_Race;
                  end if;
               when others => null;
            end case;
      end case;
   end Pad_Action;

   ---------------------------------------------------------------------------
   --  Keys
   ---------------------------------------------------------------------------

   procedure Set_Key (K : Gdk.Types.Gdk_Key_Type; Down : Boolean) is
      use Gdk.Types.Keysyms;
   begin
      if K = GDK_Left then Arrows.Left := Down;
      elsif K = GDK_Right then Arrows.Right := Down;
      elsif K = GDK_Up then Arrows.Up := Down;
      elsif K = GDK_Down then Arrows.Down := Down;
      elsif K = GDK_LC_a or else K = GDK_A then Letters.Left := Down;
      elsif K = GDK_LC_d or else K = GDK_D then Letters.Right := Down;
      elsif K = GDK_LC_w or else K = GDK_W then Letters.Up := Down;
      elsif K = GDK_LC_s or else K = GDK_S then Letters.Down := Down;
      end if;
   end Set_Key;

   --  A name or an address being typed
   procedure Edit_Key (K : Gdk.Types.Gdk_Key_Type) is
      use Gdk.Types.Keysyms;
      Code : constant Natural := Natural (K);
      Most : constant Positive := (if Editing = Editing_Name then 6 else 40);
   begin
      if K = GDK_Return or else K = GDK_KP_Enter then
         if Editing = Editing_Name then
            if Length (Edit_Text) > 0 then
               Player_Name := As_Name (To_String (Edit_Text));
            end if;
         else
            Join_Address := Edit_Text;
            if Length (Join_Address) > 0 then
               Net.Join (To_String (Join_Address), Player_Name);
            end if;
         end if;
         Editing := Not_Editing;
         Save_Choices;
      elsif K = GDK_Escape then
         Editing := Not_Editing;
      elsif K = GDK_BackSpace then
         if Length (Edit_Text) > 0 then
            Delete (Edit_Text, Length (Edit_Text), Length (Edit_Text));
         end if;
      elsif Code in 32 .. 126 and then Length (Edit_Text) < Most then
         declare
            C : constant Character := Character'Val (Code);
         begin
            if Editing = Editing_Name then
               if C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | ' ' | '-' | '!' then
                  Append (Edit_Text, (if C in 'a' .. 'z' then Character'Val (Code - 32) else C));
               end if;
            elsif C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | ':' | '-' then
               Append (Edit_Text, C);
            end if;
         end;
      end if;
   end Edit_Key;

   function Key_Press (Self : access Gtk_Widget_Record'Class;
                       Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Types.Keysyms;
      K : constant Gdk.Types.Gdk_Key_Type := Event.Keyval;
      Fire_1 : constant Boolean := K = GDK_Control_R or else K = GDK_Shift_R or else K = GDK_Return
        or else K = GDK_KP_Enter;
      Fire_2 : constant Boolean := K = GDK_Control_L or else K = GDK_Shift_L or else K = GDK_space
        or else K = GDK_LC_q or else K = GDK_Q;
   begin
      if Editing /= Not_Editing then
         Edit_Key (K);
         return True;
      end if;
      if K = GDK_Shift_L or else K = GDK_Shift_R then
         Shift_Held := True;
      end if;
      if Mode = Editing_Track then
         declare
            Result : Editor.Action;
         begin
            Editor.Key (K, Shift_Held, Result);
            case Result is
               when Editor.None => null;
               when Editor.Test_Drive =>
                  Track := Tracks.First_Custom + Editor.Current - 1;
                  Play := Single_Race;
                  From_Editor := True;
                  Start_Game;
               when Editor.Leave =>
                  if Tracks.Slots (Editor.Current).Saved then
                     Track := Tracks.First_Custom + Editor.Current - 1;
                  end if;
                  Mode := Title;
                  Choice := 1;
                  Start_Attract;
            end case;
         end;
         return True;
      end if;
      Set_Key (K, True);
      if K = GDK_F11 then
         Is_Fullscreen := not Is_Fullscreen;
         if Is_Fullscreen then
            Window.Fullscreen;
         else
            Window.Unfullscreen;
         end if;
      elsif K = GDK_F3 then
         Show_Fps := not Show_Fps;
      elsif K = GDK_LC_m or else K = GDK_M then
         Muted := not Muted;
      elsif Mode = Replay then
         if K = GDK_Escape or else K = GDK_Return or else K = GDK_KP_Enter then
            End_Replay;
         elsif K = GDK_Right or else K = GDK_Left then
            Replay_Car := (if K = GDK_Right then (if Replay_Car >= Race.State.Count then 1 else Replay_Car + 1)
                           else (if Replay_Car = 1 then Race.State.Count else Replay_Car - 1));
            View.New_Race;
         elsif K = GDK_LC_c or else K = GDK_C then
            Replay_Cam := (if Replay_Cam = View.Camera_Kind'Last then View.Camera_Kind'First
                           else View.Camera_Kind'Succ (Replay_Cam));
         end if;
      elsif Mode = Racing then
         if K = GDK_Escape or else K = GDK_LC_p or else K = GDK_P then
            Pause;
         elsif K = GDK_LC_c or else K = GDK_C then
            Next_Camera (1);
         elsif K = GDK_LC_v or else K = GDK_V then
            Next_Camera ((if Players = 2 then 2 else 1));
         elsif (K = GDK_LC_r or else K = GDK_R) and then Play not in Championship | Net_Play then
            Start_Race;
         elsif Fire_1 or else Fire_2 then
            Fire_Pending ((if Players = 2 and then Fire_2 then 2 else 1)) := True;
         end if;
      else
         if Mode = Results and then Can_Replay and then (K = GDK_LC_w or else K = GDK_W) then
            Start_Replay;
         elsif K = GDK_Up or else K = GDK_LC_w or else K = GDK_W then
            Menu_Move (-1);
         elsif K = GDK_Down or else K = GDK_LC_s or else K = GDK_S then
            Menu_Move (1);
         elsif K = GDK_Left or else K = GDK_LC_a or else K = GDK_A then
            Change (-1);
         elsif K = GDK_Right or else K = GDK_LC_d or else K = GDK_D then
            Change (1);
         elsif K = GDK_Return or else K = GDK_KP_Enter or else K = GDK_space then
            Choose;
         elsif K = GDK_Escape then
            Back;
         elsif Mode = Paused and then (K = GDK_LC_p or else K = GDK_P) then
            Pause;
         elsif Mode in Paused | Results and then Play not in Championship | Net_Play
           and then (K = GDK_LC_r or else K = GDK_R)
         then
            Start_Race;
         elsif Mode = Results and then Play not in Championship | Net_Play and then (K = GDK_LC_n or else K = GDK_N) then
            Track := (if Track >= Tracks.Built_In_Count then 1 else Track + 1);
            Save_Choices;
            Start_Race;
         end if;
      end if;
      return True;
   end Key_Press;

   function Key_Release (Self : access Gtk_Widget_Record'Class;
                         Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Types.Keysyms;
   begin
      if Event.Keyval = GDK_Shift_L or else Event.Keyval = GDK_Shift_R then
         Shift_Held := False;
      end if;
      Set_Key (Event.Keyval, False);
      return True;
   end Key_Release;

   function Of_Keys (P : Pad) return Cars.Controls is
     ((Steer => (if P.Left then -1.0 else 0.0) + (if P.Right then 1.0 else 0.0),
       Throttle => (if P.Up then 1.0 else 0.0),
       Brake => (if P.Down then 1.0 else 0.0)));

   --  The keys and the controller together
   function With_Pad (C : Cars.Controls; R : Pads.Reading) return Cars.Controls is
     ((Steer => Clamp (C.Steer + R.Steer, -1.0, 1.0),
       Throttle => Float'Max (C.Throttle, R.Throttle),
       Brake => Float'Max (C.Brake, R.Brake)));

   function Player_Input return Race.Input is
      I : Race.Input;
   begin
      if Players = 1 then
         I.P1 := Of_Keys ((Arrows.Left or else Letters.Left, Arrows.Right or else Letters.Right,
                           Arrows.Up or else Letters.Up, Arrows.Down or else Letters.Down));
         I.P1 := With_Pad (With_Pad (I.P1, Pads.Get (1)), Pads.Get (2));
         I.Fire1 := Fire_Pending (1) or else Fire_Pending (2);
      else
         I.P1 := With_Pad (Of_Keys (Arrows), Pads.Get (1));
         I.P2 := With_Pad (Of_Keys (Letters), Pads.Get (2));
         I.Fire1 := Fire_Pending (1);
         I.Fire2 := Fire_Pending (2);
      end if;
      Fire_Pending := (others => False);
      return I;
   end Player_Input;

   ---------------------------------------------------------------------------
   --  Sound
   ---------------------------------------------------------------------------

   function Pan_Of (P : Vec) return Float is
     (Clamp (Dot (P - View.Ear, View.Ear_Right) / 250.0, -1.0, 1.0));

   function Near_Level (P : Vec) return Float is
     (Clamp (1.3 - Distance (P, View.Ear) / 900.0, 0.0, 1.0));

   procedure Hear_Events is
      use Race;
      From : Natural := Events_Read;
      Racing_Now : constant Boolean := not State.Attract;
   begin
      if Event_Serial - From > Event_Ring then
         From := Event_Serial - Event_Ring;
      end if;
      for K in From .. Event_Serial - 1 loop
         declare
            E : constant Race.Event := Events (K mod Event_Ring);
            Mine : constant Boolean :=
              Racing_Now and then Mode /= Replay and then E.Car in 1 .. State.Count
              and then (if State.Mode = Race.Net then State.Racers (E.Car).Human = Local
                        else State.Racers (E.Car).Human > 0);
            Lv : constant Float := (if Mine then 1.0 else Near_Level (E.P)) * (if Racing_Now then 1.0 else 0.5);
            Pn : constant Float := (if Mine and then Players = 1 then 0.0 else Pan_Of (E.P));
         begin
            View.Hear (E);
            case E.Kind is
               when Bump =>
                  Audio.Play (Audio.Thud, Lv * Float'Min (1.0, E.Size / 180.0), Pn);
                  Kick (E.Car, E.Size / 220.0);
                  if Mine then
                     View.Shake ((if State.Racers (E.Car).Human = 2 then 2 else 1), Float'Min (4.0, E.Size / 50.0));
                  end if;
               when Fell =>
                  Kick (E.Car, 0.6);
                  if Tracks.Theme in Tracks.Workbench | Tracks.Bath then
                     Audio.Play (Audio.Fall, Lv * 0.8, Pn);
                  else
                     Audio.Play (Audio.Splash, Lv, Pn);
                  end if;
               when Splash => Audio.Play (Audio.Splash, Lv * 0.35, Pn);
               when Jumped => Audio.Play (Audio.Jump, Lv * 0.7, Pn);
               when Landed =>
                  Audio.Play (Audio.Land, Lv * 0.8, Pn);
                  Kick (E.Car, 0.45);
               when Boosted => Audio.Play (Audio.Whoosh, Lv * 0.8, Pn);
               when Put_Back => Audio.Play (Audio.Zap, Lv * 0.5, Pn);
               when Beep => if Racing_Now then Audio.Play (Audio.Beep_Low, 0.8); end if;
               when Go => if Racing_Now then Audio.Play (Audio.Beep_High, 0.9); end if;
               when Lap_Done | Final_Lap | Race.Finished =>
                  if Mine and then Mode /= Replay then
                     if Records.Offer_Lap (Tracks.Current, State.Racers (E.Car).Last_Lap) then
                        Say ("NEW LAP RECORD!", 2.5);
                        Audio.Play (Audio.Chime, 0.9);
                        Announce ("New lap record!");
                     elsif E.Kind = Final_Lap then
                        Say ("FINAL LAP");
                        Announce ("Final lap!");
                     elsif E.Kind = Lap_Done and then Play /= Time_Trial then
                        Say ("LAP " & Img (Lap_Shown (E.Car)), 1.2);
                     end if;
                     Audio.Play ((if E.Kind = Race.Finished then Audio.Fanfare else Audio.Lap), 0.8);
                     if E.Kind = Race.Finished and then Play /= Time_Trial then
                        declare
                           P : constant Positive := State.Racers (E.Car).Place;
                           Who : constant String :=
                             (if Players = 2 then "Player " & (if State.Racers (E.Car).Human = 1 then "one" else "two")
                              else "");
                        begin
                           Announce ((if P = 1 then (if Who = "" then "You win!" else Who & " wins!")
                                      else (if Who = "" then "You finished " else Who & " finished ")
                                           & Spoken_Place (P) & "."));
                        end;
                     end if;
                  end if;
               when Picked => Audio.Play (Audio.Pickup, (if Mine then 0.8 else Lv * 0.35), Pn);
               when Fired => Audio.Play (Audio.Launch, Lv, Pn);
               when Dropped => Audio.Play (Audio.Drop, Lv, Pn);
               when Shielded => Audio.Play (Audio.Shield_Up, Lv, Pn);
               when Exploded | Spun =>
                  Audio.Play (Audio.Bang, Lv, Pn);
                  Kick (E.Car, 1.0);
               when Scared => Audio.Play (Audio.Moan, Lv, Pn);
               when Duel_Won =>
                  if E.Car in 1 .. State.Count then
                     Announce ("Player " & (if State.Racers (E.Car).Human = 1 then "one" else "two")
                               & " wins the duel!");
                  end if;
               when Bells => Audio.Play (Audio.Jingle, Float'Max (0.5, Lv), Pn);
               when others => null;
            end case;
         end;
      end loop;
      Events_Read := Event_Serial;
   end Hear_Events;

   procedure Update_Sound is
      use Race;
      F : constant Car_Index := (if State.Attract or else State.Mode = Race.Net then Focus else Player (1));
      C : Cars.Car renames State.Racers (F).Car;
      P : Audio.Params;
      Best : Float := Float'Last;
      In_Race : constant Boolean := Mode in Racing | Results;
   begin
      P.Speed := C.Speed;
      P.Voice := (if Tracks.Theme = Tracks.Halloween then 20 else Tracks.Vehicle_Kind'Pos (Tracks.Vehicle));
      P.Throttle := (if not In_Race or else Autopilot then 0.8
                     else Float'Max (Of_Keys (Arrows).Throttle,
                                     Float'Max (Pads.Get (1).Throttle,
                                                (if Players = 1 then Float'Max (Of_Keys (Letters).Throttle,
                                                                                Pads.Get (2).Throttle)
                                                 else 0.0))));
      P.Boost := C.Boost_T > 0.0;
      P.Air := C.Air;
      P.Rough := (if not C.Air and then C.Under in Tracks.Floor | Tracks.Sand then 1.0 else 0.0);
      P.Slip := C.Slip;
      for K in 1 .. State.Count loop
         if K /= F then
            declare
               D : constant Float := Distance (State.Racers (K).Car.P, C.P);
            begin
               if D < Best then
                  Best := D;
                  P.Other_Speed := State.Racers (K).Car.Speed;
                  P.Other_Level := 1.0 / (1.0 + D / 60.0);
                  P.Other_Pan := Pan_Of (State.Racers (K).Car.P);
               end if;
            end;
         end if;
      end loop;
      P.Music := (if Mode = Title then 1 else 2);
      P.Music_Level := (if Mode = Racing then 0.5 else 0.9) * Float (Music_Volume) / 10.0;
      P.Master := Float (Sound_Volume) / 10.0
        * (if Muted or else Mode = Editing_Track then 0.0
           elsif Mode in Paused | Options then 0.25
           elsif Mode = Title then 0.6 else 1.0);
      Audio.Set (P);
   end Update_Sound;

   ---------------------------------------------------------------------------
   --  The frame
   ---------------------------------------------------------------------------

   --  A time trial: every lap kept for a ghost, and the best one's ghost shown
   procedure Trial_Step is
      use Race;
      R : Racer renames State.Racers (Player (1));
      Going : constant Boolean := State.Phase = Running;
   begin
      if Going and then not Was_Running then
         Records.Begin_Lap;
         Ghost_Step := 0;
      end if;
      Was_Running := Going;
      if R.Lap > Seen_Lap then
         Seen_Lap := R.Lap;
         Records.End_Lap (Tracks.Current, R.Last_Lap);
         Records.Begin_Lap;
         Ghost_Step := 0;
      end if;
      if Going and then not R.Finished then
         if Ghost_Step mod 4 = 0 then
            Records.Record_Frame (R.Car.P, R.Car.H);
         end if;
         Ghost_Step := Ghost_Step + 1;
         declare
            P : Vec;
            H : Float;
            Ok : Boolean;
         begin
            Records.Ghost_At (State.Time - R.Lap_Start, P, H, Ok);
            View.Ghost_On := Ok;
            View.Ghost_P := P;
            View.Ghost_H := H;
         end;
      else
         View.Ghost_On := False;
      end if;
   end Trial_Step;

   procedure Step_World (Dt : Float) is
      Steps : Natural := 0;
      Net_Race : constant Boolean := In_Net_Race;
   begin
      if Net_Race and then Client then
         --  the host runs the race: here it is only smoothed between the states that come
         Net.Smooth (Dt);
         Race.Follow_Camera (Dt);
         return;
      end if;
      if Mode = Paused and then not Net_Race then
         return;
      end if;
      Accum := Accum + Dt;
      while Accum >= Race.Dt and then Steps < 30 loop
         declare
            I : Race.Input := (if Mode = Racing then Player_Input
                               elsif Mode = Replay and then Replay_Pos < Natural (Recording.Length)
                               then Recording (Replay_Pos)
                               else (others => <>));
         begin
            if Mode = Replay then
               Replay_Pos := Replay_Pos + 1;
            elsif not Race.State.Attract and then not Net_Race and then Can_Replay then
               Recording.Append (I);
            end if;
            if Net_Race then
               I.Keys (1) := I.P1;
               I.Fires (1) := I.Fire1;
               Net.Host_Inputs (I);
            end if;
            Race.Step (I, Autopilot => Race.State.Attract or else Autopilot);
            if Net_Race then
               Net_Steps := Net_Steps + 1;
               if Net_Steps mod 4 = 0 then
                  Net.Host_Send_State;
               end if;
            end if;
         end;
         if Play = Time_Trial and then not Race.State.Attract and then Mode /= Replay then
            Trial_Step;
         end if;
         Accum := Accum - Race.Dt;
         Steps := Steps + 1;
      end loop;
      if Steps = 30 then
         Accum := 0.0;
      end if;
   end Step_World;

   --  The network, every frame: what came, what to send, where to go
   procedure Net_Frame (Dt : Float) is
   begin
      Net.Poll (Dt);   --  nothing, when no game is hosted or joined
      if Hosting then
         declare
            L : Net.Lobby_Info renames Net.Lobby;
         begin
            if L.Players > Players_Seen then
               Say (Trim_Name (L.Names (L.Players)) & (if L.In_Race then " JOINS FOR THE NEXT RACE" else " JOINS"), 2.5);
               Audio.Play (Audio.Chime, 0.6);
               Alone_Asked := False;
            end if;
            Players_Seen := L.Players;
            if Mode = Host_Lobby then
               if Auto_Host > 0 and then L.Players >= Auto_Host then
                  Auto_Host := 0;
                  Net.Host_Start;
                  Start_Net_Race;
                  return;
               end if;
               if L.Players + L.AIs > Race.Max_Cars then
                  L.AIs := Race.Max_Cars - L.Players;
                  Net.Changed;
               end if;
               if Track /= L.Track and then Change_T <= 0.0 then
                  Lobby_Attract;
               end if;
            end if;
         end;
      elsif Client then
         if Net.Joining = Net.Gone then
            declare
               Why : constant String := To_String (Net.Refusal);
            begin
               Leave_Net;
               Say ((if Why = "" then "THE HOST HAS GONE" else Why), 3.0);
            end;
            return;
         end if;
         if Mode = Browse and then Net.Joining = Net.In_Lobby then
            Mode := Client_Lobby;
            Choice := 1;
            Editing := Not_Editing;
         end if;
         if Net.Race_Begun then
            Start_Net_Race;
         elsif Net.Back_In_Lobby then
            Mode := Client_Lobby;
            Choice := 1;
            Start_Attract;
         end if;
         if Mode = Client_Lobby then
            Lobby_Attract;
         end if;
         if In_Net_Race then
            declare
               I : constant Race.Input := (if Mode = Racing then Player_Input else (others => <>));
            begin
               Net.Send_Keys (I.P1, Mode = Racing and then I.Fire1);
            end;
         end if;
      end if;
      Choice := Positive'Min (Choice, Lines);
   end Net_Frame;

   function All_Done return Boolean is
     (if Play = Duel_Play then Race.State.Phase = Race.Over
      elsif In_Net_Race then Race.State.Racers (Race.Focus).Finished
      else (for all P in 1 .. Players => Race.State.Racers (Race.Player (P)).Finished));

   --  The tracks of the cup, as far as they go on a line
   function Cup_Track_Names return String is
      function Names (From : Positive) return String is
        (if From > Cup_Tracks (Cup)'Last then ""
         else " " & Tracks.Name (Cup_Tracks (Cup) (From))
              & (if From < Cup_Tracks (Cup)'Last then "," else "") & Names (From + 1));
      All_Of : constant String := Names (1);
   begin
      return (if All_Of'Length > 70 then All_Of (All_Of'First .. All_Of'First + 66) & "..." else All_Of);
   end Cup_Track_Names;

   function Typed (Kind : Edit_Kind; Shown : String) return String is
     (if Editing = Kind then To_String (Edit_Text) & "_" else Shown);

   procedure Draw_Net_Menu is
      function On_Off (B : Boolean) return String is (if B then "ON" else "OFF");
      procedure Player_Notes is
      begin
         Overlay.Add_Note (Img (Net.Lobby.Players) & " OF" & Natural'Image (Race.Max_Cars) & " PLAYERS, AND"
                           & Natural'Image (Net.Lobby.AIs) & " AI DRIVERS");
         declare
            Line : Unbounded_String;
         begin
            for K in 1 .. Net.Lobby.Players loop
               Append (Line, (if K > 1 then ",  " else "") & Trim_Name (Net.Lobby.Names (K))
                       & (if Client and then K = Net.Me then " (YOU)" else ""));
            end loop;
            Overlay.Add_Note (To_String (Line));
         end;
      end Player_Notes;
   begin
      Overlay.Clear_Menu;
      case Mode is
         when Net_Menu =>
            Overlay.Add_Item ("HOST A GAME");
            Overlay.Add_Item ("JOIN A GAME");
            Overlay.Add_Item ("YOUR NAME", Typed (Editing_Name, Trim_Name (Player_Name)));
            Overlay.Add_Item ("BACK");
            Overlay.Add_Note ("THE GAME IS PLAYED OVER UDP, PORT" & Natural'Image (Net.Port));
            Overlay.Draw_Menu ("NETWORK GAME", Choice);
         when Host_Lobby =>
            Overlay.Add_Item ("START THE RACE");
            Overlay.Add_Item ("TRACK", Tracks.Name (Net.Lobby.Track), True);
            Overlay.Add_Item ("LAPS", Img (Net.Lobby.Laps), True);
            Overlay.Add_Item ("AI DRIVERS", Img (Net.Lobby.AIs), True);
            Overlay.Add_Item ("DIFFICULTY", Race.Difficulty'Image (Net.Lobby.Level), True);
            Overlay.Add_Item ("PICK-UPS", On_Off (Net.Lobby.Items), True);
            Overlay.Add_Item ("CLOSE THE GAME");
            Player_Notes;
            Overlay.Add_Note ("JOIN AT " & Net.Local_Address & " ON THIS NETWORK");
            Overlay.Draw_Menu (Trim_Name (Player_Name) & "'S GAME", Choice, "YOU ARE HOSTING");
         when Browse =>
            for K in 1 .. Net.N_Found loop
               Overlay.Add_Item (Trim_Name (Net.Found (K).Host_Name) & "'S GAME",
                                 (if Net.Found (K).In_Race then "RACING" else Tracks.Name (Net.Found (K).Track))
                                 & "  " & Img (Net.Found (K).Players) & "/" & Img (Race.Max_Cars));
            end loop;
            Overlay.Add_Item ("JOIN BY ADDRESS",
                              Typed (Editing_Address, (if Length (Join_Address) = 0 then "TYPE IT"
                                                       else To_String (Join_Address))));
            Overlay.Add_Item ("BACK");
            if Net.Joining = Net.Asking then
               Overlay.Add_Note ("ASKING TO JOIN...");
            elsif Net.N_Found = 0 then
               Overlay.Add_Note ("LOOKING FOR GAMES ON THIS NETWORK...");
            end if;
            if Net.Joining in Net.Refused | Net.Gone and then Length (Net.Refusal) > 0 then
               Overlay.Add_Note (To_String (Net.Refusal));
            end if;
            Overlay.Draw_Menu ("JOIN A GAME", Choice);
         when Client_Lobby =>
            Overlay.Add_Item ("LEAVE THE GAME");
            Overlay.Add_Note (Tracks.Name (Net.Lobby.Track) & ",  " & Img (Net.Lobby.Laps) & " LAPS,  "
                              & Race.Difficulty'Image (Net.Lobby.Level) & ",  PICK-UPS " & On_Off (Net.Lobby.Items));
            Player_Notes;
            Overlay.Add_Note ((if Net.Waiting_For_Next then "A RACE IS ON: YOU RACE IN THE NEXT ONE"
                               else "WAITING FOR " & Trim_Name (Net.Lobby.Names (1)) & " TO START THE RACE..."));
            Overlay.Draw_Menu (Trim_Name (Net.Lobby.Names (1)) & "'S GAME", Choice);
         when others =>
            null;
      end case;
      if Message_T > 0.0 then
         Overlay.Banner (Message (1 .. Message_Len), 0.12, 40.0);
      end if;
   end Draw_Net_Menu;

   Edit_Clock : Float := 0.0;

   function Paint_Name (N : Natural) return String is
     (case N is
         when 0 => "RED", when 1 => "BLUE", when 2 => "YELLOW", when 3 => "GREEN",
         when 4 => "PURPLE", when 5 => "ORANGE", when 6 => "WHITE", when others => "TEAL");

   function Volume_Bar (V : Natural) return String is
      B : String (1 .. 10) := (others => '-');
   begin
      for K in 1 .. V loop
         B (K) := '|';
      end loop;
      return B & "  " & Img (V);
   end Volume_Bar;

   procedure Draw_Frame (W, H : Natural; Alpha, Dt : Float) is
      Wf : constant Float := Float (W);
      Hf : constant Float := Float (H);
   begin
      View.Begin_Frame (Alpha, Dt);
      Overlay.Begin_Frame (W, H);
      if Mode = Options then
         if Return_To = Title then
            View.Render_View (0, 0, W, H, 1, Race.Focus, View.Chase, Orbit => True, Dt => Dt);
         else
            View.Render_View (0, 0, W, H, 1, Race.Focus, Cameras (1), False, 0.0);
         end if;
         Overlay.Clear_Menu;
         Overlay.Add_Item ("CAR, PLAYER 1", Models.Style_Name (Car_Choice (1)), True);
         Overlay.Add_Item ("COLOUR, PLAYER 1", Paint_Name (Paint_Choice (1)), True);
         Overlay.Add_Item ("CAR, PLAYER 2", Models.Style_Name (Car_Choice (2)), True);
         Overlay.Add_Item ("COLOUR, PLAYER 2", Paint_Name (Paint_Choice (2)), True);
         Overlay.Add_Item ("SOUND", Volume_Bar (Sound_Volume), True);
         Overlay.Add_Item ("MUSIC", Volume_Bar (Music_Volume), True);
         Overlay.Add_Item ("ANNOUNCER", (if not Speech.Available then "NOT FOUND (ESPEAK-NG)"
                                         else (case Voice is
                                                  when Voice_Off => "OFF",
                                                  when Voice_Woman => "FEMALE",
                                                  when Voice_Man => "MALE")), True);
         Overlay.Add_Item ("SHADOWS", (if View.Shadows_On then "ON" else "OFF"), True);
         Overlay.Add_Item ("CONTROLLER, PLAYER 1", Pad_Name (1), True);
         Overlay.Add_Item ("CONTROLLER, PLAYER 2", Pad_Name (2), True);
         Overlay.Add_Item ("BACK");
         Overlay.Add_Note (Img (Pads.Device_Count) & " CONTROLLERS PLUGGED IN");
         Overlay.Draw_Menu ("OPTIONS", Choice);
      elsif Mode = Editing_Track then
         GL.Viewport (0, 0, GL.GLsizei (W), GL.GLsizei (H));
         GL.Clear_Color (0.1, 0.1, 0.12, 1.0);
         GL.Clear (16#4100#);   --  colour and depth
         Edit_Clock := Edit_Clock + Dt;
         Editor.Draw (Overlay.Context, W, H, Edit_Clock);
      elsif Mode in Net_Menu | Host_Lobby | Browse | Client_Lobby then
         View.Render_View (0, 0, W, H, 1, Race.Focus, View.Chase, Orbit => True, Dt => Dt);
         Draw_Net_Menu;
      elsif Mode = Title then
         View.Render_View (0, 0, W, H, 1, Race.Focus, View.Chase, Orbit => True, Dt => Dt);
         Overlay.Clear_Menu;
         Overlay.Add_Item ((case Play is
                               when Single_Race => "START RACE",
                               when Championship => "START THE CUP",
                               when Time_Trial => "START THE CLOCK",
                               when Duel_Play => "START THE DUEL",
                               when Net_Play => "HOST OR JOIN A GAME"));
         Overlay.Add_Item ("MODE", Play_Name (Play), True);
         Overlay.Add_Item ("PLAYERS", Img (Players), Play in Single_Race | Championship);
         if Play = Championship then
            Overlay.Add_Item ("CUP", Cup_Name (Cup), True);
         else
            Overlay.Add_Item ("TRACK", Tracks.Name (Track), True);
         end if;
         Overlay.Add_Item ("LAPS", Img (Laps), True);
         Overlay.Add_Item ("OPPONENTS", (if Play in Time_Trial | Duel_Play then "-"
                                         else Img (Natural'Min (Opponents, Max_Opponents))),
                           Play in Single_Race | Championship);
         Overlay.Add_Item ("DIFFICULTY", Race.Difficulty'Image (Level), True);
         Overlay.Add_Item ("PICK-UPS", (if Items_On then "ON" else "OFF"), True);
         Overlay.Add_Item ("TIME", Air.Time_Name (Air.Time), True);
         Overlay.Add_Item ("WEATHER", Air.Weather_Name (Air.Weather), True);
         Overlay.Add_Item ("CAMERA, PLAYER 1", View.Camera_Kind'Image (Cameras (1)), True);
         Overlay.Add_Item ("CAMERA, PLAYER 2", View.Camera_Kind'Image (Cameras (2)), True);
         Overlay.Add_Item ("OPTIONS");
         Overlay.Add_Item ("TRACK EDITOR");
         Overlay.Add_Item ("QUIT");
         for P in Pads.Player_Number loop
            if Pads.Has (P) then
               Overlay.Add_Note ("PLAYER " & Img (P) & ": " & Pads.Name (P));
            end if;
         end loop;
         if Pads.Count > 0 and then not (Pads.Has (1) and then Pads.Has (2)) then
            Overlay.Add_Note ("PRESS A BUTTON ON A CONTROLLER TO TAKE IT");
         end if;
         Overlay.Add_Note ((if Players = 2 then "PLAYER 1: ARROWS, RIGHT CTRL    PLAYER 2: W A S D, LEFT CTRL"
                            else "ARROWS OR W A S D TO DRIVE, CTRL OR SPACE TO FIRE, C FOR THE CAMERA"));
         Overlay.Draw_Menu
           ("ADAMACHINES 3D", Choice,
            (if Play = Championship
             then Img (Cup_Tracks (Cup)'Length) & " RACES:" & Cup_Track_Names
             elsif Records.Best_Lap (Track) > 0.0
             then "LAP RECORD ON " & Tracks.Name (Track) & ": " & Overlay.Time_Img (Records.Best_Lap (Track))
             else Tracks.Name (Track) & " - " & Img (Laps) & (if Laps = 1 then " LAP" else " LAPS")));
      elsif Mode = Replay then
         View.Render_View (0, 0, W, H, 1, Replay_Car, Replay_Cam, False, Dt);
         Overlay.Race_Hud (0.0, 0.0, Wf, Hf, Replay_Car, "C  " & View.Camera_Kind'Image (Replay_Cam), False, 0.0);
         if Integer (Race.State.Time * 2.0) mod 2 = 0 then
            Overlay.Banner ("REPLAY", 0.13, 56.0);
         end if;
         Overlay.Banner ((if Race.State.Racers (Replay_Car).Human > 0
                          then "PLAYER " & Img (Race.State.Racers (Replay_Car).Human)
                          else Trim_Name (Race.State.Racers (Replay_Car).Name))
                         & "     LEFT RIGHT: ANOTHER CAR     C: CAMERA     ENTER: BACK", 0.95, 22.0);
      elsif Play = Duel_Play then
         --  one view for both, high over the race's own camera
         View.Render_View (0, 0, W, H, 1, Race.Focus, View.High, False, Dt, Shared => True);
         Overlay.Duel_Hud;
         Overlay.Countdown (0.0, 0.0, Wf, Hf);
         if Mode = Paused then
            Overlay.Clear_Menu;
            Overlay.Add_Item ("CONTINUE");
            Overlay.Add_Item ("DUEL AGAIN");
            Overlay.Add_Item ("OPTIONS");
            Overlay.Add_Item ("QUIT TO THE TITLE");
            Overlay.Draw_Menu ("PAUSED", Choice, Tracks.Name (Track));
         elsif Mode = Results then
            Overlay.Banner ("ENTER: THE TITLE     R: DUEL AGAIN     W: WATCH THE REPLAY", 0.94, 22.0);
         end if;
      elsif In_Net_Race then
         View.Render_View (0, 0, W, H, 1, Race.Focus, Cameras (1), False, Dt);
         Overlay.Race_Hud (0.0, 0.0, Wf, Hf, Race.Focus, "C  " & View.Camera_Kind'Image (Cameras (1)), Show_Fps, View.Fps);
         Overlay.Countdown (0.0, 0.0, Wf, Hf);
         if Mode = Paused then
            Overlay.Clear_Menu;
            Overlay.Add_Item ("CONTINUE");
            Overlay.Add_Item ((if Hosting then "CLOSE THE GAME" else "LEAVE THE GAME"));
            Overlay.Add_Note ("THE RACE GOES ON WHILE YOU ARE HERE");
            Overlay.Draw_Menu ("PAUSED", Choice, Tracks.Name (Track));
         elsif Mode = Results then
            Overlay.Results (Tracks.Name (Track));
            Overlay.Banner ((if Hosting then "ENTER: BACK TO THE LOBBY, WITH EVERYONE"
                             else "WAITING FOR THE HOST...     ESC: LEAVE THE GAME"), 0.94, 22.0);
         elsif Message_T > 0.0 then
            Overlay.Banner (Message (1 .. Message_Len), 0.30, 64.0);
         end if;
      else
         if Players = 2 then
            --  one above the other: player 1 at the top
            View.Render_View (0, H - H / 2, W, H / 2, 1, Race.Player (1), Cameras (1), False, Dt);
            View.Render_View (0, 0, W, H - H / 2, 2, Race.Player (2), Cameras (2), False, Dt);
            Overlay.Race_Hud (0.0, 0.0, Wf, Float (H / 2), Race.Player (1),
                              "C  " & View.Camera_Kind'Image (Cameras (1)), Show_Fps, View.Fps);
            Overlay.Race_Hud (0.0, Float (H / 2), Wf, Hf - Float (H / 2), Race.Player (2),
                              "V  " & View.Camera_Kind'Image (Cameras (2)), False, 0.0);
            Overlay.Countdown (0.0, 0.0, Wf, Hf);
         else
            View.Render_View (0, 0, W, H, 1, Race.Player (1), Cameras (1), False, Dt);
            Overlay.Race_Hud (0.0, 0.0, Wf, Hf, Race.Player (1), "C  " & View.Camera_Kind'Image (Cameras (1)),
                              Show_Fps, View.Fps);
            Overlay.Countdown (0.0, 0.0, Wf, Hf);
         end if;
         if Mode = Paused then
            Overlay.Clear_Menu;
            Overlay.Add_Item ("CONTINUE");
            Overlay.Add_Item ("RACE AGAIN");
            Overlay.Add_Item ("OPTIONS");
            Overlay.Add_Item ("QUIT TO THE TITLE");
            Overlay.Draw_Menu ("PAUSED", Choice, Tracks.Name (Track));
         elsif Mode = Results then
            if Play = Championship then
               Overlay.Results (Cup_Name (Cup) & " - RACE " & Img (Round) & " OF " & Img (Cup_Tracks (Cup)'Length));
               Overlay.Banner ("ENTER: THE STANDINGS     W: WATCH THE REPLAY", 0.94, 22.0);
            else
               Overlay.Results (Tracks.Name (Race_Track));
               Overlay.Banner ("ENTER: THE TITLE     R: RACE AGAIN     N: THE NEXT TRACK     W: WATCH THE REPLAY",
                               0.94, 22.0);
            end if;
         elsif Mode = Standings then
            declare
               Last : constant Boolean := Round = Cup_Tracks (Cup)'Last;
            begin
               Overlay.Standings (Cup_Name (Cup), (if Last then "THE FINAL STANDINGS"
                                                   else "AFTER RACE " & Img (Round) & " OF " & Img (Cup_Tracks (Cup)'Length)),
                                  Points, Last);
               Overlay.Banner ((if Last then "ENTER: THE TITLE"
                                else "ENTER: ON TO " & Tracks.Name (Cup_Tracks (Cup) (Round + 1))), 0.94, 22.0);
            end;
         elsif Message_T > 0.0 then
            Overlay.Banner (Message (1 .. Message_Len), 0.30, 64.0);
         end if;
      end if;
      View.Draw_Overlay (W, H);
   end Draw_Frame;

   procedure Save_Shot (W, H : Natural) is
      use Ada.Streams.Stream_IO;
      type Bytes is array (Natural range <>) of Interfaces.C.unsigned_char;
      Pixels : Bytes (0 .. W * H * 3 - 1);
      F : File_Type;
      Header : constant String := "P6" & ASCII.LF & Natural'Image (W) & Natural'Image (H) & ASCII.LF
        & "255" & ASCII.LF;
   begin
      GL.Pixel_Storei (GL.GL_PACK_ALIGNMENT, 1);
      GL.Read_Pixels (0, 0, GL.GLsizei (W), GL.GLsizei (H), 16#1907#, GL.GL_UNSIGNED_BYTE, Pixels'Address);
      Create (F, Out_File, Shot_File.all);
      String'Write (Stream (F), Header);
      for Row in reverse 0 .. H - 1 loop   --  GL keeps the bottom row first
         Bytes'Write (Stream (F), Pixels (Row * W * 3 .. Row * W * 3 + W * 3 - 1));
      end loop;
      Close (F);
   end Save_Shot;

   function On_Render (Self : access Gtk_Widget_Record'Class) return Boolean is
      Now : constant Time := Clock;
      Dt  : constant Float := Float'Min (0.1, Float (To_Duration (Now - Last_T)));
      Scale : constant Gint := Self.Get_Scale_Factor;
      W : constant Natural := Natural (Self.Get_Allocated_Width * Scale);
      H : constant Natural := Natural (Self.Get_Allocated_Height * Scale);
      P : Natural;
      A : Pads.Action;
   begin
      Last_T := Now;
      if not Ready then
         return True;
      end if;
      Run_T := Run_T + Dt;
      if Shot_File /= null and then Shot_After > 0.0 then
         if Run_T >= Shot_After then
            Draw_Frame (W, H, 1.0, Dt);
            Save_Shot (W, H);
            Gtk.Main.Main_Quit;
            return True;
         end if;
      elsif Shot_File /= null then
         --  a screenshot: the race run at its own pace, then the picture taken
         if Mode /= Title then
            while Race.State.Phase = Race.Countdown
              or else (Race.State.Phase = Race.Running and then Race.State.Time < Shot_At)
            loop
               Recording.Append ((others => <>));
               Race.Step ((others => <>), Autopilot => Autopilot);
               if Play = Time_Trial then
                  Trial_Step;
               end if;
               Hear_Events;
               View.Begin_Frame (1.0, Race.Dt);
            end loop;
            if Env ("ADAMACHINES_REPLAY_CHECK") /= "" then
               --  the race once more from what was recorded: every car must end where it did
               declare
                  type Places is array (Race.Car_Index) of Vec;
                  Before : Places;
                  Steps : constant Natural := Natural (Recording.Length);
                  Worst : Float := 0.0;
               begin
                  for I in 1 .. Race.State.Count loop
                     Before (I) := Race.State.Racers (I).Car.P;
                  end loop;
                  Start_Replay;
                  for K in 0 .. Steps - 1 loop
                     Race.Step (Recording (K), Autopilot => Autopilot);
                  end loop;
                  for I in 1 .. Race.State.Count loop
                     Worst := Float'Max (Worst, Distance (Before (I), Race.State.Racers (I).Car.P));
                  end loop;
                  Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "replay check:" & Natural'Image (Steps)
                                        & " steps, cars off by at most" & Float'Image (Worst));
                  Mode := Replay;
                  Replay_Pos := Steps;
               end;
            end if;
            if Env ("ADAMACHINES_SHOW") /= "" then
               Mode := Mode_Kind'Value (Env ("ADAMACHINES_SHOW"));
               if Mode = Standings then
                  Score_Round;
               end if;
            end if;
         end if;
         for K in 1 .. 90 loop   --  let the camera settle
            if Mode = Replay and then Replay_Pos < Natural (Recording.Length) then
               Race.Step (Recording (Replay_Pos), Autopilot => Autopilot);
               Replay_Pos := Replay_Pos + 1;
            else
               Race.Step ((others => <>), Autopilot => True);
            end if;
            if Play = Time_Trial and then Mode = Racing then
               Trial_Step;
            end if;
            Hear_Events;
            Draw_Frame (W, H, 1.0, 1.0 / 120.0);
         end loop;
         if Env ("ADAMACHINES_FRAMES") /= "" then
            --  a run of pictures, thirty a second of the race, for a moving picture
            declare
               Base : constant String := Shot_File.all;
            begin
               for F in 1 .. Natural'Value (Env ("ADAMACHINES_FRAMES")) loop
                  for K in 1 .. 4 loop
                     Race.Step ((others => <>), Autopilot => True);
                     Hear_Events;
                  end loop;
                  Draw_Frame (W, H, 1.0, 4.0 * Race.Dt);
                  Shot_File := new String'(Base & "-" & (1 .. 4 - Img (F)'Length => '0') & Img (F) & ".ppm");
                  Save_Shot (W, H);
               end loop;
            end;
         else
            Save_Shot (W, H);
         end if;
         Gtk.Main.Main_Quit;
         return True;
      end if;

      Net_Frame (Dt);
      Pads.Poll;
      while Pads.Next (P, A) loop
         Pad_Action (P, A);
      end loop;
      if Mode = Title and then Change_T > 0.0 then
         Change_T := Change_T - Dt;
         if Change_T <= 0.0 then
            Start_Attract;
         end if;
      end if;
      if Play = Duel_Play then
         --  what the shared camera sees of the floor: off it, a player loses a light
         declare
            D : constant Float := Sqrt (View.Shared_Height ** 2 + View.Shared_Back ** 2);
         begin
            Race.State.View_H := 2.0 * D * Tan (Geom.Pi / 6.0) * 0.98;
            Race.State.View_W := Race.State.View_H * Float (W) / Float (Natural'Max (1, H));
         end;
      end if;
      Step_World (Dt);
      Hear_Events;
      Update_Sound;
      if Mode /= Paused or else In_Net_Race then
         Message_T := Message_T - Dt;
      end if;
      Update_Feel (Dt);
      if Mode = Replay and then Replay_Pos >= Natural (Recording.Length) then
         Replay_End_T := Replay_End_T + Dt;
         if Replay_End_T > 3.0 then
            End_Replay;
         end if;
      end if;
      if Mode = Racing and then All_Done then
         Done_T := Done_T + Dt;
         if Done_T > 2.5 then
            Mode := Results;
         end if;
      end if;
      Draw_Frame (W, H, (if (Mode = Paused and then not In_Net_Race) or else (In_Net_Race and then Client) then 1.0
                         else Clamp (Accum / Race.Dt, 0.0, 1.0)),
                  (if Mode = Paused then 0.0 else Dt));
      return True;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Information (E));
         Gtk.Main.Main_Quit;
         return True;
   end On_Render;

   procedure On_Realize (Self : access Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
      use type System.Address;
   begin
      GL_Area_Make_Current (Area_C);
      if GL_Area_Get_Error (Area_C) /= System.Null_Address then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "Adamachines 3D: no OpenGL 3.3 to be had");
         Gtk.Main.Main_Quit;
         return;
      end if;
      View.Init;
      View.New_Track;
      Ready := True;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Information (E));
         Gtk.Main.Main_Quit;
   end On_Realize;

   function Tick (Widget : not null access Gtk_Widget_Record'Class;
                  Frame_Clock : not null access Gdk.Frame_Clock.Gdk_Frame_Clock_Record'Class)
                  return Boolean
   is
      pragma Unreferenced (Frame_Clock);
   begin
      Widget.Queue_Draw;
      return True;
   end Tick;

   procedure On_Destroy (Self : access Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Gtk.Main.Main_Quit;
   end On_Destroy;

   procedure Run is
      Id : Guint;
      Stub : Gtk_Widget_Record;
   begin
      Gtk.Main.Init;
      Load_Choices;
      Records.Load;
      Editor.Load;
      if Tracks.Is_Custom (Track) and then not Tracks.Slots (Tracks.Slot_Of (Track)).Saved then
         Track := 1;
      end if;
      if Env ("ADAMACHINES_TRACK") /= "" then
         Track := Tracks.Track_Id'Value (Env ("ADAMACHINES_TRACK"));
      end if;
      if Env ("ADAMACHINES_PLAYERS") /= "" then
         Players_Choice := Positive'Value (Env ("ADAMACHINES_PLAYERS"));
      end if;
      if Env ("ADAMACHINES_TIME") /= "" then
         Air.Time := Air.Time_Kind'Value (Env ("ADAMACHINES_TIME"));
      end if;
      if Env ("ADAMACHINES_WEATHER") /= "" then
         Air.Weather := Air.Weather_Kind'Value (Env ("ADAMACHINES_WEATHER"));
      end if;
      if Env ("ADAMACHINES_PLAY") /= "" then
         Play := Play_Kind'Value (Env ("ADAMACHINES_PLAY"));
      end if;
      Autopilot := Env ("ADAMACHINES_AUTOPILOT") /= "";
      if Env ("ADAMACHINES_CAMERA") /= "" then
         Cameras := (others => View.Camera_Kind'Value (Env ("ADAMACHINES_CAMERA")));
      end if;
      if Env ("ADAMACHINES_SHOT") /= "" then
         Shot_File := new String'(Env ("ADAMACHINES_SHOT"));
         Autopilot := Autopilot or else Env ("ADAMACHINES_SHOT_AFTER") = "";   --  the race run by itself
         if Env ("ADAMACHINES_SHOT_AT") /= "" then
            Shot_At := Float'Value (Env ("ADAMACHINES_SHOT_AT"));
         end if;
      end if;

      Shot_Off := Shot_File = null;
      if Env ("ADAMACHINES_SHOT_AFTER") /= "" then
         Shot_After := Float'Value (Env ("ADAMACHINES_SHOT_AFTER"));
      end if;
      if Env ("ADAMACHINES_NAME") /= "" then
         Player_Name := As_Name (Env ("ADAMACHINES_NAME"));
      end if;
      if Env ("ADAMACHINES_OPTIONS") /= "" then
         To_Title;
         Return_To := Title;
         Mode := Options;
      elsif Env ("ADAMACHINES_EDITOR") /= "" then
         To_Title;
         Mode := Editing_Track;
         if Env ("ADAMACHINES_EDITOR") = "drive" then
            --  for the checks: Enter pressed in the editor, the track driven
            declare
               Result : Editor.Action;
            begin
               Editor.Key (Gdk.Types.Keysyms.GDK_Return, False, Result);
               if Result = Editor.Test_Drive then
                  Track := Tracks.First_Custom + Editor.Current - 1;
                  Play := Single_Race;
                  From_Editor := True;
                  Start_Game;
               end if;
            end;
         end if;
      elsif Env ("ADAMACHINES_NET_HOST") /= "" then
         Play := Net_Play;
         Auto_Host := Natural'Value (Env ("ADAMACHINES_NET_HOST"));
         To_Title;
         Begin_Hosting;
      elsif Env ("ADAMACHINES_NET_JOIN") /= "" then
         Play := Net_Play;
         To_Title;
         Net.Browse;
         Mode := Browse;
         Net.Join (Env ("ADAMACHINES_NET_JOIN"), Player_Name);
      elsif Env ("ADAMACHINES_AUTOSTART") /= ""
        or else (Shot_File /= null and then Shot_After = 0.0 and then Env ("ADAMACHINES_MENU") = "")
      then
         Start_Race;
      else
         To_Title;
      end if;

      Gtk.Window.Gtk_New (Window);
      Window.Set_Title ("Adamachines 3D");
      Window.Set_Default_Size (1600, 900);
      Window.On_Destroy (On_Destroy'Access);
      Window.On_Key_Press_Event (Key_Press'Access, False);
      Window.On_Key_Release_Event (Key_Release'Access, False);

      Area_C := GL_Area_New;
      Area := Gtk_Widget (Glib.Object.Get_User_Data (Area_C, Stub));
      GL_Area_Set_Required_Version (Area_C, 3, 3);
      GL_Area_Set_Has_Depth_Buffer (Area_C, 1);
      Area.On_Realize (On_Realize'Access);
      Render_Cb.Connect (Area, "render", On_Render'Access);
      Window.Add (Area);
      Window.Show_All;
      if Env ("ADAMACHINES_FULLSCREEN") /= "" then
         Window.Fullscreen;
         Is_Fullscreen := True;
      end if;

      if Shot_File = null then
         Audio.Start;
      end if;
      Id := Area.Add_Tick_Callback (Tick'Access);
      pragma Unreferenced (Id);
      Gtk.Main.Main;
      if Net.Role /= Net.Off then
         Net.Stop;
      end if;
      if Shot_File = null then
         Save_Choices;
         Pads.Shut_Down;
         Audio.Stop;
      end if;
   end Run;

end App;
