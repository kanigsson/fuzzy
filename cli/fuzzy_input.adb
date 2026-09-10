with Ada.Streams;
with Ada.Text_IO.Text_Streams;
with Ada.Unchecked_Deallocation;
with Fuzzy.Corpus;

package body Fuzzy_Input is

   procedure Free is new Ada.Unchecked_Deallocation (String, Text_Buffer);
   procedure Free is
     new Ada.Unchecked_Deallocation (Fuzzy.Candidate_Array, Candidate_Buffer);

   --  Next capacity, or zero when the current one cannot be doubled within
   --  the representable index range.
   function Doubled (Length : Positive) return Natural is
     (if Length >= Natural'Last / 2 then
        (if Length = Natural'Last then 0 else Natural'Last)
      else Length * 2);

   procedure Read_Standard_Input
     (Self : in out Corpus; Delimiter : Character; Ok : out Boolean)
   is
      use type Ada.Streams.Stream_Element_Offset;

      --  Records are framed by a single delimiter byte and may contain any
      --  other byte, including a newline, so standard input is read as a byte
      --  stream rather than through the line-oriented input layer.
      Input : constant Ada.Text_IO.Text_Streams.Stream_Access :=
        Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Standard_Input);

      --  A record may span several reads of the input, so it is accumulated
      --  here instead of being a slice of the block just read.
      Pending : Text_Buffer := new String (1 .. 4 * 1024);
      Pending_Used : Natural := 0;

      procedure Grow_Text (Ok : out Boolean) is
         Wanted : constant Natural := Doubled (Self.Text'Length);
         Bigger : Text_Buffer;
      begin
         if Wanted = 0 then
            Ok := False;
            return;
         end if;
         Bigger := new String (1 .. Wanted);
         Bigger (1 .. Self.Used) := Self.Text (1 .. Self.Used);
         Free (Self.Text);
         Self.Text := Bigger;
         Ok := True;
      exception
         when Storage_Error =>
            Ok := False;
      end Grow_Text;

      procedure Grow_Items (Ok : out Boolean) is
         Wanted : constant Natural := Doubled (Self.Items'Length);
         Bigger : Candidate_Buffer;
      begin
         if Wanted = 0 then
            Ok := False;
            return;
         end if;
         Bigger := new Fuzzy.Candidate_Array (1 .. Wanted);
         Bigger (1 .. Self.Count) := Self.Items (1 .. Self.Count);
         Free (Self.Items);
         Self.Items := Bigger;
         Ok := True;
      exception
         when Storage_Error =>
            Ok := False;
      end Grow_Items;

      procedure Grow_Pending (Ok : out Boolean) is
         Wanted : constant Natural := Doubled (Pending'Length);
         Bigger : Text_Buffer;
      begin
         if Wanted = 0 then
            Ok := False;
            return;
         end if;
         Bigger := new String (1 .. Wanted);
         Bigger (1 .. Pending_Used) := Pending (1 .. Pending_Used);
         Free (Pending);
         Pending := Bigger;
         Ok := True;
      exception
         when Storage_Error =>
            Ok := False;
      end Grow_Pending;

      procedure Push (Item : Character; Ok : out Boolean) is
      begin
         if Pending_Used = Pending'Length then
            Grow_Pending (Ok);
            if not Ok then
               return;
            end if;
         end if;
         Pending_Used := Pending_Used + 1;
         Pending (Pending_Used) := Item;
         Ok := True;
      end Push;

      --  Hand the accumulated record to the corpus and start a new one.
      procedure Emit_Record (Ok : out Boolean) is
         Slice : Fuzzy.Text_Slice;
      begin
         loop
            Fuzzy.Corpus.Append
              (Self.Text.all, Self.Used, Pending (1 .. Pending_Used),
               Slice, Ok);
            exit when Ok;
            Grow_Text (Ok);
            if not Ok then
               return;
            end if;
         end loop;
         if Self.Count = Self.Items'Length then
            Grow_Items (Ok);
            if not Ok then
               return;
            end if;
         end if;
         Self.Count := Self.Count + 1;
         Self.Items (Self.Count) := (Text => Slice);
         Pending_Used := 0;
         Ok := True;
      end Emit_Record;

      Block : Ada.Streams.Stream_Element_Array (1 .. 64 * 1024);
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      if Self.Text = null then
         Self.Text := new String (1 .. 64 * 1024);
      end if;
      if Self.Items = null then
         Self.Items := new Fuzzy.Candidate_Array (1 .. 1024);
      end if;
      loop
         Ada.Streams.Read (Input.all, Block, Last);
         exit when Last < Block'First;
         for I in Block'First .. Last loop
            declare
               Item : constant Character := Character'Val (Block (I));
            begin
               if Item = Delimiter then
                  Emit_Record (Ok);
               else
                  Push (Item, Ok);
               end if;
            end;
            if not Ok then
               Free (Pending);
               return;
            end if;
         end loop;
      end loop;
      --  Input not ending in a delimiter still ends a record; input that does
      --  must not produce a trailing empty one. An unterminated empty record
      --  is no bytes at all, so nothing is lost by dropping it.
      Ok := True;
      if Pending_Used > 0 then
         Emit_Record (Ok);
      end if;
      Free (Pending);
   end Read_Standard_Input;

end Fuzzy_Input;
