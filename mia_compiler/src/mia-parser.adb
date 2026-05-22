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
         P.Type_Name := To_Unbounded_String (Expect_Identifier);
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
         F.Return_Type := To_Unbounded_String (Expect_Identifier);
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
         return F;
      end Parse_Function;

      function Parse_Type_Decl return Mia.Model.Type_Spec is
         Name : constant String := Expect_Identifier;
      begin
         Expect (Tok_Is);
         if Peek (L).Kind = Tok_Left_Paren then
            declare
               T : Mia.Model.Type_Spec (Kind => Mia.Model.Enum_Type);
            begin
               T.Name := To_Unbounded_String (Name);
               Consume (L);
               T.Literals.Append
                 (To_Unbounded_String (Expect_Identifier));
               while Peek (L).Kind = Tok_Comma loop
                  Consume (L);
                  T.Literals.Append
                    (To_Unbounded_String (Expect_Identifier));
               end loop;
               Expect (Tok_Right_Paren);
               return T;
            end;
         elsif Peek (L).Kind = Tok_Record then
            declare
               T : Mia.Model.Type_Spec (Kind => Mia.Model.Record_Type);
            begin
               T.Name := To_Unbounded_String (Name);
               Consume (L);
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
               return T;
            end;
         else
            raise Parse_Error
              with "line" & Peek (L).Line'Image
                   & ": expected '(' or 'record' in type declaration";
         end if;
      end Parse_Type_Decl;

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
      loop
         if Peek (L).Kind = Tok_Function then
            Consume (L);
            Result.Functions.Append (Parse_Function);
         else
            Consume (L);
            Result.Types.Append (Parse_Type_Decl);
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
