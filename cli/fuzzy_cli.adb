with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Text_IO.Text_Streams;
with Fuzzy;
with Fuzzy_Input;
with Fuzzy_Select;

procedure Fuzzy_CLI is
   use Ada.Command_Line;
   use Ada.Text_IO;

   Output : constant Ada.Text_IO.Text_Streams.Stream_Access :=
     Ada.Text_IO.Text_Streams.Stream (Standard_Output);

   --  Input and output framing are chosen independently, matching the way the
   --  shell integration asks for them.
   Read_Delimiter  : Character := Ada.Characters.Latin_1.LF;
   Write_Delimiter : Character := Ada.Characters.Latin_1.LF;
   Interactive     : Boolean := False;
   Multi           : Boolean := False;

   Corpus : Fuzzy_Input.Corpus;
   Limit  : Natural := 30;

   procedure Usage is
   begin
      Put_Line
        (Standard_Error, "usage: fuzzy [--read0] [--print0] [--] QUERY [K]");
      Put_Line
        (Standard_Error,
         "       fuzzy --interactive [--multi] [--read0] [--print0] [--]"
         & " [QUERY]");
      Put_Line
        (Standard_Error,
         "  one candidate per stdin record; candidates are read to end of"
         & " input");
      Set_Exit_Status (Failure);
   end Usage;

   procedure Fail (Reason : String) is
   begin
      Put_Line (Standard_Error, Reason);
      Set_Exit_Status (Failure);
   end Fail;

   --  Options are the arguments beginning with two dashes; everything else is
   --  positional. A lone "--" ends them, so a query that itself starts with a
   --  dash stays reachable.
   function Is_Option (Arg : String) return Boolean
   is (Arg'Length >= 2 and then Arg (Arg'First .. Arg'First + 1) = "--");

   procedure Put_Candidate (Slice : Fuzzy.Text_Slice) is
      Data : String renames Corpus.Text (1 .. Corpus.Used);
   begin
      if Slice.Length > 0 then
         String'Write
           (Output, Data (Slice.First .. Slice.First + (Slice.Length - 1)));
      end if;
      Character'Write (Output, Write_Delimiter);
   end Put_Candidate;

   type Mark_Buffer is access Fuzzy_Select.Mark_Array;

   First_Positional : Positive := 1;
   Positionals      : Natural;
   Ok               : Boolean;
begin
   while First_Positional <= Argument_Count
     and then Is_Option (Argument (First_Positional))
   loop
      declare
         Option : constant String := Argument (First_Positional);
      begin
         First_Positional := First_Positional + 1;
         if Option = "--" then
            exit;
         elsif Option = "--read0" then
            Read_Delimiter := Ada.Characters.Latin_1.NUL;
         elsif Option = "--print0" then
            Write_Delimiter := Ada.Characters.Latin_1.NUL;
         elsif Option = "--interactive" then
            Interactive := True;
         elsif Option = "--multi" then
            Multi := True;
         else
            Usage;
            return;
         end if;
      end;
   end loop;
   Positionals := Argument_Count - First_Positional + 1;
   --  Interactively the query is only a starting point and the display
   --  bounds how many results are useful, so K has no meaning there.
   if Positionals
      not in (if Interactive then 0 else 1) .. (if Interactive then 1 else 2)
   then
      Usage;
      return;
   end if;
   if not Interactive and then Positionals = 2 then
      begin
         Limit := Natural'Value (Argument (First_Positional + 1));
      exception
         when Constraint_Error =>
            Usage;
            return;
      end;
   end if;

   Fuzzy_Input.Read_Standard_Input (Corpus, Read_Delimiter, Ok);
   if not Ok then
      Fail ("input exceeds the representable buffer size");
      return;
   end if;

   if Interactive then
      declare
         Query      : constant String :=
           (if Positionals = 1 then Argument (First_Positional) else "");
         --  One flag per candidate, which the corpus may well have many of.
         Marks      : constant Mark_Buffer :=
           new Fuzzy_Select.Mark_Array (1 .. Corpus.Count);
         Chosen     : Natural;
         Status     : Natural;
         Any_Marked : Boolean := False;
      begin
         Fuzzy_Select.Run (Corpus, Query, Multi, Chosen, Marks.all, Status);
         if Status = 2 then
            Fail ("no usable terminal on /dev/tty");
            return;
         end if;
         --  Marking anything replaces the candidate under the cursor, which
         --  is what makes Tab additive rather than a second way to accept.
         for Which in Marks'Range loop
            if Marks (Which) then
               Any_Marked := True;
               Put_Candidate (Corpus.Items (Which).Text);
            end if;
         end loop;
         if not Any_Marked and then Chosen > 0 then
            Put_Candidate (Corpus.Items (Chosen).Text);
         end if;
         Set_Exit_Status (Exit_Status (Status));
      end;
      return;
   end if;

   declare
      Data       : String renames Corpus.Text (1 .. Corpus.Used);
      Candidates : Fuzzy.Candidate_Array renames
        Corpus.Items (1 .. Corpus.Count);
      Results    :
        Fuzzy.Search_Result_Array (1 .. Natural'Min (Limit, Corpus.Count));
      Found      : Natural;
   begin
      Fuzzy.Search
        (Argument (First_Positional), Data, Candidates, Results, Found);
      for R in 1 .. Found loop
         Put_Candidate (Candidates (Results (R).Candidate).Text);
      end loop;
   end;
end Fuzzy_CLI;
