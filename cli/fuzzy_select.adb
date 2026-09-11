with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Fuzzy;
with Fuzzy_Term;

package body Fuzzy_Select is
   use Ada.Strings.Unbounded;

   ESC     : constant Character := Character'Val (27);
   CSI     : constant String := ESC & "[";
   --  Raw mode turns off output post-processing, so a line feed alone leaves
   --  the cursor in the column it was in.
   New_Row : constant String := Character'Val (13) & Character'Val (10);

   type Result_Buffer is access Fuzzy.Search_Result_Array;
   procedure Free is new
     Ada.Unchecked_Deallocation (Fuzzy.Search_Result_Array, Result_Buffer);

   function Image (Value : Natural) return String is
      Text : constant String := Natural'Image (Value);
   begin
      return Text (Text'First + 1 .. Text'Last);
   end Image;

   procedure Run
     (Corpus        : Fuzzy_Input.Corpus;
      Initial_Query : String;
      Multi         : Boolean;
      Chosen        : out Natural;
      Marks         : out Mark_Array;
      Status        : out Natural)
   is
      Data  : String renames Corpus.Text (1 .. Corpus.Used);
      Items : Fuzzy.Candidate_Array renames Corpus.Items (1 .. Corpus.Count);

      Query  : String (1 .. 1024);
      Length : Natural := 0;
      Point  : Natural := 0;

      --  The matcher returns the best K, so K bounds how far the selection
      --  can travel. Rather than pay for a large K on every keystroke, it
      --  starts at one screenful and doubles only when the selection actually
      --  reaches the end of what was returned.
      Capacity     : Positive := 1;
      Results      : Result_Buffer;
      Found        : Natural := 0;
      Selected     : Natural := 0;
      Top          : Positive := 1;
      Stale        : Boolean := True;
      Marked_Count : Natural := 0;

      procedure Refresh is
      begin
         if Results = null or else Results'Length /= Capacity then
            Free (Results);
            Results := new Fuzzy.Search_Result_Array (1 .. Capacity);
         end if;
         if Length = 0 then
            --  An empty pattern matches everything with a score of minus the
            --  candidate length, so ranking it would order the corpus by
            --  length. That is meaningless for a caller whose input already
            --  carries an order, such as a history list running from the most
            --  recent entry, so the input order is kept instead.
            Found := Natural'Min (Capacity, Items'Length);
            for Slot in 1 .. Found loop
               Results (Slot) :=
                 (Candidate => Items'First + (Slot - 1), Score => 0);
            end loop;
         else
            Fuzzy.Search
              (Query (1 .. Length), Data, Items, Results.all, Found);
         end if;
         Selected := Natural'Min (Natural'Max (Selected, 1), Found);
         Top := Positive'Min (Top, Positive'Max (Selected, 1));
         Stale := False;
      end Refresh;

      --  Render one candidate, highlighting the characters the pattern
      --  matched and cutting the line to the width available.
      procedure Put_Candidate
        (Frame : in out Unbounded_String; Slot : Positive; Width : Natural)
      is
         Slice     : constant Fuzzy.Text_Slice :=
           Items (Results (Slot).Candidate).Text;
         Positions : Fuzzy.Match_Position_Array (1 .. Natural'Max (Length, 1));
         Matched   : Boolean;
         Value     : Fuzzy.Score_Type;
         Marked    : Natural;
         Next      : Positive := 1;
         Shown     : constant Natural := Natural'Min (Slice.Length, Width);
      begin
         Fuzzy.Match_Details
           (Query (1 .. Length),
            Data,
            Slice,
            Matched,
            Value,
            Positions,
            Marked);
         for Offset in 1 .. Shown loop
            declare
               Item  : constant Character :=
                 Fuzzy.Character_At (Data, Slice, Offset);
               --  A candidate may hold any byte, and writing a control
               --  character to a terminal in raw mode would move the cursor
               --  rather than print. Each stands in for exactly one byte, so
               --  the highlight offsets still line up with what is shown.
               Shape : constant String :=
                 (if Item = Character'Val (10)
                  then "↵"
                  elsif Item < ' ' or else Item = Character'Val (127)
                  then "·"
                  else (1 => Item));
            begin
               if Next <= Marked and then Positions (Next) = Offset then
                  Append (Frame, CSI & "32m" & Shape & CSI & "39m");
                  Next := Next + 1;
               else
                  Append (Frame, Shape);
               end if;
            end;
         end loop;
         if Slice.Length > Shown then
            Append (Frame, "…");
         end if;
      end Put_Candidate;

      procedure Draw (List_Rows : Natural; Cols : Positive) is
         Frame : Unbounded_String;
         Width : constant Natural := (if Cols > 3 then Cols - 3 else 1);
         Last  : Natural;
      begin
         if Selected > 0 then
            if Selected < Top then
               Top := Selected;
            elsif List_Rows > 0 and then Selected > Top + (List_Rows - 1) then
               Top := Selected - (List_Rows - 1);
            end if;
         end if;
         Append (Frame, CSI & "?25l" & CSI & "H" & CSI & "2J");
         Append (Frame, "> " & Query (1 .. Length) & New_Row);
         Append
           (Frame,
            CSI
            & "90m  "
            & Image (Found)
            & (if Found = Capacity and then Found < Corpus.Count
               then "+"
               else "")
            & "/"
            & Image (Corpus.Count)
            & (if Marked_Count > 0
               then " (" & Image (Marked_Count) & ")"
               else "")
            & CSI
            & "39m"
            & New_Row);
         Last := Natural'Min (Found, Top + (List_Rows - 1));
         for Slot in Top .. Last loop
            declare
               Mark : constant String :=
                 (if Marks (Results (Slot).Candidate) then "+" else " ");
            begin
               if Slot = Selected then
                  Append (Frame, CSI & "1m>" & Mark);
                  Put_Candidate (Frame, Slot, Width);
                  Append (Frame, CSI & "0m");
               else
                  Append (Frame, " " & Mark);
                  Put_Candidate (Frame, Slot, Width);
               end if;
            end;
            Append (Frame, New_Row);
         end loop;
         --  Leave the cursor where the caret belongs, on the query line.
         Append (Frame, CSI & "1;" & Image (3 + Point) & "H" & CSI & "?25h");
         Fuzzy_Term.Write (To_String (Frame));
      end Draw;

      procedure Insert (Item : Character) is
      begin
         if Length = Query'Last then
            return;
         end if;
         Query (Point + 2 .. Length + 1) := Query (Point + 1 .. Length);
         Query (Point + 1) := Item;
         Length := Length + 1;
         Point := Point + 1;
         Stale := True;
      end Insert;

      procedure Delete_At (From : Positive) is
      begin
         Query (From .. Length - 1) := Query (From + 1 .. Length);
         Length := Length - 1;
         Stale := True;
      end Delete_At;

      procedure Delete_Word is
         Edge : Natural := Point;
      begin
         while Edge > 0 and then Query (Edge) = ' ' loop
            Edge := Edge - 1;
         end loop;
         while Edge > 0 and then Query (Edge) /= ' ' loop
            Edge := Edge - 1;
         end loop;
         while Point > Edge loop
            Delete_At (Point);
            Point := Point - 1;
         end loop;
      end Delete_Word;

      --  Marks belong to candidates rather than to result slots, so they
      --  survive a change of query that reorders or hides them.
      procedure Toggle is
         Which : Positive;
      begin
         if not Multi or else Selected = 0 then
            return;
         end if;
         Which := Results (Selected).Candidate;
         Marks (Which) := not Marks (Which);
         Marked_Count :=
           (if Marks (Which) then Marked_Count + 1 else Marked_Count - 1);
      end Toggle;

      procedure Move_Down is
      begin
         if Selected < Found then
            Selected := Selected + 1;
         elsif Found = Capacity and then Found < Corpus.Count then
            Capacity :=
              (if Capacity > Positive'Last / 2
               then Positive'Last
               else Capacity * 2);
            Refresh;
            if Selected < Found then
               Selected := Selected + 1;
            end if;
         end if;
      end Move_Down;

      Keys       : Fuzzy_Term.Key_Array (1 .. 64);
      Count      : Natural;
      Rows, Cols : Positive;
      List_Rows  : Natural;
      Opened     : Boolean;
      Done       : Boolean := False;
   begin
      Chosen := 0;
      Status := 130;
      Marks := (others => False);
      if Initial_Query'Length > 0 then
         Length := Natural'Min (Initial_Query'Length, Query'Length);
         Query (1 .. Length) :=
           Initial_Query
             (Initial_Query'First .. Initial_Query'First + (Length - 1));
         Point := Length;
      end if;

      Fuzzy_Term.Open (Opened);
      if not Opened then
         Status := 2;
         return;
      end if;

      while not Done loop
         Fuzzy_Term.Size (Rows, Cols);
         List_Rows := (if Rows > 2 then Rows - 2 else 1);
         if Capacity < List_Rows then
            Capacity := List_Rows;
            Stale := True;
         end if;
         if Stale then
            Refresh;
         end if;
         Draw (List_Rows, Cols);

         Fuzzy_Term.Read_Keys (Keys, Count);
         if Count = 0 then
            Done := True;
         end if;
         for K in 1 .. Count loop
            case Keys (K).Kind is
               when Fuzzy_Term.Char           =>
                  Insert (Keys (K).Ch);

               when Fuzzy_Term.Backspace      =>
                  if Point > 0 then
                     Delete_At (Point);
                     Point := Point - 1;
                  end if;

               when Fuzzy_Term.Delete_Forward =>
                  if Point < Length then
                     Delete_At (Point + 1);
                  end if;

               when Fuzzy_Term.Delete_Word    =>
                  Delete_Word;

               when Fuzzy_Term.Clear_Line     =>
                  Length := 0;
                  Point := 0;
                  Stale := True;

               when Fuzzy_Term.Left           =>
                  if Point > 0 then
                     Point := Point - 1;
                  end if;

               when Fuzzy_Term.Right          =>
                  if Point < Length then
                     Point := Point + 1;
                  end if;

               when Fuzzy_Term.Line_Start     =>
                  Point := 0;

               when Fuzzy_Term.Line_End       =>
                  Point := Length;

               when Fuzzy_Term.Up             =>
                  if Selected > 1 then
                     Selected := Selected - 1;
                  end if;

               when Fuzzy_Term.Down           =>
                  Move_Down;

               when Fuzzy_Term.Mark_Down      =>
                  Toggle;
                  Move_Down;

               when Fuzzy_Term.Mark_Up        =>
                  Toggle;
                  if Selected > 1 then
                     Selected := Selected - 1;
                  end if;

               when Fuzzy_Term.Enter          =>
                  if Selected > 0 then
                     Chosen := Results (Selected).Candidate;
                     Status := 0;
                  else
                     Status := 1;
                  end if;
                  Done := True;

               when Fuzzy_Term.Accept_Abort   =>
                  Status := 130;
                  Done := True;

               when Fuzzy_Term.Ignored        =>
                  null;
            end case;
            --  A query edit invalidates the selection window as well.
            if Stale then
               Selected := 1;
               Top := 1;
            end if;
            exit when Done;
         end loop;
      end loop;

      Fuzzy_Term.Close;
      Free (Results);
   end Run;

end Fuzzy_Select;
