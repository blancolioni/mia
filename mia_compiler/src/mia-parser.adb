with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Mia.Lexer;

package body Mia.Parser is

   use Ada.Strings.Unbounded;
   use Mia.Lexer;
   use Mia.Model;

   function Parse (Source : String) return Package_Spec is

      L : Lexer_Type;

      procedure Expect (Kind : Token_Kind) is
         T : constant Token := Next (L);
      begin
         if T.Kind /= Kind then
            raise Parse_Error
              with "line" & T.Line'Image & ": expected "
                   & Kind'Image & ", got '"
                   & To_String (T.Text) & "'";
         end if;
      end Expect;

      function Expect_Identifier return String is
         T : constant Token := Next (L);
      begin
         if T.Kind /= Tok_Identifier then
            raise Parse_Error
              with "line" & T.Line'Image
                   & ": expected identifier, got '"
                   & To_String (T.Text) & "'";
         end if;
         return To_String (T.Text);
      end Expect_Identifier;

      function Parse_Name return String is
         --  name ::= identifier { "." identifier }
         Result_S : Unbounded_String :=
                      To_Unbounded_String (Expect_Identifier);
      begin
         while Peek (L).Kind = Tok_Dot loop
            Consume (L);
            Append (Result_S, ".");
            Append (Result_S, Expect_Identifier);
         end loop;
         return To_String (Result_S);
      end Parse_Name;

      function Parse_Aspect_Value return String is
         T : constant Token := Peek (L);
      begin
         if T.Kind = Tok_String_Literal then
            declare
               Tok : constant Token := Next (L);
            begin
               return To_String (Tok.Text);
            end;
         elsif T.Kind = Tok_Identifier then
            return Parse_Name;
         else
            raise Parse_Error
              with "line" & T.Line'Image
                   & ": expected string or identifier";
         end if;
      end Parse_Aspect_Value;

      function Parse_Method (S : String) return Http_Method is
         Lower : constant String :=
                   Ada.Characters.Handling.To_Lower (S);
      begin
         if Lower = "get" then
            return Get;
         elsif Lower = "post" then
            return Post;
         elsif Lower = "put" then
            return Put;
         elsif Lower = "delete" then
            return Delete;
         elsif Lower = "patch" then
            return Patch;
         else
            raise Parse_Error with "unknown HTTP method: " & S;
         end if;
      end Parse_Method;

      function Parse_Param return Parameter_Type is
         P : Parameter_Type;
      begin
         P.Name      := To_Unbounded_String (Expect_Identifier);
         Expect (Tok_Colon);
         P.Type_Name := To_Unbounded_String (Parse_Name);
         return P;
      end Parse_Param;

      function Parse_Function return Function_Spec is
         F : Function_Spec;
      begin
         F.Name := To_Unbounded_String (Expect_Identifier);
         if Peek (L).Kind = Tok_Left_Paren then
            Consume (L);
            if Peek (L).Kind = Tok_Right_Paren then
               raise Parse_Error
                 with "line" & Peek (L).Line'Image
                      & ": empty parameter list; omit parentheses"
                      & " for functions with no arguments";
            end if;
            F.Parameters.Append (Parse_Param);
            while Peek (L).Kind = Tok_Semicolon loop
               Consume (L);
               F.Parameters.Append (Parse_Param);
            end loop;
            Expect (Tok_Right_Paren);
         end if;
         Expect (Tok_Return);
         declare
            First : constant Token := Peek (L);
         begin
            if First.Kind = Tok_Identifier
              and then Ada.Characters.Handling.To_Lower
                         (To_String (First.Text)) = "array"
            then
               Consume (L);
               declare
                  Of_Word : constant String := Expect_Identifier;
               begin
                  if Ada.Characters.Handling.To_Lower (Of_Word) /= "of" then
                     raise Parse_Error with "expected 'of' after 'array'";
                  end if;
               end;
               F.Return_Type := To_Unbounded_String (Parse_Name);
               F.Is_Array    := True;
            else
               F.Return_Type := To_Unbounded_String (Parse_Name);
            end if;
         end;
         Expect (Tok_With);
         loop
            declare
               Key   : constant String := Expect_Identifier;
               Lower : constant String :=
                         Ada.Characters.Handling.To_Lower (Key);
            begin
               Expect (Tok_Arrow);
               declare
                  Val : constant String := Parse_Aspect_Value;
               begin
                  if Lower = "method" then
                     F.Method := Parse_Method (Val);
                  elsif Lower = "path" then
                     F.Path := To_Unbounded_String (Val);
                  elsif Lower = "impl" then
                     F.Impl := To_Unbounded_String (Val);
                  elsif Lower = "scanner" then
                     F.Scanner := To_Unbounded_String (Val);
                  elsif Lower = "to_json" then
                     F.To_Json := To_Unbounded_String (Val);
                  elsif Lower = "from_body" then
                     if Length (F.From_Body) > 0 then
                        raise Parse_Error
                          with "at most one From_Body per function";
                     end if;
                     F.From_Body := To_Unbounded_String (Val);
                  elsif Lower = "from_json" then
                     F.From_Json := To_Unbounded_String (Val);
                  elsif Lower = "schema" then
                     F.Body_Schema := To_Unbounded_String (Val);
                  elsif Lower = "auth" then
                     declare
                        Auth_Lower : constant String :=
                                       Ada.Characters.Handling.To_Lower
                                         (Val);
                     begin
                        if Auth_Lower = "anonymous" then
                           F.Auth := Anonymous;
                        elsif Auth_Lower = "required" then
                           F.Auth := Inherited;
                        else
                           raise Parse_Error
                             with "unknown auth value: " & Val;
                        end if;
                     end;
                  else
                     raise Parse_Error
                       with "unknown aspect: " & Key;
                  end if;
               end;
            end;
            exit when Peek (L).Kind /= Tok_Comma;
            Consume (L);
         end loop;
         if Length (F.From_Body) > 0 and then Length (F.From_Json) = 0 then
            raise Parse_Error with "From_Body requires From_Json";
         end if;
         if Length (F.From_Json) > 0 and then Length (F.From_Body) = 0 then
            raise Parse_Error with "From_Json requires From_Body";
         end if;
         if F.Is_Array and then Length (F.Scanner) = 0 then
            raise Parse_Error with "array return type requires Scanner aspect";
         end if;
         if not F.Is_Array and then Length (F.Scanner) > 0 then
            raise Parse_Error with "Scanner aspect requires array return type";
         end if;
         return F;
      end Parse_Function;

      --  Parse field list up to and including 'end record'
      procedure Parse_Record_Fields
        (T : in out Mia.Model.Type_Spec)
      is
      begin
         while Peek (L).Kind /= Tok_End loop
            declare
               F : Mia.Model.Type_Field;
            begin
               F.Name := To_Unbounded_String (Expect_Identifier);
               Expect (Tok_Colon);
               F.Type_Name :=
                 To_Unbounded_String (Expect_Identifier);
               T.Fields.Append (F);
               Expect (Tok_Semicolon);
            end;
         end loop;
         Expect (Tok_End);
         Expect (Tok_Record);
      end Parse_Record_Fields;

      --  Parse optional 'with Key => Val, ...' after a type body
      procedure Parse_Type_Aspects
        (T : in out Mia.Model.Type_Spec)
      is
      begin
         if Peek (L).Kind /= Tok_With then
            return;
         end if;
         Consume (L);
         loop
            declare
               Key   : constant String := Expect_Identifier;
               Lower : constant String :=
                         Ada.Characters.Handling.To_Lower (Key);
            begin
               Expect (Tok_Arrow);
               declare
                  Val : constant String := Parse_Aspect_Value;
               begin
                  if Lower = "to_json" then
                     T.To_Json := To_Unbounded_String (Val);
                  elsif Lower = "kind" then
                     T.Variant_Tag :=
                       To_Unbounded_String
                         (Ada.Characters.Handling.To_Lower (Val));
                  else
                     raise Parse_Error
                       with "unknown type aspect: " & Key;
                  end if;
               end;
            end;
            exit when Peek (L).Kind /= Tok_Comma;
            Consume (L);
         end loop;
      end Parse_Type_Aspects;

      function Parse_Type_Decl return Mia.Model.Type_Spec is
         Name : constant String := Parse_Name;

         function Peek_Word return String is
         begin
            if Peek (L).Kind = Tok_Identifier then
               return Ada.Characters.Handling.To_Lower
                        (To_String (Peek (L).Text));
            end if;
            return "";
         end Peek_Word;

      begin
         Expect (Tok_Is);

         --  Enum: type A.B.T is (..)
         --  A.B is the existing Ada package where the enumeration is
         --  declared; its literals are unknown at code-gen time and are
         --  discovered at runtime via the type's attributes.
         if Peek (L).Kind = Tok_Left_Paren then
            declare
               T : Mia.Model.Type_Spec (Kind => Mia.Model.Enum_Type);
            begin
               T.Name := To_Unbounded_String (Name);
               Consume (L);              --  (
               Expect (Tok_Dot);         --  .
               Expect (Tok_Dot);         --  .
               Expect (Tok_Right_Paren); --  )
               return T;
            end;

         --  Record: type T is record ... end record
         elsif Peek (L).Kind = Tok_Record then
            declare
               T : Mia.Model.Type_Spec (Kind => Mia.Model.Record_Type);
            begin
               T.Name := To_Unbounded_String (Name);
               Consume (L);
               Parse_Record_Fields (T);
               Parse_Type_Aspects (T);
               return T;
            end;

         --  Null record: type T is null record
         elsif Peek_Word = "null" then
            Consume (L);
            Expect (Tok_Record);
            declare
               T : Mia.Model.Type_Spec (Kind => Mia.Model.Record_Type);
            begin
               T.Name := To_Unbounded_String (Name);
               --  Fields stays empty
               Parse_Type_Aspects (T);
               return T;
            end;

         --  Derived: type T is new Parent with record/null record
         elsif Peek_Word = "new" then
            Consume (L);
            declare
               Parent_Name : constant String := Parse_Name;
               T : Mia.Model.Type_Spec (Kind => Mia.Model.Record_Type);
            begin
               T.Name   := To_Unbounded_String (Name);
               T.Parent := To_Unbounded_String (Parent_Name);
               Expect (Tok_With);
               if Peek_Word = "null" then
                  Consume (L);
                  Expect (Tok_Record);
                  --  Fields stays empty
               elsif Peek (L).Kind = Tok_Record then
                  Consume (L);
                  Parse_Record_Fields (T);
               else
                  raise Parse_Error
                    with "line" & Peek (L).Line'Image
                         & ": expected 'record' or 'null record'"
                         & " after 'is new ... with'";
               end if;
               Parse_Type_Aspects (T);
               return T;
            end;

         else
            raise Parse_Error
              with "line" & Peek (L).Line'Image
                   & ": expected '(', 'record', 'null record',"
                   & " or 'new' in type declaration";
         end if;
      end Parse_Type_Decl;

      function Short_Name_Of (Name : String) return String is
      begin
         for I in reverse Name'Range loop
            if Name (I) = '.' then
               return Name (I + 1 .. Name'Last);
            end if;
         end loop;
         return Name;
      end Short_Name_Of;

      procedure Parse_Links (Result : in out Package_Spec) is
         Type_Name : constant String := Parse_Name;
         T_Idx     : Natural := 0;
      begin
         for I in Result.Types.First_Index
                  .. Result.Types.Last_Index
         loop
            declare
               Full : constant String :=
                        To_String (Result.Types.Element (I).Name);
            begin
               if Full = Type_Name
                 or else Short_Name_Of (Full) = Type_Name
               then
                  T_Idx := I;
                  exit;
               end if;
            end;
         end loop;
         if T_Idx = 0 then
            raise Parse_Error
              with "links: unknown type '" & Type_Name & "'";
         end if;
         Expect (Tok_Is);
         declare
            T : Mia.Model.Type_Spec :=
                  Result.Types.Element (T_Idx);
         begin
            while Peek (L).Kind /= Tok_End loop
               declare
                  Link : Mia.Model.Link_Spec;
               begin
                  Link.Name :=
                    To_Unbounded_String (Expect_Identifier);
                  Expect (Tok_Arrow);
                  Link.Function_Name :=
                    To_Unbounded_String (Expect_Identifier);
                  Expect (Tok_Left_Paren);
                  loop
                     declare
                        B : Mia.Model.Link_Binding;
                     begin
                        B.Param_Name :=
                          To_Unbounded_String (Expect_Identifier);
                        Expect (Tok_Arrow);
                        B.Field_Name :=
                          To_Unbounded_String (Expect_Identifier);
                        Link.Bindings.Append (B);
                     end;
                     exit when Peek (L).Kind /= Tok_Comma;
                     Consume (L);
                  end loop;
                  Expect (Tok_Right_Paren);
                  Expect (Tok_Semicolon);
                  T.Links.Append (Link);
               end;
            end loop;
            Result.Types.Replace_Element (T_Idx, T);
         end;
         Expect (Tok_End);
         declare
            use Ada.Characters.Handling;
            End_Word : constant String :=
                         To_Lower (Expect_Identifier);
         begin
            if End_Word /= "links" then
               raise Parse_Error
                 with "expected 'links' after 'end'";
            end if;
         end;
      end Parse_Links;

      procedure Parse_Package_Aspects (Spec : in out Package_Spec) is
      begin
         loop
            declare
               Key   : constant String := Expect_Identifier;
               Lower : constant String :=
                         Ada.Characters.Handling.To_Lower (Key);
            begin
               Expect (Tok_Arrow);
               declare
                  Val : constant String := Parse_Aspect_Value;
               begin
                  if Lower = "session" then
                     Spec.Session_Type :=
                       To_Unbounded_String (Val);
                  else
                     raise Parse_Error
                       with "unknown package aspect: " & Key;
                  end if;
               end;
            end;
            exit when Peek (L).Kind /= Tok_Comma;
            Consume (L);
         end loop;
      end Parse_Package_Aspects;

      Result : Package_Spec;

   begin
      Open (L, Source);
      Expect (Tok_Package);
      Result.Name := To_Unbounded_String (Parse_Name);
      if Peek (L).Kind = Tok_With then
         Consume (L);
         Parse_Package_Aspects (Result);
      end if;
      Expect (Tok_Is);
      while Peek (L).Kind = Tok_Function
        or else Peek (L).Kind = Tok_Type
        or else (Peek (L).Kind = Tok_Identifier
                 and then Ada.Characters.Handling.To_Lower
                            (To_String (Peek (L).Text)) = "links")
      loop
         if Peek (L).Kind = Tok_Function then
            Consume (L);
            Result.Functions.Append (Parse_Function);
         elsif Peek (L).Kind = Tok_Type then
            Consume (L);
            Result.Types.Append (Parse_Type_Decl);
         else
            Consume (L);  --  consume 'links'
            Parse_Links (Result);
         end if;
         Expect (Tok_Semicolon);
      end loop;
      Expect (Tok_End);
      declare
         End_Name : constant String := Parse_Name;
         Pkg_Name : constant String := To_String (Result.Name);
      begin
         if End_Name /= Pkg_Name then
            raise Parse_Error
              with "end name '" & End_Name
                   & "' does not match package name '"
                   & Pkg_Name & "'";
         end if;
      end;
      Expect (Tok_Semicolon);
      return Result;
   end Parse;

end Mia.Parser;
