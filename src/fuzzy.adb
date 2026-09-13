package body Fuzzy
  with SPARK_Mode
is
   function Next_Position
     (Data : String; Text : Text_Slice; After : Natural; Ch : Character)
      return Natural
   is
      J : Natural := After;
   begin
      while J < Text.Length loop
         pragma Loop_Variant (Increases => J);
         pragma Loop_Invariant (J in After .. Text.Length);
         pragma
           Loop_Invariant
             (for all K in 1 .. J =>
                (if K > After then Character_At (Data, Text, K) /= Ch));
         J := J + 1;
         if Character_At (Data, Text, J) = Ch then
            return J;
         end if;
      end loop;
      return 0;
   end Next_Position;

   function Match_End
     (Pattern : String; Data : String; Text : Text_Slice; Count : Natural)
      return Natural
   is
      Previous : Natural;
   begin
      if Count = 0 then
         return 0;
      end if;
      Previous := Match_End (Pattern, Data, Text, Count - 1);
      if Count > 1 and then Previous = 0 then
         return 0;
      end if;
      return
        Next_Position
          (Data, Text, Previous, Pattern (Pattern'First + (Count - 1)));
   end Match_End;

   procedure Witness_Implies_Match
     (Pattern   : String;
      Data      : String;
      Text      : Text_Slice;
      Positions : Match_Position_Array)
   is
      Previous : Natural := 0;
      Offset   : Natural;
   begin
      for I in 1 .. Pattern'Length loop
         pragma Loop_Invariant (Previous <= Text.Length);
         pragma
           Loop_Invariant (Previous = Match_End (Pattern, Data, Text, I - 1));
         pragma
           Loop_Invariant
             (if I > 1
                then
                  Previous > 0
                  and then Previous <= Positions (Positions'First + (I - 2)));
         Offset :=
           Next_Position
             (Data, Text, Previous, Pattern (Pattern'First + (I - 1)));
         pragma
           Assert
             (Character_At (Data, Text, Positions (Positions'First + (I - 1)))
                = Pattern (Pattern'First + (I - 1)));
         pragma
           Assert
             (Offset > 0
                and then Offset <= Positions (Positions'First + (I - 1)));
         Previous := Offset;
      end loop;
   end Witness_Implies_Match;

   procedure Failed_Prefix
     (Pattern : String; Data : String; Text : Text_Slice; Count : Positive)
   with
     Ghost,
     Global => null,
     Pre    =>
       Valid (Data, Text)
       and then Count <= Pattern'Length
       and then Match_End (Pattern, Data, Text, Count) = 0,
     Post   => not Is_Subsequence (Pattern, Data, Text)
   is
   begin
      for K in Count .. Pattern'Length loop
         pragma Loop_Invariant (Match_End (Pattern, Data, Text, K) = 0);
      end loop;
   end Failed_Prefix;

   procedure Successful_Prefix
     (Pattern : String; Data : String; Text : Text_Slice; Count : Positive)
   with
     Ghost,
     Global => null,
     Pre    =>
       Valid (Data, Text)
       and then Count <= Pattern'Length
       and then Is_Subsequence (Pattern, Data, Text),
     Post   => Match_End (Pattern, Data, Text, Count) > 0
   is
   begin
      for K in reverse Count .. Pattern'Length loop
         pragma Loop_Invariant (Match_End (Pattern, Data, Text, K) > 0);
      end loop;
   end Successful_Prefix;

   function Separator (C : Character) return Boolean
   is (C = '/' or else C = '\');

   function Word_Start (Previous, Current : Character) return Boolean
   is (Previous = '_'
       or else Previous = '-'
       or else Previous = '.'
       or else Previous = ' '
       or else (Previous in 'a' .. 'z' and then Current in 'A' .. 'Z'));

   type Evaluation is record
      Matched : Boolean;
      Value   : Score_Type;
   end record;

   function Evaluate
     (Pattern : String; Data : String; Text : Text_Slice) return Evaluation
   with
     Global => null,
     Pre    => Valid (Data, Text),
     Post   =>
       Evaluate'Result.Matched = Is_Subsequence (Pattern, Data, Text)
       and then (if not Evaluate'Result.Matched then Evaluate'Result.Value = 0)
   is
      Previous       : Natural := 0;
      Last_Separator : Natural := 0;
      Offset         : Natural;
      Total          : Long_Long_Integer := -Long_Long_Integer (Text.Length);
      Bonus          : Long_Long_Integer;
   begin
      if Pattern'Length = 0 then
         return (True, Score_Type (Total));
      elsif Pattern'Length > Text.Length then
         return (False, 0);
      end if;
      for J in 1 .. Text.Length loop
         pragma Loop_Invariant (Last_Separator <= Text.Length);
         if Separator (Character_At (Data, Text, J)) then
            Last_Separator := J;
         end if;
      end loop;
      for I in 1 .. Pattern'Length loop
         pragma Loop_Invariant (Previous <= Text.Length);
         pragma Loop_Invariant (if I > 1 then Previous > 0);
         pragma
           Loop_Invariant (Previous = Match_End (Pattern, Data, Text, I - 1));
         pragma
           Loop_Invariant
             (Total
                >= -Long_Long_Integer (Text.Length)
                   - 2 * Long_Long_Integer (Previous));
         pragma Loop_Invariant (Total <= 60 * Long_Long_Integer (I - 1));
         Offset :=
           Next_Position
             (Data, Text, Previous, Pattern (Pattern'First + (I - 1)));
         pragma Assert (Offset = Match_End (Pattern, Data, Text, I));
         if Offset = 0 then
            --  Once a prefix fails, every longer prefix fails too.
            Failed_Prefix (Pattern, Data, Text, I);
            return (False, 0);
         end if;
         Bonus := 16;
         if Previous > 0 and then Offset - Previous = 1 then
            Bonus := Bonus + 12;
         end if;
         if Offset = 1
           or else Separator (Character_At (Data, Text, Offset - 1))
         then
            Bonus := Bonus + 16;
         end if;
         if Offset > 1
           and then Word_Start
                      (Character_At (Data, Text, Offset - 1),
                       Character_At (Data, Text, Offset))
         then
            Bonus := Bonus + 8;
         end if;
         if Offset > Last_Separator then
            Bonus := Bonus + 8;
         end if;
         Total :=
           Total - 2 * Long_Long_Integer (Offset - Previous - 1) + Bonus;
         Previous := Offset;
      end loop;
      return (True, Score_Type (Total));
   end Evaluate;

   function Score_Of
     (Pattern : String; Data : String; Text : Text_Slice) return Score_Type
   is (Evaluate (Pattern, Data, Text).Value);

   procedure Score
     (Pattern   : String;
      Data      : String;
      Candidate : Text_Slice;
      Matched   : out Boolean;
      Value     : out Score_Type)
   is
      E : constant Evaluation := Evaluate (Pattern, Data, Candidate);
   begin
      Matched := E.Matched;
      Value := E.Value;
   end Score;

   procedure Match_Details
     (Pattern        : String;
      Data           : String;
      Candidate      : Text_Slice;
      Matched        : out Boolean;
      Value          : out Score_Type;
      Positions      : out Match_Position_Array;
      Position_Count : out Natural)
   is
      Previous : Natural := 0;
      Offset   : Natural;
   begin
      Positions := [others => 1];
      Position_Count := 0;
      Score (Pattern, Data, Candidate, Matched, Value);
      if not Matched then
         return;
      end if;
      for I in 1 .. Pattern'Length loop
         pragma Loop_Invariant (Previous <= Candidate.Length);
         pragma
           Loop_Invariant
             (Previous = Match_End (Pattern, Data, Candidate, I - 1));
         pragma
           Loop_Invariant
             (for all P in Positions'Range =>
                (if P - Positions'First < I - 1
                 then
                   Positions (P)
                   = Match_End
                       (Pattern, Data, Candidate, P - Positions'First + 1)
                   and then Positions (P) <= Candidate.Length
                   and then Character_At (Data, Candidate, Positions (P))
                            = Pattern (Pattern'First + (P - Positions'First))
                   and then (if P > Positions'First
                             then Positions (P - 1) < Positions (P))));
         --  Propagate successful matching back to this prefix.
         Successful_Prefix (Pattern, Data, Candidate, I);
         Offset :=
           Next_Position
             (Data, Candidate, Previous, Pattern (Pattern'First + (I - 1)));
         pragma Assert (Offset = Match_End (Pattern, Data, Candidate, I));
         Positions (Positions'First + (I - 1)) := Offset;
         Previous := Offset;
      end loop;
      Position_Count := Pattern'Length;
   end Match_Details;

   --  The executable insertion step exposes its exact position mapping.
   procedure Insert_At
     (Results : in out Search_Result_Array;
      Count   : in out Natural;
      Item    : Search_Result;
      Slot    : Natural)
   with
     Global => null,
     Always_Terminates,
     Pre    =>
       Count <= Results'Length
       and then Slot <= Count
       and then Slot < Results'Length,
     Post   =>
       Count
       = (if Count'Old < Results'Length then Count'Old + 1 else Count'Old)
       and then (for all R in Results'Range =>
                   (if R - Results'First < Slot
                    then Results (R) = Results'Old (R)
                    elsif R - Results'First = Slot
                    then Results (R) = Item
                    elsif R - Results'First < Count
                    then Results (R) = Results'Old (R - 1)
                    else Results (R) = Results'Old (R)))
   is
      Before : constant Search_Result_Array := Results
      with Ghost;
   begin
      if Count < Results'Length then
         Count := Count + 1;
      end if;
      for J in reverse Slot + 1 .. Count - 1 loop
         pragma
           Loop_Invariant
             (for all R in Results'Range =>
                (if R - Results'First <= J or else R - Results'First >= Count
                 then Results (R) = Before (R)
                 else Results (R) = Before (R - 1)));
         Results (Results'First + J) := Results (Results'First + (J - 1));
      end loop;
      Results (Results'First + Slot) := Item;
   end Insert_At;

   --  Introduce a known position as a witness for prefix membership.
   procedure Member_At
     (Results : Search_Result_Array; Count : Natural; Position : Positive)
   with
     Ghost,
     Global => null,
     Always_Terminates,
     Pre    =>
       Count <= Results'Length
       and then Position in Results'Range
       and then Position - Results'First < Count,
     Post   => Contains (Results, Count, Results (Position).Candidate)
   is
   begin
      null;
   end Member_At;

   --  Give the existential membership model an explicit position witness
   --  for each result preserved by insertion.
   procedure Retained_Members
     (Before, After : Search_Result_Array; Count : Positive; Slot : Natural)
   with
     Ghost,
     Global => null,
     Always_Terminates,
     Pre    =>
       Before'First = After'First
       and then Before'Last = After'Last
       and then Count <= After'Length
       and then Slot < Count
       and then (for all R in Before'Range =>
                   (if R - Before'First < Count - 1
                    then
                      After (if R - Before'First < Slot then R else R + 1)
                      = Before (R))),
     Post   =>
       (for all R in Before'Range =>
          (if R - Before'First < Count - 1
           then Contains (After, Count, Before (R).Candidate)))
   is
   begin
      for R in Before'Range loop
         if R - Before'First < Count - 1 then
            declare
               S : constant Positive :=
                 (if R - Before'First < Slot then R else R + 1);
            begin
               pragma Assert (After (S) = Before (R));
               Member_At (After, Count, S);
            end;
         end if;
         pragma
           Loop_Invariant
             (for all Q in Before'First .. R =>
                (if Q - Before'First < Count - 1
                 then Contains (After, Count, Before (Q).Candidate)));
      end loop;
   end Retained_Members;

   --  Recover the position witness when reasoning about an evicted member.
   function Member_Position
     (Results   : Search_Result_Array;
      Count     : Natural;
      Candidate : Candidate_Index) return Positive
   with
     Ghost,
     Global => null,
     Pre    =>
       Count <= Results'Length and then Contains (Results, Count, Candidate),
     Post   =>
       Member_Position'Result in Results'Range
       and then Member_Position'Result - Results'First < Count
       and then Results (Member_Position'Result).Candidate = Candidate
   is
   begin
      for R in Results'Range loop
         if R - Results'First < Count
           and then Results (R).Candidate = Candidate
         then
            return R;
         end if;
         pragma
           Loop_Invariant
             (for all Q in Results'First .. R =>
                (if Q - Results'First < Count
                 then Results (Q).Candidate /= Candidate));
      end loop;
      return Results'First;
   end Member_Position;

   procedure Better_Transitive
     (Left, Middle, Right : Search_Result; Candidates : Candidate_Array)
   with
     Ghost,
     Global => null,
     Always_Terminates,
     Pre    =>
       Left.Candidate in Candidates'Range
       and then Middle.Candidate in Candidates'Range
       and then Right.Candidate in Candidates'Range
       and then Better (Left, Middle, Candidates)
       and then Better (Middle, Right, Candidates),
     Post   => Better (Left, Right, Candidates)
   is
   begin
      null;
   end Better_Transitive;

   --  An omitted match was either the evicted last result or was already
   --  below the old cutoff. In the latter case use transitivity explicitly.
   procedure Preserve_Cutoff
     (Pattern, Data : String;
      Candidates    : Candidate_Array;
      C             : Candidate_Index;
      Before        : Search_Result_Array;
      Old_Count     : Natural;
      After         : Search_Result_Array;
      Count         : Positive)
   with
     Ghost,
     Global => null,
     Always_Terminates,
     Pre    =>
       Valid (Data, Candidates)
       and then C in Candidates'Range
       and then Before'First = After'First
       and then Before'Last = After'Last
       and then Old_Count <= Before'Length
       and then Count <= After'Length
       and then Count
                = (if Old_Count < Before'Length
                   then Old_Count + 1
                   else Old_Count)
       and then Contains (After, Count, C)
       and then (for all R in Before'Range =>
                   (if R - Before'First < Old_Count
                    then
                      Before (R).Candidate in Candidates'First .. C - 1
                      and then Before (R).Score
                               = Score_Of
                                   (Pattern,
                                    Data,
                                    Candidates (Before (R).Candidate).Text)))
       and then (if Count = After'Length
                 then After (After'Last).Candidate in Candidates'Range)
       and then (for all R in Before'Range =>
                   (if R - Before'First < Count - 1
                    then Contains (After, Count, Before (R).Candidate)))
       and then (if Old_Count = Before'Length
                 then
                   Better
                     (After (After'Last), Before (Before'Last), Candidates))
       and then (for all D in Candidates'First .. C - 1 =>
                   (if Is_Subsequence (Pattern, Data, Candidates (D).Text)
                      and then not Contains (Before, Old_Count, D)
                    then
                      Old_Count = Before'Length
                      and then Better
                                 (Before (Before'Last),
                                  (D,
                                   Score_Of
                                     (Pattern, Data, Candidates (D).Text)),
                                  Candidates))),
     Post   =>
       (for all D in Candidates'First .. C =>
          (if Is_Subsequence (Pattern, Data, Candidates (D).Text)
             and then not Contains (After, Count, D)
             and then Count = After'Length
           then
             Better
               (After (After'Last),
                (D, Score_Of (Pattern, Data, Candidates (D).Text)),
                Candidates)))
   is
   begin
      for D in Candidates'First .. C loop
         if Is_Subsequence (Pattern, Data, Candidates (D).Text)
           and then not Contains (After, Count, D)
           and then Count = After'Length
         then
            pragma Assert (D < C);
            if Contains (Before, Old_Count, D) then
               declare
                  R : constant Positive :=
                    Member_Position (Before, Old_Count, D);
               begin
                  pragma Assert (R - Before'First >= Count - 1);
                  pragma Assert (Old_Count = Before'Length);
                  pragma Assert (R = Before'Last);
               end;
            else
               Better_Transitive
                 (After (After'Last),
                  Before (Before'Last),
                  (D, Score_Of (Pattern, Data, Candidates (D).Text)),
                  Candidates);
            end if;
         end if;
         pragma
           Loop_Invariant
             (for all E in Candidates'First .. D =>
                (if Is_Subsequence (Pattern, Data, Candidates (E).Text)
                   and then not Contains (After, Count, E)
                   and then Count = After'Length
                 then
                   Better
                     (After (After'Last),
                      (E, Score_Of (Pattern, Data, Candidates (E).Text)),
                      Candidates)));
      end loop;
   end Preserve_Cutoff;

   procedure Search
     (Pattern      : String;
      Data         : String;
      Candidates   : Candidate_Array;
      Results      : out Search_Result_Array;
      Result_Count : out Natural)
   is
      Matched : Boolean;
      Value   : Score_Type;
      Item    : Search_Result;
      Slot    : Natural;
      Before  : Search_Result_Array (Results'Range)
      with Ghost;
   begin
      Results := [others => (Candidate => 1, Score => 0)];
      Result_Count := 0;
      if Results'Length = 0 then
         return;
      end if;
      for C in Candidates'Range loop
         Score (Pattern, Data, Candidates (C).Text, Matched, Value);
         if Matched then
            Item := (C, Value);
            Slot := Result_Count;
            while Slot > 0 loop
               pragma Loop_Variant (Decreases => Slot);
               pragma Loop_Invariant (Slot <= Result_Count);
               pragma
                 Loop_Invariant
                   (for all R in Results'Range =>
                      (if R - Results'First >= Slot
                         and then R - Results'First < Result_Count
                       then Better (Item, Results (R), Candidates)));
               exit when
                 not Better
                       (Item,
                        Results (Results'First + (Slot - 1)),
                        Candidates);
               Slot := Slot - 1;
            end loop;
            if Slot < Results'Length then
               declare
                  Old_Count : constant Natural := Result_Count
                  with Ghost;
               begin
                  Before := Results;
                  if Slot > 0 then
                     pragma
                       Assert
                         (Better
                            (Results (Results'First + (Slot - 1)),
                             Item,
                             Candidates));
                  end if;
                  pragma
                    Assert
                      (if Old_Count = Results'Length
                         then
                           Better (Item, Before (Before'Last), Candidates)
                           and then (if Slot < Results'Length - 1
                                     then
                                       Better
                                         (Before (Before'Last - 1),
                                          Before (Before'Last),
                                          Candidates)));
                  Insert_At (Results, Result_Count, Item, Slot);
                  Member_At (Results, Result_Count, Results'First + Slot);
                  Retained_Members (Before, Results, Result_Count, Slot);
                  pragma
                    Assert
                      (if Old_Count = Results'Length
                         then
                           Better
                             (Results (Results'Last),
                              Before (Before'Last),
                              Candidates));
                  Preserve_Cutoff
                    (Pattern,
                     Data,
                     Candidates,
                     C,
                     Before,
                     Old_Count,
                     Results,
                     Result_Count);
               end;
            end if;
         end if;
         pragma Loop_Invariant (Result_Count <= Results'Length);
         pragma Loop_Invariant (Result_Count <= C - Candidates'First + 1);
         pragma
           Loop_Invariant
             (for all R in Results'Range =>
                (if R - Results'First < Result_Count
                 then
                   Results (R).Candidate in Candidates'First .. C
                   and then Is_Subsequence
                              (Pattern,
                               Data,
                               Candidates (Results (R).Candidate).Text)
                   and then Results (R).Score
                            = Score_Of
                                (Pattern,
                                 Data,
                                 Candidates (Results (R).Candidate).Text)));
         pragma
           Loop_Invariant
             (for all R in Results'Range =>
                (for all S in Results'Range =>
                   (if R - Results'First < Result_Count
                      and then S - Results'First < Result_Count
                      and then R < S
                    then Better (Results (R), Results (S), Candidates))));
         --  An omitted match requires a full buffer. Its last result is
         --  the cutoff; pairwise ordering lifts this bound to every result.
         pragma
           Loop_Invariant
             (for all D in Candidates'First .. C =>
                (if Is_Subsequence (Pattern, Data, Candidates (D).Text)
                   and then not Contains (Results, Result_Count, D)
                 then Result_Count = Results'Length));
         pragma
           Loop_Invariant
             (for all D in Candidates'First .. C =>
                (if Is_Subsequence (Pattern, Data, Candidates (D).Text)
                   and then not Contains (Results, Result_Count, D)
                   and then Result_Count = Results'Length
                 then
                   Better
                     (Results (Results'Last),
                      (D, Score_Of (Pattern, Data, Candidates (D).Text)),
                      Candidates)));
      end loop;
   end Search;
end Fuzzy;
