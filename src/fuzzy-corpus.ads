--  Packing helper for the caller-owned corpus that Fuzzy searches. The library
--  never allocates, so the buffer and its fill level belong to the client; this
--  package only appends into that buffer and reports the resulting slice. It
--  exists so clients do not each re-derive the capacity arithmetic.
package Fuzzy.Corpus with SPARK_Mode, Pure is

   --  Characters still available after the first Used ones.
   function Room (Buffer : String; Used : Natural) return Natural is
     (Buffer'Length - Used)
   with Pre => Used <= Buffer'Length;

   --  The slice that appending Item would produce. An empty item gets First
   --  one: an empty slice is never dereferenced, so it has no location, and
   --  taking no position from the buffer keeps First representable both for a
   --  buffer ending at Positive'Last and for a buffer with a null range.
   function Appended_Slice
     (Buffer : String; Used : Natural; Item : String) return Text_Slice is
     (First  => (if Item'Length = 0 then 1 else Buffer'First + Used),
      Length => Item'Length)
   with Pre => Used <= Buffer'Length
     and then Item'Length <= Room (Buffer, Used);

   --  Slice holds exactly Item. Clients can carry this through their own
   --  reasoning: it is preserved by later appends, which only write beyond
   --  the current fill level.
   function Holds
     (Buffer : String; Slice : Text_Slice; Item : String) return Boolean is
     (Slice.Length = Item'Length
      and then (for all K in 1 .. Slice.Length =>
                  Character_At (Buffer, Slice, K) = Item (Item'First + (K - 1))))
   with Pre => Valid (Buffer, Slice);

   --  Append Item to the packed corpus. On success Slice describes where it
   --  landed and is ready to store in a Candidate. On failure the buffer and
   --  fill level are untouched, so a client can grow the buffer and retry.
   --  The frame condition below names the whole buffer, so an
   --  assertion-enabled build copies it on every append; that makes building
   --  a large corpus quadratic there, though never in a release build.
   --  Whether Buffer or Buffer (Buffer'First .. Buffer'First + Used - 1) is
   --  later passed to Search is immaterial: slices index Buffer absolutely and
   --  no slice covers the unused tail.
   procedure Append
     (Buffer : in out String; Used : in out Natural; Item : String;
      Slice : out Text_Slice; Ok : out Boolean)
   with Global => null, Always_Terminates,
     Pre => Used <= Buffer'Length,
     Post => Ok = (Item'Length <= Buffer'Length - Used'Old)
       and then Used <= Buffer'Length
       and then
         (if Ok then
            Used = Used'Old + Item'Length
            and then Slice = Appended_Slice (Buffer, Used'Old, Item)
            and then Valid (Buffer, Slice)
            and then Holds (Buffer, Slice, Item)
            --  Earlier appends keep their contents, so their slices stay valid
            --  and keep holding what they held.
            and then Buffer (Buffer'First .. Buffer'First + (Used'Old - 1)) =
              Buffer'Old (Buffer'First .. Buffer'First + (Used'Old - 1))
          else
            Used = Used'Old
            and then Slice.Length = 0
            and then Buffer = Buffer'Old);

end Fuzzy.Corpus;
