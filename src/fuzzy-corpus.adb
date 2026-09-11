package body Fuzzy.Corpus
  with SPARK_Mode
is

   procedure Append
     (Buffer : in out String;
      Used   : in out Natural;
      Item   : String;
      Slice  : out Text_Slice;
      Ok     : out Boolean)
   is
      Start : Positive;
   begin
      if Item'Length > Buffer'Length - Used then
         Slice := (First => 1, Length => 0);
         Ok := False;
         return;
      end if;
      Slice := Appended_Slice (Buffer, Used, Item);
      if Item'Length > 0 then
         Start := Buffer'First + Used;
         Buffer (Start .. Start + (Item'Length - 1)) := Item;
      end if;
      Used := Used + Item'Length;
      Ok := True;
   end Append;

end Fuzzy.Corpus;
