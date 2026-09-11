with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Text_IO;
with Fuzzy;

procedure Bench_Fuzzy is
   use Ada.Real_Time;
   use Fuzzy;
   Count      : constant Positive :=
     (if Ada.Command_Line.Argument_Count > 0
      then Positive'Value (Ada.Command_Line.Argument (1))
      else 100_000);
   Query      : constant String :=
     (if Ada.Command_Line.Argument_Count > 1
      then Ada.Command_Line.Argument (2)
      else "fma");
   Capacity   : constant Natural :=
     (if Ada.Command_Line.Argument_Count > 2
      then Natural'Value (Ada.Command_Line.Argument (3))
      else 30);
   Repeats    : constant Positive := 20;
   Width      : constant := 50;
   Data       : String (1 .. Count * Width);
   Candidates : Candidate_Array (1 .. Count);
   Results    : Search_Result_Array (1 .. Capacity);
   Found      : Natural;
   Start      : Time;
   Elapsed    : Duration;
   Checksum   : Long_Long_Integer := 0;
begin
   for C in Candidates'Range loop
      declare
         First  : constant Positive := (C - 1) * Width + 1;
         Name   : String (1 .. Width) := [others => 'x'];
         Number : Natural := C;
      begin
         Name (1 .. 20) := "src/fuzzy_matcher_ab";
         for J in reverse 21 .. 30 loop
            Name (J) := Character'Val (Character'Pos ('0') + Number mod 10);
            Number := Number / 10;
         end loop;
         Name (47 .. 50) := ".adb";
         Data (First .. First + Width - 1) := Name;
         Candidates (C) := (Text => (First, Width));
      end;
   end loop;
   Start := Clock;
   for Trial in 1 .. Repeats loop
      Search (Query, Data, Candidates, Results, Found);
      for R in 1 .. Found loop
         Checksum :=
           Checksum
           + Long_Long_Integer (Results (R).Candidate)
           + Long_Long_Integer (Results (R).Score);
      end loop;
   end loop;
   Elapsed := To_Duration (Clock - Start);
   Ada.Text_IO.Put_Line
     ("candidates="
      & Count'Image
      & " width=50 K="
      & Capacity'Image
      & " repeats=20 query="
      & Query);
   Ada.Text_IO.Put_Line
     ("seconds=" & Elapsed'Image & " checksum=" & Checksum'Image);
end Bench_Fuzzy;
