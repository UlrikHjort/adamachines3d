--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The time of day and the weather a race is run in.  Only how it looks:
--  the race itself is the same, so a network game is the same everywhere.

package Air is

   type Time_Kind is (Day, Sunset, Night);
   type Weather_Kind is (Clear, Rain, Snow);

   Time    : Time_Kind := Day;
   Weather : Weather_Kind := Clear;

   function Time_Name (T : Time_Kind) return String is
     (case T is when Day => "DAY", when Sunset => "SUNSET", when Night => "NIGHT");
   function Weather_Name (W : Weather_Kind) return String is
     (case W is when Clear => "CLEAR", when Rain => "RAIN", when Snow => "SNOW");

end Air;
