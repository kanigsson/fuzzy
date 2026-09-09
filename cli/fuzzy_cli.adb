with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Fuzzy;

procedure Fuzzy_CLI is
   use Ada.Command_Line;
   use type Ada.Containers.Count_Type;
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   package Candidate_Vectors is new Ada.Containers.Vectors
     (Positive, Fuzzy.Candidate, Fuzzy."=");
   Text : Unbounded_String;
   Items : Candidate_Vectors.Vector;
   Limit : Natural := 30;

   procedure Usage is
   begin
      Put_Line (Standard_Error, "usage: fuzzy QUERY [K]  (one candidate per stdin line)");
      Set_Exit_Status (Failure);
   end Usage;
begin
   if Argument_Count not in 1 .. 2 then
      Usage;
      return;
   end if;
   if Argument_Count = 2 then
      begin
         Limit := Natural'Value (Argument (2));
      exception
         when Constraint_Error =>
            Usage;
            return;
      end;
   end if;
   while not End_Of_File loop
      declare
         Line : constant String := Get_Line;
         First : Positive := 1;
      begin
         if Line'Length > Natural'Last - Length (Text)
           or else Items.Length = Ada.Containers.Count_Type (Natural'Last)
         then
            Put_Line (Standard_Error, "input exceeds the representable buffer size");
            Set_Exit_Status (Failure);
            return;
         end if;
         if Line'Length > 0 then
            First := Length (Text) + 1;
         end if;
         Items.Append (Fuzzy.Candidate'(Text => (First, Line'Length)));
         Append (Text, Line);
      end;
   end loop;
   declare
      Data : constant String := To_String (Text);
      Candidates : Fuzzy.Candidate_Array (1 .. Natural (Items.Length));
      Results : Fuzzy.Search_Result_Array (1 .. Natural'Min (Limit, Candidates'Length));
      Count : Natural;
   begin
      for C in Candidates'Range loop
         Candidates (C) := Items (C);
      end loop;
      Fuzzy.Search (Argument (1), Data, Candidates, Results, Count);
      for R in 1 .. Count loop
         declare
            Slice : constant Fuzzy.Text_Slice := Candidates (Results (R).Candidate).Text;
         begin
            if Slice.Length = 0 then
               New_Line;
            else
               Put_Line (Data (Slice.First .. Slice.First + (Slice.Length - 1)));
            end if;
         end;
      end loop;
   end;
end Fuzzy_CLI;
