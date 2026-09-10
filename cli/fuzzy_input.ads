with Fuzzy;

--  Standard input adapter for the CLI, outside the proof boundary. The
--  library never allocates; corpus storage lives here because standard input
--  has no size known in advance.
package Fuzzy_Input is

   type Text_Buffer is access String;
   type Candidate_Buffer is access Fuzzy.Candidate_Array;

   --  A packed corpus and the candidates pointing into it. Buffers start at
   --  index one and grow by doubling; slices are absolute indexes, so they
   --  survive a growth step that preserves the lower bound and filled prefix.
   type Corpus is limited record
      Text  : Text_Buffer;
      Used  : Natural := 0;
      Items : Candidate_Buffer;
      Count : Natural := 0;
   end record;

   --  Read every delimiter-framed record from standard input. A record may
   --  hold any byte other than the delimiter in force. Input need not end
   --  with a delimiter, and a delimiter at the very end does not add an empty
   --  record. Ok is False only when the input outgrows the representable
   --  buffer size.
   procedure Read_Standard_Input
     (Self : in out Corpus; Delimiter : Character; Ok : out Boolean);

end Fuzzy_Input;
