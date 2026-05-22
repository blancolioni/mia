with Ada.Characters.Handling;

package body Mia.Lexer is

   use Ada.Strings.Unbounded;

   function At_End (L : Lexer_Type) return Boolean is
   begin
      return L.Position > Length (L.Source);
   end At_End;

   function Current (L : Lexer_Type) return Character is
   begin
      if At_End (L) then
         return ASCII.NUL;
      end if;
      return Element (L.Source, L.Position);
   end Current;

   function Look_Ahead (L : Lexer_Type) return Character is
   begin
      if L.Position >= Length (L.Source) then
         return ASCII.NUL;
      end if;
      return Element (L.Source, L.Position + 1);
   end Look_Ahead;

   procedure Advance (L : in out Lexer_Type) is
   begin
      if not At_End (L) then
         if Current (L) = ASCII.LF then
            L.Line := L.Line + 1;
         end if;
         L.Position := L.Position + 1;
      end if;
   end Advance;

   procedure Skip_Trivia (L : in out Lexer_Type) is
   begin
      loop
         if At_End (L) then
            exit;
         elsif Current (L) = ' '
           or else Current (L) = ASCII.HT
           or else Current (L) = ASCII.CR
           or else Current (L) = ASCII.LF
         then
            Advance (L);
         elsif Current (L) = '-' and then Look_Ahead (L) = '-' then
            while not At_End (L) and then Current (L) /= ASCII.LF loop
               Advance (L);
            end loop;
         else
            exit;
         end if;
      end loop;
   end Skip_Trivia;

   function Read_Word (L : in out Lexer_Type) return Token is
      use Ada.Characters.Handling;
      Start_Line : constant Positive := L.Line;
      Text       : Unbounded_String;
   begin
      while not At_End (L)
        and then (Is_Alphanumeric (Current (L))
                  or else Current (L) = '_')
      loop
         Append (Text, Current (L));
         Advance (L);
      end loop;

      declare
         S : constant String := To_Lower (To_String (Text));
      begin
         if S = "package" then
            return (Tok_Package, Text, Start_Line);
         elsif S = "is" then
            return (Tok_Is, Text, Start_Line);
         elsif S = "end" then
            return (Tok_End, Text, Start_Line);
         elsif S = "function" then
            return (Tok_Function, Text, Start_Line);
         elsif S = "return" then
            return (Tok_Return, Text, Start_Line);
         elsif S = "with" then
            return (Tok_With, Text, Start_Line);
         elsif S = "type" then
            return (Tok_Type, Text, Start_Line);
         elsif S = "record" then
            return (Tok_Record, Text, Start_Line);
         else
            return (Tok_Identifier, Text, Start_Line);
         end if;
      end;
   end Read_Word;

   function Read_String_Lit (L : in out Lexer_Type) return Token is
      Start_Line : constant Positive := L.Line;
      Text       : Unbounded_String;
   begin
      Advance (L);
      loop
         if At_End (L) then
            return (Tok_Error,
                    To_Unbounded_String ("Unterminated string"),
                    Start_Line);
         elsif Current (L) = '"' then
            Advance (L);
            return (Tok_String_Literal, Text, Start_Line);
         else
            Append (Text, Current (L));
            Advance (L);
         end if;
      end loop;
   end Read_String_Lit;

   function Scan (L : in out Lexer_Type) return Token is
      Line : Positive;
   begin
      Skip_Trivia (L);
      Line := L.Line;

      if At_End (L) then
         return (Tok_End_Of_File, Null_Unbounded_String, Line);
      end if;

      case Current (L) is
         when 'A' .. 'Z' | 'a' .. 'z' =>
            return Read_Word (L);
         when '"' =>
            return Read_String_Lit (L);
         when '(' =>
            Advance (L);
            return (Tok_Left_Paren, To_Unbounded_String ("("), Line);
         when ')' =>
            Advance (L);
            return (Tok_Right_Paren, To_Unbounded_String (")"), Line);
         when ';' =>
            Advance (L);
            return (Tok_Semicolon, To_Unbounded_String (";"), Line);
         when ':' =>
            Advance (L);
            return (Tok_Colon, To_Unbounded_String (":"), Line);
         when ',' =>
            Advance (L);
            return (Tok_Comma, To_Unbounded_String (","), Line);
         when '.' =>
            Advance (L);
            return (Tok_Dot, To_Unbounded_String ("."), Line);
         when '=' =>
            if Look_Ahead (L) = '>' then
               Advance (L);
               Advance (L);
               return (Tok_Arrow, To_Unbounded_String ("=>"), Line);
            else
               Advance (L);
               return (Tok_Error,
                       To_Unbounded_String ("Expected =>"),
                       Line);
            end if;
         when others =>
            declare
               Ch : constant Character := Current (L);
            begin
               Advance (L);
               return (Tok_Error,
                       To_Unbounded_String ("Unexpected: " & Ch),
                       Line);
            end;
      end case;
   end Scan;

   procedure Open (L : out Lexer_Type; Source : String) is
   begin
      L.Source   := To_Unbounded_String (Source);
      L.Position := 1;
      L.Line     := 1;
      L.Has_Peek := False;
      L.Peeked   := (Kind => Tok_End_Of_File,
                     Text => Null_Unbounded_String,
                     Line => 1);
   end Open;

   function Next (L : in out Lexer_Type) return Token is
   begin
      if L.Has_Peek then
         L.Has_Peek := False;
         return L.Peeked;
      end if;
      return Scan (L);
   end Next;

   function Peek (L : in out Lexer_Type) return Token is
   begin
      if not L.Has_Peek then
         L.Peeked   := Scan (L);
         L.Has_Peek := True;
      end if;
      return L.Peeked;
   end Peek;

   procedure Consume (L : in out Lexer_Type) is
      Unused_Token : constant Token := Next (L);
   begin
      null;
   end Consume;

end Mia.Lexer;
