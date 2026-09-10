with Fuzzy_Input;

--  The interactive picker, outside the proof boundary.
package Fuzzy_Select is

   --  Filter Corpus interactively, starting from Initial_Query. Chosen is the
   --  index of the accepted candidate, or zero. Status follows the convention
   --  the shell integration relies on: 0 accepted, 1 nothing matched, 2 no
   --  usable terminal, 130 aborted.
   procedure Run
     (Corpus        : Fuzzy_Input.Corpus;
      Initial_Query : String;
      Chosen        : out Natural;
      Status        : out Natural);

end Fuzzy_Select;
