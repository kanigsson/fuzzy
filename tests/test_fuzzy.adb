with Ada.Text_IO;
with Fuzzy;
with Fuzzy.Corpus;

procedure Test_Fuzzy is
   use Fuzzy;
   Checks : Natural := 0;
   procedure Check (Condition : Boolean) is
   begin
      Checks := Checks + 1;
      if not Condition then
         raise Program_Error with "check" & Checks'Image;
      end if;
   end Check;

   --  Independent existential oracle: explore both using and skipping a
   --  character. This deliberately does not use the library's greedy scan.
   function Exists (P, T : String) return Boolean is
   begin
      if P'Length = 0 then
         return True;
      elsif T'Length = 0 then
         return False;
      else
         return (P (P'First) = T (T'First)
                 and then Exists (P (P'First + 1 .. P'Last),
                                  T (T'First + 1 .. T'Last)))
           or else Exists (P, T (T'First + 1 .. T'Last));
      end if;
   end Exists;

   function Reference_Score (P, T : String) return Score_Type is
      Positions : Match_Position_Array (1 .. P'Length);
      Next : Natural := T'First;
      Base : Natural := T'First;
      Previous : Natural := T'First - 1;
      Value : Score_Type := -Score_Type (T'Length);
      N : Natural := 0;
   begin
      for J in T'Range loop
         if T (J) in '/' | '\' then
            Base := J + 1;
         end if;
      end loop;
      for Ch of P loop
         while Next <= T'Last and then T (Next) /= Ch loop
            Next := Next + 1;
         end loop;
         if Next > T'Last then
            return 0;
         end if;
         N := N + 1;
         Positions (N) := Next;
         Next := Next + 1;
      end loop;
      for J of Positions loop
         Value := Value + 16 - 2 * Score_Type (J - Previous - 1);
         if Previous >= T'First and then J = Previous + 1 then
            Value := Value + 12;
         end if;
         if J = T'First or else T (J - 1) in '/' | '\' then
            Value := Value + 16;
         end if;
         if J > T'First and then
           (T (J - 1) in '_' | '-' | '.' | ' '
            or else (T (J - 1) in 'a' .. 'z' and then T (J) in 'A' .. 'Z'))
         then
            Value := Value + 8;
         end if;
         if J >= Base then
            Value := Value + 8;
         end if;
         Previous := J;
      end loop;
      return Value;
   end Reference_Score;

   procedure Pair (P, T : String) is
      Data : constant String (17 .. 16 + T'Length) := T;
      Pattern : constant String (5 .. 4 + P'Length) := P;
      Slice : constant Text_Slice := (17, T'Length);
      M, D : Boolean;
      V, W : Score_Type;
      Positions : Match_Position_Array (9 .. 10 + P'Length);
      Count : Natural;
   begin
      Score (Pattern, Data, Slice, M, V);
      Match_Details (Pattern, Data, Slice, D, W, Positions, Count);
      Check (M = Exists (P, T));
      Check (M = D and V = W);
      Check (V = Reference_Score (P, T));
      Check (Count = (if M then P'Length else 0));
      for J in 1 .. Count loop
         Check (Positions (8 + J) <= T'Length);
         Check (T (T'First + Positions (8 + J) - 1) = P (P'First + J - 1));
         if J > 1 then
            Check (Positions (7 + J) < Positions (8 + J));
         end if;
      end loop;
   end Pair;

   Alphabet : constant String := "aB/_";
   function Word (Code : Natural; Size : Natural) return String is
      Result : String (1 .. Size);
      Rest : Natural := Code;
   begin
      for C of Result loop
         C := Alphabet (Rest mod Alphabet'Length + 1);
         Rest := Rest / Alphabet'Length;
      end loop;
      return Result;
   end Word;

   procedure Search_Case (P : String; Capacity : Natural) is
      Data : constant String := "ab/aBa_abab/aBxyz";
      Items : constant Candidate_Array (7 .. 14) :=
        [(Text => (1, 2)), (Text => (4, 2)), (Text => (1, 5)),
         (Text => (6, 3)), (Text => (9, 2)), (Text => (1, 0)),
         (Text => (9, 5)), (Text => (14, 3))];
      Results : Search_Result_Array (19 .. 18 + Capacity);
      Expected : Search_Result_Array (1 .. Items'Length);
      Count, Total : Natural := 0;
      Used : array (Items'Range) of Boolean := [others => False];
      Best : Natural;
      Best_Value, V : Score_Type;
   begin
      --  Independent full selection sort, then truncate to K.
      loop
         Best := 0;
         Best_Value := Score_Type'First;
         for C in Items'Range loop
            declare
               S : constant Text_Slice := Items (C).Text;
               T : constant String := Data (S.First .. S.First + S.Length - 1);
            begin
               if not Used (C) and then Exists (P, T) then
                  V := Reference_Score (P, T);
                  if Best = 0 or else V > Best_Value or else
                    (V = Best_Value and then
                     (S.Length < Items (Best).Text.Length or else
                      (S.Length = Items (Best).Text.Length and then C < Best)))
                  then
                     Best := C;
                     Best_Value := V;
                  end if;
               end if;
            end;
         end loop;
         exit when Best = 0;
         Total := Total + 1;
         Expected (Total) := (Best, Best_Value);
         Used (Best) := True;
      end loop;
      Search (P, Data, Items, Results, Count);
      Check (Count = Natural'Min (Total, Capacity));
      for R in 1 .. Count loop
         Check (Results (18 + R) = Expected (R));
      end loop;
   end Search_Case;
   --  One of four corpus items, named by a digit so sequences of appends can
   --  be enumerated as strings.
   function Piece (Kind : Natural) return String is
     (case Kind is
        when 0 => "",
        when 1 => "a",
        when 2 => "ab",
        when others => "b/a");

   function Text_Of (Data : String; Slice : Text_Slice) return String is
     (if Slice.Length = 0 then ""
      else Data (Slice.First .. Slice.First + (Slice.Length - 1)));

   --  Replay one sequence of appends into a buffer of the given capacity and
   --  check the reported slices, the untouched-on-failure guarantee, that
   --  earlier slices survive later appends, and that the packed result is a
   --  usable Search input both whole and trimmed to the fill level.
   procedure Check_Build (Capacity : Natural; Sequence : String) is
      Buffer : String (1 .. Capacity) := [others => '#'];
      Used : Natural := 0;
      Slices : array (1 .. Sequence'Length) of Text_Slice := [others => (1, 0)];
      Kinds : array (1 .. Sequence'Length) of Natural := [others => 0];
      Kept : Natural := 0;
   begin
      for S in Sequence'Range loop
         declare
            Kind : constant Natural :=
              Character'Pos (Sequence (S)) - Character'Pos ('0');
            Item : constant String := Piece (Kind);
            Before : constant String := Buffer;
            Before_Used : constant Natural := Used;
            Slice : Text_Slice;
            Ok : Boolean;
         begin
            Check (Corpus.Room (Buffer, Used) = Capacity - Used);
            Corpus.Append (Buffer, Used, Item, Slice, Ok);
            Check (Ok = (Item'Length <= Capacity - Before_Used));
            if Ok then
               Check (Used = Before_Used + Item'Length);
               Check (Slice = Corpus.Appended_Slice (Before, Before_Used, Item));
               Check (Valid (Buffer, Slice));
               Check (Corpus.Holds (Buffer, Slice, Item));
               Check (Buffer (1 .. Before_Used) = Before (1 .. Before_Used));
               Kept := Kept + 1;
               Slices (Kept) := Slice;
               Kinds (Kept) := Kind;
            else
               Check (Used = Before_Used and then Buffer = Before);
               Check (Slice.Length = 0);
            end if;
         end;
      end loop;
      for K in 1 .. Kept loop
         Check (Valid (Buffer, Slices (K)));
         Check (Corpus.Holds (Buffer, Slices (K), Piece (Kinds (K))));
      end loop;
      declare
         C : Candidate_Array (1 .. Kept);
         R : Search_Result_Array (1 .. Kept);
         N : Natural;
      begin
         for K in 1 .. Kept loop
            C (K) := (Text => Slices (K));
         end loop;
         Check (Valid (Buffer, C));
         Check (Valid (Buffer (1 .. Used), C));
         for K in 1 .. Kept loop
            Search (Piece (Kinds (K)), Buffer, C, R, N);
            --  Candidate K holds exactly this pattern, so it must be found.
            Check (N >= 1);
            for J in 1 .. N loop
               Check (Exists (Piece (Kinds (K)),
                              Text_Of (Buffer, C (R (J).Candidate).Text)));
            end loop;
            --  Trimming the corpus to the fill level cannot change the answer.
            declare
               Trimmed : Search_Result_Array (1 .. Kept);
               M : Natural;
            begin
               Search (Piece (Kinds (K)), Buffer (1 .. Used), C, Trimmed, M);
               Check (M = N and then Trimmed (1 .. M) = R (1 .. N));
            end;
         end loop;
      end;
   end Check_Build;

begin
   Pair ("", "");
   Pair ("aa", "a");
   Pair ("fa", "src/fuzzy_algorithm.adb");
   Pair ("fA", "src/fooAccess.adb");
   Pair ("fa", "src\file-access.adb");
   Pair ("a", "A");
   for T_Size in 0 .. 4 loop
      for T_Code in 0 .. 4 ** T_Size - 1 loop
         for P_Size in 0 .. 3 loop
            for P_Code in 0 .. 4 ** P_Size - 1 loop
               Pair (Word (P_Code, P_Size), Word (T_Code, T_Size));
            end loop;
         end loop;
      end loop;
   end loop;
   for Size in 0 .. 3 loop
      for Code in 0 .. 4 ** Size - 1 loop
         for Capacity in 0 .. 10 loop
            Search_Case (Word (Code, Size), Capacity);
         end loop;
      end loop;
   end loop;
   declare
      Data : constant String (Integer'Last .. Integer'Last) := "a";
      P : constant String (Integer'Last .. Integer'Last) := "a";
      C : constant Candidate_Array (Integer'Last .. Integer'Last) :=
        [others => (Text => (Integer'Last, 1))];
      R : Search_Result_Array (Integer'Last .. Integer'Last);
      Positions : Match_Position_Array (Integer'Last .. Integer'Last);
      N : Natural;
      M : Boolean;
      V : Score_Type;
   begin
      Search (P, Data, C, R, N);
      Check (N = 1 and then R (R'First).Candidate = Integer'Last);
      Match_Details (P, Data, C (C'First).Text, M, V, Positions, N);
      Check (M and N = 1 and Positions (Positions'First) = 1);
      Check (not Valid (Data, Text_Slice'(Integer'Last, 2)));
      Check (Valid (Data, Text_Slice'(1, 0)));
   end;
   declare
      C : Candidate_Array (8 .. 7);
      R : Search_Result_Array (3 .. 6);
      N : Natural;
   begin
      Search ("", "", C, R, N);
      Check (N = 0);
   end;
   declare
      Data : constant String := "abbbbbbbbbbb_a";
      C : constant Candidate_Array (7 .. 8) :=
        [(Text => (1, 12)), (Text => (13, 2))];
      R : Search_Result_Array (1 .. 2);
      N : Natural;
   begin
      Search ("a", Data, C, R, N);
      Check (N = 2 and then R (1).Score = R (2).Score);
      Check (R (1).Candidate = 8 and R (2).Candidate = 7);
   end;
   --  Corpus packing.
   declare
      Kinds : constant String := "0123";
   begin
      for Capacity in 0 .. 8 loop
         Check_Build (Capacity, "");
         for A in Kinds'Range loop
            Check_Build (Capacity, [Kinds (A)]);
            for B in Kinds'Range loop
               Check_Build (Capacity, [Kinds (A), Kinds (B)]);
               for C in Kinds'Range loop
                  Check_Build (Capacity, [Kinds (A), Kinds (B), Kinds (C)]);
               end loop;
            end loop;
         end loop;
      end loop;
   end;
   declare
      --  Buffer bounds other than one, and a buffer with a null range.
      Buffer : String (5 .. 12) := [others => '#'];
      Empty : String (9 .. 8);
      Used : Natural := 0;
      Slice : Text_Slice;
      Ok : Boolean;
   begin
      Corpus.Append (Buffer, Used, "abc", Slice, Ok);
      Check (Ok and Used = 3 and Slice = Text_Slice'(5, 3));
      Corpus.Append (Buffer, Used, "de", Slice, Ok);
      Check (Ok and Used = 5 and Slice = Text_Slice'(8, 2));
      Check (Buffer = "abcde###");
      Corpus.Append (Buffer, Used, "ffff", Slice, Ok);
      Check (not Ok and Used = 5 and Buffer = "abcde###");
      Corpus.Append (Buffer, Used, "fff", Slice, Ok);
      Check (Ok and Used = 8 and Buffer = "abcdefff");
      Corpus.Append (Buffer, Used, "", Slice, Ok);
      --  A full buffer still accepts an empty item; its First is not a
      --  buffer position, so it stays representable.
      Check (Ok and Used = 8 and Slice = Text_Slice'(1, 0));
      Corpus.Append (Buffer, Used, "g", Slice, Ok);
      Check (not Ok);
      Used := 0;
      Corpus.Append (Empty, Used, "", Slice, Ok);
      Check (Ok and Used = 0 and Slice.Length = 0);
      Check (Corpus.Room (Empty, Used) = 0);
      Corpus.Append (Empty, Used, "a", Slice, Ok);
      Check (not Ok and Used = 0);
   end;
   Ada.Text_IO.Put_Line ("PASS:" & Checks'Image & " checks");
end Test_Fuzzy;
