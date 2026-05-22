with Ada.Strings.Unbounded;

package Mia.Lexer is

   type Token_Kind is
     (Tok_Package,
      Tok_Is,
      Tok_End,
      Tok_Function,
      Tok_Return,
      Tok_With,
      Tok_Type,
      Tok_Record,
      Tok_Left_Paren,
      Tok_Right_Paren,
      Tok_Semicolon,
      Tok_Colon,
      Tok_Comma,
      Tok_Arrow,
      Tok_Dot,
      Tok_Identifier,
      Tok_String_Literal,
      Tok_End_Of_File,
      Tok_Error);

   type Token is record
      Kind : Token_Kind                         := Tok_End_Of_File;
      Text : Ada.Strings.Unbounded.Unbounded_String;
      Line : Positive                           := 1;
   end record;

   type Lexer_Type is private;

   procedure Open
     (L      :    out Lexer_Type;
      Source :        String);

   function Next (L : in out Lexer_Type) return Token;
   function Peek (L : in out Lexer_Type) return Token;
   procedure Consume (L : in out Lexer_Type);

private

   type Lexer_Type is record
      Source   : Ada.Strings.Unbounded.Unbounded_String;
      Position : Natural  := 0;
      Line     : Positive := 1;
      Has_Peek : Boolean  := False;
      Peeked   : Token;
   end record;

end Mia.Lexer;
