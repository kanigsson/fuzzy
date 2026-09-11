--  Raw-mode access to the controlling terminal, outside the proof boundary.
--
--  Standard input carries the candidate stream, so keys are read from the
--  terminal device itself and the display is written there too. Standard
--  output stays free to carry the result, which may well be a pipe.

package Fuzzy_Term is

   --  Enter raw mode and the alternate screen. Ok is False when there is no
   --  controlling terminal or its mode cannot be changed; nothing is left
   --  half-configured in that case.
   procedure Open (Ok : out Boolean);

   --  Restore the saved mode and leave the alternate screen. Idempotent, and
   --  safe to call when Open failed.
   procedure Close;

   function Standard_Input_Is_Terminal return Boolean;

   type Key_Kind is
     (Char,
      Enter,
      Accept_Abort,
      Backspace,
      Delete_Forward,
      Delete_Word,
      Clear_Line,
      Up,
      Down,
      Left,
      Right,
      Line_Start,
      Line_End,
      Mark_Down,
      Mark_Up,
      Ignored);

   type Key is record
      Kind : Key_Kind := Ignored;
      Ch   : Character := ' ';
   end record;
   type Key_Array is array (Positive range <>) of Key;

   --  Block until at least one byte arrives, then decode everything that came
   --  with it. A terminal writes an escape sequence in one go, so reading a
   --  block at a time is what keeps arrow keys from being seen as a bare
   --  escape followed by letters. Count is zero when the terminal closed.
   procedure Read_Keys (Keys : out Key_Array; Count : out Natural);

   --  Current size, or a conservative default when it cannot be determined.
   --  Queried on each redraw, which is what makes a resize take effect
   --  without a signal handler.
   procedure Size (Rows, Cols : out Positive);

   procedure Write (Item : String);

end Fuzzy_Term;
