with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Fuzzy.Corpus;

procedure Fuzzy_CLI is
   use Ada.Command_Line;
   use Ada.Text_IO;

   type Text_Buffer is access String;
   type Candidate_Buffer is access Fuzzy.Candidate_Array;
   procedure Free is new Ada.Unchecked_Deallocation (String, Text_Buffer);
   procedure Free is
     new Ada.Unchecked_Deallocation (Fuzzy.Candidate_Array, Candidate_Buffer);

   --  The library never allocates; the corpus storage belongs here because
   --  standard input has no size known in advance. Both buffers start at
   --  index one and grow by doubling. Slices survive a move because they are
   --  absolute indexes into a buffer whose lower bound and filled prefix the
   --  move preserves.
   Text : Text_Buffer := new String (1 .. 64 * 1024);
   Used : Natural := 0;
   Items : Candidate_Buffer := new Fuzzy.Candidate_Array (1 .. 1024);
   Count : Natural := 0;
   Limit : Natural := 30;

   procedure Usage is
   begin
      Put_Line (Standard_Error, "usage: fuzzy QUERY [K]  (one candidate per stdin line)");
      Set_Exit_Status (Failure);
   end Usage;

   procedure Overflow is
   begin
      Put_Line (Standard_Error, "input exceeds the representable buffer size");
      Set_Exit_Status (Failure);
   end Overflow;

   --  Next capacity, or zero when the current one cannot be doubled within
   --  the representable index range.
   function Doubled (Length : Positive) return Natural is
     (if Length >= Natural'Last / 2 then
        (if Length = Natural'Last then 0 else Natural'Last)
      else Length * 2);

   procedure Grow_Text (Ok : out Boolean) is
      Wanted : constant Natural := Doubled (Text'Length);
      Bigger : Text_Buffer;
   begin
      if Wanted = 0 then
         Ok := False;
         return;
      end if;
      Bigger := new String (1 .. Wanted);
      Bigger (1 .. Used) := Text (1 .. Used);
      Free (Text);
      Text := Bigger;
      Ok := True;
   exception
      when Storage_Error =>
         Ok := False;
   end Grow_Text;

   procedure Grow_Items (Ok : out Boolean) is
      Wanted : constant Natural := Doubled (Items'Length);
      Bigger : Candidate_Buffer;
   begin
      if Wanted = 0 then
         Ok := False;
         return;
      end if;
      Bigger := new Fuzzy.Candidate_Array (1 .. Wanted);
      Bigger (1 .. Count) := Items (1 .. Count);
      Free (Items);
      Items := Bigger;
      Ok := True;
   exception
      when Storage_Error =>
         Ok := False;
   end Grow_Items;
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
         Slice : Fuzzy.Text_Slice;
         Ok : Boolean;
      begin
         loop
            Fuzzy.Corpus.Append (Text.all, Used, Line, Slice, Ok);
            exit when Ok;
            Grow_Text (Ok);
            if not Ok then
               Overflow;
               return;
            end if;
         end loop;
         if Count = Items'Length then
            Grow_Items (Ok);
            if not Ok then
               Overflow;
               return;
            end if;
         end if;
         Count := Count + 1;
         Items (Count) := (Text => Slice);
      end;
   end loop;
   declare
      Data : String renames Text (1 .. Used);
      Candidates : Fuzzy.Candidate_Array renames Items (1 .. Count);
      Results : Fuzzy.Search_Result_Array (1 .. Natural'Min (Limit, Count));
      Found : Natural;
   begin
      Fuzzy.Search (Argument (1), Data, Candidates, Results, Found);
      for R in 1 .. Found loop
         declare
            Slice : constant Fuzzy.Text_Slice :=
              Candidates (Results (R).Candidate).Text;
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
