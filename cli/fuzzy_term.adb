with Interfaces.C;
with System;

package body Fuzzy_Term is
   use Interfaces.C;

   O_RDWR : constant int := 2;
   TCSANOW : constant int := 0;
   TIOCGWINSZ : constant unsigned_long := 16#5413#;
   SIGHUP : constant int := 1;
   SIGTERM : constant int := 15;

   ESC : constant Character := Character'Val (27);
   Enter_Screen : constant String := ESC & "[?1049h";
   Leave_Screen : constant String := ESC & "[?25h" & ESC & "[?1049l";

   function C_Open (Path : char_array; Flags : int) return int
     with Import, Convention => C, External_Name => "open";
   function C_Close (FD : int) return int
     with Import, Convention => C, External_Name => "close";
   function C_Read (FD : int; Buf : System.Address; Bytes : size_t) return long
     with Import, Convention => C, External_Name => "read";
   function C_Write (FD : int; Buf : System.Address; Bytes : size_t) return long
     with Import, Convention => C, External_Name => "write";
   function C_Isatty (FD : int) return int
     with Import, Convention => C, External_Name => "isatty";
   function C_Ioctl
     (FD : int; Request : unsigned_long; Arg : System.Address) return int
     with Import, Convention => C, External_Name => "ioctl";

   --  The terminal mode is handled as an opaque block: only its size and
   --  alignment matter here, because the C library supplies both the query
   --  and the raw-mode edit. That keeps this binding free of any assumption
   --  about where the individual mode fields sit.
   type Mode_Block is array (1 .. 32) of aliased unsigned;

   function C_Tcgetattr (FD : int; Mode : System.Address) return int
     with Import, Convention => C, External_Name => "tcgetattr";
   function C_Tcsetattr
     (FD : int; Actions : int; Mode : System.Address) return int
     with Import, Convention => C, External_Name => "tcsetattr";
   procedure C_Cfmakeraw (Mode : System.Address)
     with Import, Convention => C, External_Name => "cfmakeraw";
   procedure C_Exit (Status : int)
     with Import, Convention => C, External_Name => "_exit", No_Return;
   function C_Signal
     (Sig : int; Handler : System.Address) return System.Address
     with Import, Convention => C, External_Name => "signal";

   type Win_Size is record
      Rows, Cols, X_Pixels, Y_Pixels : unsigned_short;
   end record with Convention => C;

   FD : int := -1;
   Saved : aliased Mode_Block;
   Raw_Active : Boolean := False;

   procedure Write (Item : String) is
      Sent : long;
      Done : Natural := 0;
   begin
      if FD < 0 then
         return;
      end if;
      while Done < Item'Length loop
         Sent := C_Write
           (FD, Item (Item'First + Done)'Address, size_t (Item'Length - Done));
         exit when Sent <= 0;
         Done := Done + Natural (Sent);
      end loop;
   end Write;

   procedure Restore is
      Ignored : int;
   begin
      if Raw_Active then
         Write (Leave_Screen);
         Ignored := C_Tcsetattr (FD, TCSANOW, Saved'Address);
         Raw_Active := False;
      end if;
   end Restore;

   --  Termination signals would otherwise leave the terminal in raw mode.
   --  Restoring it and leaving immediately is all that may safely be
   --  attempted from here.
   procedure On_Signal (Sig : int) with Convention => C;

   procedure On_Signal (Sig : int) is
   begin
      Restore;
      C_Exit (128 + Sig);
   end On_Signal;

   procedure Open (Ok : out Boolean) is
      Work : aliased Mode_Block;
      Ignored : int;
      Ignored_Handler : System.Address;
   begin
      Ok := FD >= 0;
      if Ok then
         return;
      end if;
      FD := C_Open (To_C ("/dev/tty"), O_RDWR);
      if FD < 0 then
         return;
      end if;
      if C_Tcgetattr (FD, Saved'Address) /= 0 then
         Ignored := C_Close (FD);
         FD := -1;
         return;
      end if;
      Work := Saved;
      C_Cfmakeraw (Work'Address);
      if C_Tcsetattr (FD, TCSANOW, Work'Address) /= 0 then
         Ignored := C_Close (FD);
         FD := -1;
         return;
      end if;
      Raw_Active := True;
      Ignored_Handler := C_Signal (SIGTERM, On_Signal'Address);
      Ignored_Handler := C_Signal (SIGHUP, On_Signal'Address);
      Write (Enter_Screen);
      Ok := True;
   end Open;

   procedure Close is
      Ignored : int;
   begin
      if FD < 0 then
         return;
      end if;
      Restore;
      Ignored := C_Close (FD);
      FD := -1;
   end Close;

   function Standard_Input_Is_Terminal return Boolean is (C_Isatty (0) = 1);

   procedure Size (Rows, Cols : out Positive) is
      Window : aliased Win_Size := (others => 0);
   begin
      Rows := 24;
      Cols := 80;
      if FD >= 0 and then C_Ioctl (FD, TIOCGWINSZ, Window'Address) = 0 then
         if Window.Rows > 0 then
            Rows := Positive (Window.Rows);
         end if;
         if Window.Cols > 0 then
            Cols := Positive (Window.Cols);
         end if;
      end if;
   end Size;

   --  Control characters follow the bindings the same keys have in fzf, so
   --  that muscle memory carries over.
   function Control_Key (Item : Character) return Key is
     (case Item is
         when Character'Val (1) => (Line_Start, ' '),
         when Character'Val (3) => (Accept_Abort, ' '),
         when Character'Val (4) => (Delete_Forward, ' '),
         when Character'Val (5) => (Line_End, ' '),
         when Character'Val (8) => (Backspace, ' '),
         when Character'Val (10) => (Down, ' '),
         when Character'Val (11) => (Up, ' '),
         when Character'Val (13) => (Enter, ' '),
         when Character'Val (14) => (Down, ' '),
         when Character'Val (16) => (Up, ' '),
         when Character'Val (21) => (Clear_Line, ' '),
         when Character'Val (23) => (Delete_Word, ' '),
         when Character'Val (127) => (Backspace, ' '),
         when others => (Ignored, ' '));

   procedure Read_Keys (Keys : out Key_Array; Count : out Natural) is
      Block : array (1 .. 128) of aliased unsigned_char;
      Read_Bytes : long;
      Available : Natural;
      At_Byte : Natural := 1;

      function Item (Offset : Natural) return Character is
        (Character'Val (Block (Offset)));

      procedure Emit (Found : Key) is
      begin
         if Count < Keys'Length then
            Count := Count + 1;
            Keys (Keys'First + (Count - 1)) := Found;
         end if;
      end Emit;
   begin
      Count := 0;
      if FD < 0 then
         return;
      end if;
      Read_Bytes := C_Read (FD, Block'Address, Block'Length);
      if Read_Bytes <= 0 then
         return;
      end if;
      Available := Natural (Read_Bytes);
      while At_Byte <= Available loop
         if Item (At_Byte) = ESC
           and then At_Byte + 2 <= Available
           and then (Item (At_Byte + 1) = '[' or else Item (At_Byte + 1) = 'O')
         then
            case Item (At_Byte + 2) is
               when 'A' => Emit ((Up, ' '));
               when 'B' => Emit ((Down, ' '));
               when 'C' => Emit ((Right, ' '));
               when 'D' => Emit ((Left, ' '));
               when 'H' => Emit ((Line_Start, ' '));
               when 'F' => Emit ((Line_End, ' '));
               when '3' => Emit ((Delete_Forward, ' '));
               when others => Emit ((Ignored, ' '));
            end case;
            --  Parameterized sequences run on to a final byte outside the
            --  digit and semicolon range.
            if Item (At_Byte + 2) in '0' .. '9' then
               At_Byte := At_Byte + 3;
               while At_Byte <= Available
                 and then Item (At_Byte) in '0' .. '9' | ';'
               loop
                  At_Byte := At_Byte + 1;
               end loop;
               At_Byte := At_Byte + 1;
            else
               At_Byte := At_Byte + 3;
            end if;
         elsif Item (At_Byte) = ESC then
            Emit ((Accept_Abort, ' '));
            At_Byte := At_Byte + 1;
         elsif Item (At_Byte) in ' ' .. '~' then
            Emit ((Char, Item (At_Byte)));
            At_Byte := At_Byte + 1;
         else
            Emit (Control_Key (Item (At_Byte)));
            At_Byte := At_Byte + 1;
         end if;
      end loop;
   end Read_Keys;

end Fuzzy_Term;
