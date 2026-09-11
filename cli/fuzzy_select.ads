with Fuzzy_Input;

--  The interactive picker, outside the proof boundary.

package Fuzzy_Select is

   type Mark_Array is array (Positive range <>) of Boolean;

   --  Filter Corpus interactively, starting from Initial_Query. Chosen is the
   --  index of the candidate under the cursor when it was accepted, or zero.
   --
   --  With Multi, Tab and Shift-Tab mark candidates, and Marks reports every
   --  marked one; a caller offering that should prefer the marks over Chosen
   --  whenever any is set. Marks is indexed like the corpus candidates and is
   --  set even without Multi, in which case none is ever marked.
   procedure Run
     (Corpus        : Fuzzy_Input.Corpus;
      Initial_Query : String;
      Multi         : Boolean;
      Chosen        : out Natural;
      Marks         : out Mark_Array;
      Status        : out Natural)
   with Pre => Marks'Length = Corpus.Count;

end Fuzzy_Select;
