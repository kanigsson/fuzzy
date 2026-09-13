package Fuzzy
  with SPARK_Mode, Pure
is
   subtype Candidate_Index is Positive;

   type Text_Slice is record
      First  : Positive;
      Length : Natural;
   end record;
   type Candidate is record
      Text : Text_Slice;
   end record;
   type Candidate_Array is array (Candidate_Index range <>) of Candidate;

   --  At most 60 points per matched character, at least -3 per text
   --  character. These bounds cover every representable String length.
   type Score_Type is
     range -3 * Long_Long_Integer (Integer'Last)
           .. 60 * Long_Long_Integer (Integer'Last);

   type Search_Result is record
      Candidate : Candidate_Index;
      Score     : Score_Type;
   end record;
   type Search_Result_Array is array (Positive range <>) of Search_Result;
   --  Positions are ONE-BASED OFFSETS within the candidate, not Data indexes.
   type Match_Position_Array is array (Positive range <>) of Positive;

   function Valid (Data : String; Text : Text_Slice) return Boolean
   is (Text.Length = 0
       or else (Text.First in Data'Range
                and then Text.Length - 1 <= Data'Last - Text.First));
   --  An empty slice is valid regardless of First; it is never dereferenced.

   function Valid (Data : String; Candidates : Candidate_Array) return Boolean
   is (for all C of Candidates => Valid (Data, C.Text));

   function Character_At
     (Data : String; Text : Text_Slice; Offset : Positive) return Character
   is (Data (Text.First + (Offset - 1)))
   with Pre => Valid (Data, Text) and then Offset <= Text.Length;

   --  Earliest occurrence strictly after an offset, or zero if absent.
   function Next_Position
     (Data : String; Text : Text_Slice; After : Natural; Ch : Character)
      return Natural
   with
     Global => null,
     Pre    => Valid (Data, Text) and then After <= Text.Length,
     Post   =>
       Next_Position'Result <= Text.Length
       and then (if Next_Position'Result > 0
                 then
                   Next_Position'Result > After
                   and then Character_At (Data, Text, Next_Position'Result)
                            = Ch)
       and then (for all J in 1 .. Text.Length =>
                   (if J > After
                      and then (Next_Position'Result = 0
                                or else J < Next_Position'Result)
                    then Character_At (Data, Text, J) /= Ch));

   --  A mathematical witness: the earliest possible ending offset of the
   --  first Count pattern characters; zero means that prefix cannot match.
   --  Count = 0 also returns zero (the empty prefix).
   function Match_End
     (Pattern : String; Data : String; Text : Text_Slice; Count : Natural)
      return Natural
   with
     Ghost,
     Global             => null,
     Pre                => Valid (Data, Text) and then Count <= Pattern'Length,
     Post               =>
       Match_End'Result <= Text.Length
       and then (if Count = 0
                 then Match_End'Result = 0
                 else
                   Match_End'Result
                   = (if Count > 1
                        and then Match_End (Pattern, Data, Text, Count - 1) = 0
                      then 0
                      else
                        Next_Position
                          (Data,
                           Text,
                           Match_End (Pattern, Data, Text, Count - 1),
                           Pattern (Pattern'First + (Count - 1)))))
       and then (if Count > 0 and then Match_End'Result > 0
                 then
                   Match_End'Result >= Count
                   and then Character_At (Data, Text, Match_End'Result)
                            = Pattern (Pattern'First + (Count - 1))
                   and then (if Count > 1
                             then
                               Match_End (Pattern, Data, Text, Count - 1) > 0
                               and then Match_End
                                          (Pattern, Data, Text, Count - 1)
                                        < Match_End'Result)),
     Subprogram_Variant => (Decreases => Count);

   function Is_Subsequence
     (Pattern : String; Data : String; Text : Text_Slice) return Boolean
   is (Pattern'Length = 0
       or else Match_End (Pattern, Data, Text, Pattern'Length) > 0)
   with Ghost, Pre => Valid (Data, Text);

   function Is_Witness
     (Pattern   : String;
      Data      : String;
      Text      : Text_Slice;
      Positions : Match_Position_Array) return Boolean
   is (Positions'Length >= Pattern'Length
       and then (for all P in Positions'Range =>
                   (if P - Positions'First < Pattern'Length
                    then
                      Positions (P) <= Text.Length
                      and then Character_At (Data, Text, Positions (P))
                               = Pattern
                                   (Pattern'First + (P - Positions'First))
                      and then (if P > Positions'First
                                then Positions (P - 1) < Positions (P)))))
   with Ghost, Pre => Valid (Data, Text);

   --  Completeness theorem: ANY ordered occurrence witness implies a match,
   --  so a negative answer also rules out non-greedy alignments.
   procedure Witness_Implies_Match
     (Pattern   : String;
      Data      : String;
      Text      : Text_Slice;
      Positions : Match_Position_Array)
   with
     Ghost,
     Global => null,
     Always_Terminates,
     Pre    =>
       Valid (Data, Text) and then Is_Witness (Pattern, Data, Text, Positions),
     Post   => Is_Subsequence (Pattern, Data, Text);

   --  Ghost value model shared by Score, Search, and Match_Details.
   function Score_Of
     (Pattern : String; Data : String; Text : Text_Slice) return Score_Type
   with Ghost, Global => null, Pre => Valid (Data, Text);

   procedure Score
     (Pattern   : String;
      Data      : String;
      Candidate : Text_Slice;
      Matched   : out Boolean;
      Value     : out Score_Type)
   with
     Global => null,
     Always_Terminates,
     Pre    => Valid (Data, Candidate),
     Post   =>
       Matched = Is_Subsequence (Pattern, Data, Candidate)
       and then Value = Score_Of (Pattern, Data, Candidate)
       and then (if not Matched then Value = 0);

   function Better
     (Left, Right : Search_Result; Candidates : Candidate_Array) return Boolean
   is (Left.Score > Right.Score
       or else (Left.Score = Right.Score
                and then (Candidates (Left.Candidate).Text.Length
                          < Candidates (Right.Candidate).Text.Length
                          or else (Candidates (Left.Candidate).Text.Length
                                   = Candidates (Right.Candidate).Text.Length
                                   and then Left.Candidate
                                            < Right.Candidate))))
   with
     Pre =>
       Left.Candidate in Candidates'Range
       and then Right.Candidate in Candidates'Range;

   --  Membership only in the meaningful output prefix.
   function Contains
     (Results   : Search_Result_Array;
      Count     : Natural;
      Candidate : Candidate_Index) return Boolean
   is (for some R in Results'Range =>
         R - Results'First < Count and then Results (R).Candidate = Candidate)
   with Ghost, Pre => Count <= Results'Length;

   procedure Search
     (Pattern      : String;
      Data         : String;
      Candidates   : Candidate_Array;
      Results      : out Search_Result_Array;
      Result_Count : out Natural)
   with
     Global => null,
     Always_Terminates,
     Pre    => Valid (Data, Candidates),
     Post   =>
       Result_Count <= Results'Length
       and then Result_Count <= Candidates'Length
       and then (for all R in Results'Range =>
                   (if R - Results'First < Result_Count
                    then
                      Results (R).Candidate in Candidates'Range
                      and then Is_Subsequence
                                 (Pattern,
                                  Data,
                                  Candidates (Results (R).Candidate).Text)
                      and then Results (R).Score
                               = Score_Of
                                   (Pattern,
                                    Data,
                                    Candidates (Results (R).Candidate).Text)))
       --  Strict pairwise ranking and score consistency exclude duplicates.
       and then (for all R in Results'Range =>
                   (for all S in Results'Range =>
                      (if R - Results'First < Result_Count
                         and then S - Results'First < Result_Count
                         and then R < S
                       then Better (Results (R), Results (S), Candidates))))
       --  Every omitted match is worse than every returned result, and
       --  omission is allowed only when the output buffer is full.
       --  Thus Count = min (capacity, number of matching candidates).
       and then (for all C in Candidates'Range =>
                   (if Is_Subsequence (Pattern, Data, Candidates (C).Text)
                      and then not Contains (Results, Result_Count, C)
                    then
                      Result_Count = Results'Length
                      and then (for all R in Results'Range =>
                                  Better
                                    (Results (R),
                                     (C,
                                      Score_Of
                                        (Pattern, Data, Candidates (C).Text)),
                                     Candidates))));

   procedure Match_Details
     (Pattern        : String;
      Data           : String;
      Candidate      : Text_Slice;
      Matched        : out Boolean;
      Value          : out Score_Type;
      Positions      : out Match_Position_Array;
      Position_Count : out Natural)
   with
     Global => null,
     Always_Terminates,
     Pre    =>
       Valid (Data, Candidate) and then Positions'Length >= Pattern'Length,
     Post   =>
       Matched = Is_Subsequence (Pattern, Data, Candidate)
       and then Value = Score_Of (Pattern, Data, Candidate)
       and then Position_Count = (if Matched then Pattern'Length else 0)
       and then (for all P in Positions'Range =>
                   (if P - Positions'First < Position_Count
                    then
                      Positions (P) <= Candidate.Length
                      and then Character_At (Data, Candidate, Positions (P))
                               = Pattern
                                   (Pattern'First + (P - Positions'First))
                      and then (if P > Positions'First
                                then Positions (P - 1) < Positions (P))));
end Fuzzy;
