--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

with Ada.Calendar; use Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces; use Interfaces;
with Interfaces.C; use Interfaces.C;
with System;
with GNAT.OS_Lib;

package body Pads is

   function C_Open (Path : char_array; Flags : int) return int
     with Import, Convention => C, External_Name => "open";
   function C_Read (Fd : int; Buf : System.Address; Count : size_t) return long
     with Import, Convention => C, External_Name => "read";
   function C_Close (Fd : int) return int
     with Import, Convention => C, External_Name => "close";
   function C_Ioctl (Fd : int; Request : unsigned_long; Arg : System.Address) return int
     with Import, Convention => C, External_Name => "ioctl";
   function C_Write (Fd : int; Buf : System.Address; Count : size_t) return long
     with Import, Convention => C, External_Name => "write";

   O_RDWR : constant := 2;
   EVIOCSFF : constant := 16#4030_4580#;   --  upload a force effect (48 bytes)
   EV_FF : constant := 16#15#;
   FF_RUMBLE : constant := 16#50#;
   FF_CONSTANT : constant := 16#52#;
   FF_GAIN : constant := 16#60#;
   FF_AUTOCENTER : constant := 16#61#;

   O_NONBLOCK : constant := 8#4000#;
   EAGAIN : constant := 11;

   JSIOCGAXES    : constant := 16#8001_6A11#;
   JSIOCGBUTTONS : constant := 16#8001_6A12#;
   JSIOCGNAME    : constant := 16#8080_6A13#;   --  128 bytes
   JSIOCGAXMAP   : constant := 16#8040_6A32#;
   JSIOCGBTNMAP_Large : constant := 16#8400_6A34#;   --  512 codes
   JSIOCGBTNMAP_Small : constant := 16#8200_6A34#;   --  older kernels: 256 codes

   JS_EVENT_BUTTON : constant := 16#01#;
   JS_EVENT_AXIS   : constant := 16#02#;
   JS_EVENT_INIT   : constant := 16#80#;

   ABS_X : constant := 0;   ABS_Y : constant := 1;   ABS_Z : constant := 2;
   ABS_RZ : constant := 5;  ABS_GAS : constant := 9; ABS_BRAKE : constant := 10;
   ABS_HAT0X : constant := 16;  ABS_HAT0Y : constant := 17;

   BTN_A : constant := 16#130#;  BTN_B : constant := 16#131#;
   BTN_X : constant := 16#133#;  BTN_Y : constant := 16#134#;
   BTN_TL : constant := 16#136#; BTN_TR : constant := 16#137#;
   BTN_SELECT : constant := 16#13A#; BTN_START : constant := 16#13B#; BTN_MODE : constant := 16#13C#;

   type Kind is (Pad, Wheel, Stick);

   Max_Axes : constant := 64;
   Max_Buttons : constant := 512;

   type Axis_Codes is array (0 .. Max_Axes - 1) of Unsigned_8 with Convention => C;
   type Button_Codes is array (0 .. Max_Buttons - 1) of Unsigned_16 with Convention => C;
   type Axis_Values is array (0 .. Max_Axes - 1) of Integer;
   type Button_States is array (0 .. Max_Buttons - 1) of Boolean;

   type Device is record
      Open     : Boolean := False;
      Fd       : int := -1;
      Name     : String (1 .. 64) := (others => ' ');
      Name_Len : Natural := 0;
      Class    : Kind := Pad;
      Axes, Buttons : Natural := 0;
      Axis_Map : Axis_Codes := (others => 0);
      Btn_Map  : Button_Codes := (others => 0);
      Value    : Axis_Values := (others => 0);
      Rest     : Axis_Values := (others => 0);
      Down     : Button_States := (others => False);
      Owner    : Natural := 0;
      Stick_X, Stick_Y : Integer := 0;   --  where the stick was, for the menus: -1, 0, 1
      --  Its force feedback, through its event device
      Ev_Fd    : int := -1;
      Effect   : Integer := -1;          --  the rumble or force uploaded, by the kernel's number
      Playing  : Boolean := False;
      Sent_A, Sent_B : Float := 0.0;     --  what it was last told: rumble strong and weak, or push
      Sent_At  : Time := Clock;
      Center   : Float := -1.0;          --  a wheel's centring, as last set
   end record;

   Max_Devices : constant := 16;
   Devices : array (0 .. Max_Devices - 1) of Device;

   Start_Time : constant Time := Clock;

   Debug : constant Boolean := Ada.Environment_Variables.Exists ("ADAMACHINES_PAD_DEBUG");
   Last_Scan : Time := Clock - 10.0;

   --  The things pressed, waiting to be taken
   type Pressed is record
      P : Natural := 0;
      A : Action := Fire;
   end record;
   Queue : array (0 .. 63) of Pressed;
   Head, Tail : Natural := 0;

   procedure Push (P : Natural; A : Action) is
   begin
      if (Tail + 1) mod Queue'Length /= Head then
         Queue (Tail) := (P, A);
         Tail := (Tail + 1) mod Queue'Length;
      end if;
   end Push;

   function Next (P : out Natural; A : out Action) return Boolean is
   begin
      if Head = Tail then
         P := 0;
         A := Fire;
         return False;
      end if;
      P := Queue (Head).P;
      A := Queue (Head).A;
      Head := (Head + 1) mod Queue'Length;
      return True;
   end Next;

   ---------------------------------------------------------------------------

   function Contains (S, Part : String) return Boolean is
     (Ada.Strings.Fixed.Index (Ada.Characters.Handling.To_Upper (S), Part) > 0);

   ---------------------------------------------------------------------------
   --  Force feedback
   ---------------------------------------------------------------------------

   type Raw is array (Natural range <>) of Unsigned_8 with Convention => C;

   procedure Put16 (R : in out Raw; At_Byte : Natural; V : Integer) is
      U : constant Unsigned_16 := Unsigned_16 (V mod 65536);
   begin
      R (At_Byte) := Unsigned_8 (U and 16#FF#);
      R (At_Byte + 1) := Unsigned_8 (Shift_Right (U, 8));
   end Put16;

   --  Sends an event to the device: an effect played or stopped, the gain, the centring
   procedure Send (D : Device; Code, Value : Integer) is
      E : Raw (0 .. 23) := (others => 0);
      R : long;
      pragma Unreferenced (R);
   begin
      if D.Ev_Fd < 0 then
         return;
      end if;
      Put16 (E, 16, EV_FF);
      Put16 (E, 18, Code);
      E (20) := Unsigned_8 (Value mod 256);
      E (21) := Unsigned_8 ((Value / 256) mod 256);
      E (22) := Unsigned_8 ((Value / 65536) mod 256);
      E (23) := (if Value < 0 then 16#FF# else 0);
      R := C_Write (D.Ev_Fd, E'Address, 24);
   end Send;

   --  Puts an effect on the device (or changes the one there) and plays it
   procedure Play_Effect (D : in out Device; Kind_Of : Integer; A, B : Integer; Length_Ms : Natural) is
      E : Raw (0 .. 47) := (others => 0);
   begin
      Put16 (E, 0, Kind_Of);
      Put16 (E, 2, D.Effect);
      Put16 (E, 4, 16#4000#);       --  the direction: across, for a wheel's push
      Put16 (E, 10, Length_Ms);
      Put16 (E, 16, A);             --  rumble: strong; constant: level
      Put16 (E, 18, B);             --  rumble: weak
      if C_Ioctl (D.Ev_Fd, EVIOCSFF, E'Address) < 0 then
         return;
      end if;
      D.Effect := Integer (Integer_16'(Integer_16 (E (2)) + Integer_16 (E (3)) * 256));
      Send (D, D.Effect, 1);
      D.Playing := True;
   end Play_Effect;

   procedure Stop_Effect (D : in out Device) is
   begin
      if D.Playing and then D.Effect >= 0 then
         Send (D, D.Effect, 0);
      end if;
      D.Playing := False;
      D.Sent_A := 0.0;
      D.Sent_B := 0.0;
   end Stop_Effect;

   procedure Set_Center (D : in out Device; Share : Float) is
   begin
      if D.Class = Wheel and then abs (Share - D.Center) > 0.03 then
         Send (D, FF_AUTOCENTER, Integer (65535.0 * Float'Max (0.0, Float'Min (1.0, Share))));
         D.Center := Share;
      end if;
   end Set_Center;

   --  The event device beside the joystick device, for the forces
   procedure Open_Feedback (D : in out Device; N : Natural) is
      use Ada.Directories;
      Dir : constant String := "/sys/class/input/js" & Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left)
        & "/device";
      Search : Search_Type;
      Found  : Directory_Entry_Type;
   begin
      Start_Search (Search, Dir, "event*");
      if More_Entries (Search) then
         Get_Next_Entry (Search, Found);
         D.Ev_Fd := C_Open (To_C ("/dev/input/" & Simple_Name (Found)), O_RDWR + O_NONBLOCK);
         if D.Ev_Fd >= 0 then
            Send (D, FF_GAIN, 16#FFFF#);
         end if;
      end if;
      End_Search (Search);
   exception
      when others => D.Ev_Fd := -1;
   end Open_Feedback;

   procedure Feel_Device (D : in out Device; Kick, Rough, Speed_Share : Float) is
      Since : constant Duration := Clock - D.Sent_At;
   begin
      if D.Ev_Fd < 0 then
         return;
      end if;
      case D.Class is
         when Pad | Stick =>
            declare
               Strong : constant Float := Float'Min (1.0, Kick);
               Weak : constant Float := Float'Min (1.0, Float'Max (Kick * 0.6, Rough * 0.22));
            begin
               if Strong < 0.03 and then Weak < 0.03 then
                  Stop_Effect (D);
               elsif abs (Strong - D.Sent_A) > 0.05 or else abs (Weak - D.Sent_B) > 0.05 or else Since > 0.2 then
                  Play_Effect (D, FF_RUMBLE, Integer (65535.0 * Strong), Integer (65535.0 * Weak), 300);
                  D.Sent_A := Strong;
                  D.Sent_B := Weak;
                  D.Sent_At := Clock;
               end if;
            end;
         when Wheel =>
            --  heavier in the hands the faster the car goes
            Set_Center (D, 0.12 + 0.45 * Float'Min (1.0, Speed_Share));
            declare
               Shake : constant Float := Float'Min (1.0, Float'Max (Kick, Rough * 0.3)) * 0.45;
               Flip : constant Boolean := (Integer (Float (Clock - Start_Time) * 25.0) mod 2) = 0;
               Push : constant Float := (if Flip then Shake else -Shake);
            begin
               if Shake < 0.02 then
                  Stop_Effect (D);
               elsif abs (Push - D.Sent_A) > 0.03 then
                  Play_Effect (D, FF_CONSTANT, Integer (32767.0 * Push), 0, 100);
                  D.Sent_A := Push;
                  D.Sent_At := Clock;
               end if;
            end;
      end case;
   end Feel_Device;

   procedure Try_Open (N : Natural) is
      Path : constant String := "/dev/input/js" & Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left);
      Fd : constant int := C_Open (To_C (Path), O_NONBLOCK);
      D : Device renames Devices (N);
      Count : aliased Unsigned_8 := 0;
      Name_Buf : aliased char_array (0 .. 127) := (others => nul);
      R : int;
      pragma Unreferenced (R);
   begin
      if Fd < 0 then
         return;
      end if;
      D := (Open => True, Fd => Fd, others => <>);
      R := C_Ioctl (Fd, JSIOCGAXES, Count'Address);
      D.Axes := Natural'Min (Natural (Count), Max_Axes);
      R := C_Ioctl (Fd, JSIOCGBUTTONS, Count'Address);
      D.Buttons := Natural'Min (Natural (Count), Max_Buttons);
      R := C_Ioctl (Fd, JSIOCGNAME, Name_Buf'Address);
      declare
         S : constant String := To_Ada (Name_Buf);
      begin
         D.Name_Len := Natural'Min (S'Length, D.Name'Length);
         D.Name (1 .. D.Name_Len) := S (S'First .. S'First + D.Name_Len - 1);
      end;
      R := C_Ioctl (Fd, JSIOCGAXMAP, D.Axis_Map'Address);
      if C_Ioctl (Fd, JSIOCGBTNMAP_Large, D.Btn_Map'Address) < 0 then
         R := C_Ioctl (Fd, JSIOCGBTNMAP_Small, D.Btn_Map'Address);
      end if;
      declare
         N_Up : constant String := D.Name (1 .. D.Name_Len);
         Has_A : Boolean := False;
      begin
         for K in 0 .. D.Buttons - 1 loop
            Has_A := Has_A or else D.Btn_Map (K) = BTN_A;
         end loop;
         D.Class :=
           (if Contains (N_Up, "WHEEL") or else Contains (N_Up, "G29") or else Contains (N_Up, "G920")
               or else Contains (N_Up, "G27") or else Contains (N_Up, "DRIVING FORCE") then Wheel
            elsif Contains (N_Up, "COMPETITION PRO") or else not Has_A then Stick
            else Pad);
      end;
      Open_Feedback (D, N);
      if Debug then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pad: " & Path & " " & D.Name (1 .. D.Name_Len)
                               & " as " & Kind'Image (D.Class)
                               & (if D.Ev_Fd >= 0 then ", with force feedback" else ""));
      end if;
   end Try_Open;

   procedure Close_Device (D : in out Device) is
      R : int;
      pragma Unreferenced (R);
   begin
      R := C_Close (D.Fd);
      if D.Ev_Fd >= 0 then
         R := C_Close (D.Ev_Fd);
      end if;
      if Debug then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pad gone: " & D.Name (1 .. D.Name_Len));
      end if;
      D := (others => <>);
   end Close_Device;

   function Owned (P : Natural) return Boolean is
     (for some D of Devices => D.Open and then D.Owner = P);

   Picks : array (Player_Number) of Integer := (others => 0);

   procedure Claim (D : in out Device) is
   begin
      if D.Owner = 0 then
         for P in Player_Number loop
            if not Owned (P) and then Picks (P) = 0 then
               D.Owner := P;
               if Debug then
                  Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "pad: " & D.Name (1 .. D.Name_Len) & " is player" & P'Image);
               end if;
               return;
            end if;
         end loop;
      end if;
   end Claim;

   function Axis_Code (D : Device; Index : Natural) return Natural is (Natural (D.Axis_Map (Index)));

   function Find_Axis (D : Device; Code : Natural) return Integer is
   begin
      for K in 0 .. D.Axes - 1 loop
         if Axis_Code (D, K) = Code then
            return K;
         end if;
      end loop;
      return -1;
   end Find_Axis;

   function Axis (D : Device; Code : Natural) return Float is
      K : constant Integer := Find_Axis (D, Code);
   begin
      return (if K < 0 then 0.0 else Float (D.Value (K)) / 32767.0);
   end Axis;

   --  A trigger or a pedal: 0 where it rests, 1 pressed right down
   function Pedal (D : Device; Code : Natural) return Float is
      K : constant Integer := Find_Axis (D, Code);
   begin
      if K < 0 then
         return 0.0;
      elsif D.Rest (K) > 16_000 then
         return Float'Max (0.0, Float (32767 - D.Value (K)) / 65534.0);
      elsif D.Rest (K) < -16_000 then
         return Float'Max (0.0, Float (D.Value (K) + 32767) / 65534.0);
      else
         return Float'Max (0.0, Float (abs D.Value (K)) / 32767.0);
      end if;
   end Pedal;

   function Button (D : Device; Code : Natural) return Boolean is
     (for some K in 0 .. D.Buttons - 1 => Natural (D.Btn_Map (K)) = Code and then D.Down (K));

   function Dead (V, Zone : Float) return Float is
     (if abs V < Zone then 0.0 elsif V > 0.0 then (V - Zone) / (1.0 - Zone) else (V + Zone) / (1.0 - Zone));

   --  What a button press means
   procedure Press (D : in out Device; Index : Natural) is
      Code : constant Natural := Natural (D.Btn_Map (Index));
      P : Natural;
   begin
      Claim (D);
      P := D.Owner;
      case Code is
         when BTN_A => Push (P, Ok);
         when BTN_B => Push (P, Fire); Push (P, Back);
         when BTN_X => null;   --  a brake
         when BTN_Y => Push (P, Camera);
         when BTN_TL | BTN_TR => Push (P, Fire);
         when BTN_START | BTN_MODE => Push (P, Pause);
         when BTN_SELECT => Push (P, Restart);
         when others =>
            --  a wheel's or a joystick's buttons, by their place
            case Index is
               when 0 => Push (P, Fire); Push (P, Ok);
               when 1 => Push (P, Camera); Push (P, Back);
               when 2 => Push (P, Fire); Push (P, Back);
               when 3 => Push (P, Camera);
               when 4 | 5 => Push (P, Fire);
               when 6 | 7 => Push (P, Restart);
               when 8 | 9 => Push (P, Pause);
               when others => Push (P, Fire);
            end case;
      end case;
   end Press;

   --  A stick or the cross moved: the menus hear it as a press
   procedure Moved (D : in out Device; Code : Natural; V : Integer) is
      Step : constant Integer := (if V < -20_000 then -1 elsif V > 20_000 then 1 else 0);
      Was  : Integer;
   begin
      if Code in ABS_X | ABS_HAT0X then
         Was := D.Stick_X;
         D.Stick_X := Step;
         if Step /= 0 and then Step /= Was then
            if Code = ABS_HAT0X then
               Claim (D);
            end if;
            Push (D.Owner, (if Step < 0 then Left else Right));
         end if;
      elsif Code in ABS_Y | ABS_HAT0Y and then D.Class /= Wheel then
         Was := D.Stick_Y;
         D.Stick_Y := Step;
         if Step /= 0 and then Step /= Was then
            if Code = ABS_HAT0Y or else D.Class = Stick then
               Claim (D);
            end if;
            Push (D.Owner, (if Step < 0 then Up else Down));
         end if;
      end if;
   end Moved;

   type Js_Event is record
      Time   : Unsigned_32;
      Value  : Integer_16;
      Kind   : Unsigned_8;
      Number : Unsigned_8;
   end record with Convention => C;

   procedure Poll is
   begin
      if Clock - Last_Scan > 2.0 then
         Last_Scan := Clock;
         for N in Devices'Range loop
            if not Devices (N).Open then
               Try_Open (N);
            end if;
         end loop;
      end if;
      for D of Devices loop
         if D.Open then
            loop
               declare
                  E : aliased Js_Event;
                  Got : constant long := C_Read (D.Fd, E'Address, 8);
                  N : constant Natural := Natural (E.Number);
                  Init : constant Boolean := (E.Kind and JS_EVENT_INIT) /= 0;
                  Kind_Of : constant Unsigned_8 := E.Kind and not JS_EVENT_INIT;
               begin
                  if Got /= 8 then
                     if Got < 0 and then GNAT.OS_Lib.Errno /= EAGAIN then
                        Close_Device (D);
                     end if;
                     exit;
                  end if;
                  if Debug and then not Init then
                     Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, D.Name (1 .. D.Name_Len) & (if Kind_Of = JS_EVENT_AXIS then " axis" else " button")
                                           & N'Image & " code" & Natural'Image
                                             (if Kind_Of = JS_EVENT_AXIS then Natural (D.Axis_Map (N mod Max_Axes))
                                              else Natural (D.Btn_Map (N mod Max_Buttons)))
                                           & " =" & E.Value'Image);
                  end if;
                  if Kind_Of = JS_EVENT_AXIS and then N < Max_Axes then
                     D.Value (N) := Integer (E.Value);
                     if Init then
                        D.Rest (N) := Integer (E.Value);
                     else
                        Moved (D, Axis_Code (D, N), Integer (E.Value));
                        --  a trigger or pedal pressed hard gives the controller to a player
                        if Axis_Code (D, N) in ABS_Z | ABS_RZ | ABS_GAS | ABS_BRAKE | ABS_Y
                          and then D.Class /= Stick and then Pedal (D, Axis_Code (D, N)) > 0.6
                          and then (D.Class = Wheel or else Axis_Code (D, N) /= ABS_Y)
                        then
                           Claim (D);
                        end if;
                     end if;
                  elsif Kind_Of = JS_EVENT_BUTTON and then N < Max_Buttons then
                     D.Down (N) := E.Value /= 0;
                     if not Init and then E.Value /= 0 then
                        Press (D, N);
                     end if;
                  end if;
               end;
            end loop;
         end if;
      end loop;
   end Poll;

   function Read_Of (D : Device) return Reading is
      R : Reading;
      Hat : constant Float := Axis (D, ABS_HAT0X);
   begin
      case D.Class is
         when Pad =>
            R.Steer := Dead (Axis (D, ABS_X), 0.18);
            R.Throttle := Float'Max (Pedal (D, ABS_RZ), (if Button (D, BTN_A) then 1.0 else 0.0));
            R.Brake := Float'Max (Pedal (D, ABS_Z), (if Button (D, BTN_X) then 1.0 else 0.0));
         when Wheel =>
            --  the wheel turns far: a third of the way round is full lock
            R.Steer := Float'Max (-1.0, Float'Min (1.0, 3.0 * Dead (Axis (D, ABS_X), 0.01)));
            R.Throttle := Pedal (D, ABS_Y);
            R.Brake := Pedal (D, ABS_Z);
         when Stick =>
            R.Steer := Dead (Axis (D, ABS_X), 0.3);
            R.Throttle := Float'Max ((if Axis (D, ABS_Y) < -0.5 then 1.0 else 0.0), Pedal (D, ABS_GAS));
            R.Brake := Float'Max ((if Axis (D, ABS_Y) > 0.5 then 1.0 else 0.0), Pedal (D, ABS_BRAKE));
      end case;
      if Hat /= 0.0 then
         R.Steer := Hat;
      end if;
      R.Steer := Float'Max (-1.0, Float'Min (1.0, R.Steer));
      return R;
   end Read_Of;

   function Has (P : Player_Number) return Boolean is (Owned (P));

   function Get (P : Player_Number) return Reading is
   begin
      for D of Devices loop
         if D.Open and then D.Owner = P then
            return Read_Of (D);
         end if;
      end loop;
      return (others => <>);
   end Get;

   function Name (P : Player_Number) return String is
   begin
      for D of Devices loop
         if D.Open and then D.Owner = P then
            return D.Name (1 .. D.Name_Len);
         end if;
      end loop;
      return "";
   end Name;

   function Count return Natural is
      N : Natural := 0;
   begin
      for D of Devices loop
         if D.Open then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count;

   procedure Feel (P : Player_Number; Kick, Rough, Speed_Share : Float) is
   begin
      for D of Devices loop
         if D.Open and then D.Owner = P then
            Feel_Device (D, Kick, Rough, Speed_Share);
         end if;
      end loop;
   end Feel;

   procedure Quiet is
   begin
      for D of Devices loop
         if D.Open and then D.Ev_Fd >= 0 then
            Stop_Effect (D);
            Set_Center (D, 0.25);
         end if;
      end loop;
   end Quiet;

   procedure Shut_Down is
   begin
      for D of Devices loop
         if D.Open and then D.Ev_Fd >= 0 then
            Stop_Effect (D);
            if D.Class = Wheel then
               Send (D, FF_AUTOCENTER, 0);
            end if;
         end if;
      end loop;
   end Shut_Down;

   function Device_Count return Natural renames Count;

   --  The index in Devices of the K-th one open
   function Nth (K : Positive) return Integer is
      N : Natural := 0;
   begin
      for I in Devices'Range loop
         if Devices (I).Open then
            N := N + 1;
            if N = K then
               return I;
            end if;
         end if;
      end loop;
      return -1;
   end Nth;

   function Device_Name (K : Positive) return String is
      I : constant Integer := Nth (K);
   begin
      return (if I < 0 then "" else Devices (I).Name (1 .. Devices (I).Name_Len));
   end Device_Name;

   procedure Choose (P : Player_Number; K : Integer) is
      I : constant Integer := (if K > 0 then Nth (K) else -1);
   begin
      Picks (P) := K;
      for D of Devices loop
         if D.Owner = P then
            D.Owner := 0;
         end if;
      end loop;
      if I >= 0 then
         Devices (I).Owner := P;
      end if;
   end Choose;

   function Chosen (P : Player_Number) return Integer is (Picks (P));

   procedure Release_All is
   begin
      for D of Devices loop
         D.Owner := 0;
      end loop;
   end Release_All;

end Pads;
