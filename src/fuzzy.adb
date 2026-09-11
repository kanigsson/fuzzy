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
   begin
      Results := [others => (Candidate => 1, Score => 0)];
      Result_Count := 0;
      if Results'Length = 0 then
         return;
      end if;
      for C in Candidates'Range loop
         pragma Loop_Invariant (Result_Count <= Results'Length);
         pragma Loop_Invariant (Result_Count <= C - Candidates'First);
         pragma
           Loop_Invariant
             (for all R in Results'Range =>
                (if R - Results'First < Result_Count
                 then
                   Results (R).Candidate in Candidates'First .. C - 1
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
                (if R - Results'First < Result_Count and then R > Results'First
                 then Better (Results (R - 1), Results (R), Candidates)));
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
                  Before : constant Search_Result_Array := Results
                  with Ghost;
               begin
                  if Slot > 0 then
                     pragma
                       Assert
                         (Better
                            (Results (Results'First + (Slot - 1)),
                             Item,
                             Candidates));
                  end if;
                  if Result_Count < Results'Length then
                     Result_Count := Result_Count + 1;
                  end if;
                  for J in reverse Slot + 1 .. Result_Count - 1 loop
                     pragma
                       Loop_Invariant
                         (for all R in Results'Range =>
                            (if R - Results'First <= J
                             then Results (R) = Before (R)
                             elsif R - Results'First < Result_Count
                             then Results (R) = Before (R - 1)));
                     Results (Results'First + J) :=
                       Results (Results'First + (J - 1));
                  end loop;
                  Results (Results'First + Slot) := Item;
               end;
            end if;
         end if;
      end loop;
   end Search;
end Fuzzy;
