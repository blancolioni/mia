with Ada.Characters.Handling;
with Ada.Containers.Ordered_Sets;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Mia.Generator is

   use Ada.Strings.Unbounded;

   package String_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => Unbounded_String,
      "<"          => Ada.Strings.Unbounded."<",
      "="          => Ada.Strings.Unbounded."=");

   function To_Lower (S : String) return String
     renames Ada.Characters.Handling.To_Lower;

   function Package_To_File (Name : String) return String;
   function Impl_Package     (Impl : String) return String;
   function Ada_Lit          (S    : String) return String;
   function Short_Name       (Qualified : String) return String;

   function Resolve_Type
     (Name  : String;
      Types : Mia.Model.Type_Vectors.Vector)
      return String;

   function Json_Schema_Type (Ada_Type : String) return String;
   function Method_Image     (M : Mia.Model.Http_Method) return String;
   function Method_Status    (M : Mia.Model.Http_Method) return String;

   function Placeholder_Of
     (Template   : String;
      Param_Name : String) return String;

   function Is_Path_Param
     (Template   : String;
      Param_Name : String) return Boolean;

   function Build_Params_Json
     (Fn : Mia.Model.Function_Spec) return String;

   function Resolve_To_Json
     (Return_Type : String;
      Fn          : Mia.Model.Function_Spec;
      Types       : Mia.Model.Type_Vectors.Vector)
      return String;

   function Json_Set_Field (Return_Type : String) return String;

   function Schema_For_Type
     (Type_Name : String;
      Types     : Mia.Model.Type_Vectors.Vector)
      return String;

   function Schema_For_Record
     (T     : Mia.Model.Type_Spec;
      Types : Mia.Model.Type_Vectors.Vector)
      return String;

   procedure Write_Spec
     (Pkg        : String;
      Output_Dir : String;
      File_Base  : String);

   procedure Write_Body
     (Spec       : Mia.Model.Package_Spec;
      Pkg        : String;
      Output_Dir : String;
      File_Base  : String);

   procedure Write_Type_Package
     (Spec       : Mia.Model.Package_Spec;
      Pkg_Name   : String;
      Output_Dir : String);

   --  ---------------------------------------------------------------
   --  General utilities
   --  ---------------------------------------------------------------

   function Package_To_File (Name : String) return String is
      Result : String := To_Lower (Name);
   begin
      for I in Result'Range loop
         if Result (I) = '.' then
            Result (I) := '-';
         end if;
      end loop;
      return Result;
   end Package_To_File;

   function Impl_Package (Impl : String) return String is
      Last_Dot : Natural := 0;
   begin
      for I in Impl'Range loop
         if Impl (I) = '.' then
            Last_Dot := I;
         end if;
      end loop;
      if Last_Dot = 0 then
         return "";
      end if;
      return Impl (Impl'First .. Last_Dot - 1);
   end Impl_Package;

   --  Return S wrapped in an Ada string literal with " doubled.
   function Ada_Lit (S : String) return String is
      Result : Unbounded_String;
   begin
      Append (Result, """");
      for I in S'Range loop
         if S (I) = '"' then
            Append (Result, """""");
         else
            Append (Result, S (I));
         end if;
      end loop;
      Append (Result, """");
      return To_String (Result);
   end Ada_Lit;

   function Short_Name (Qualified : String) return String is
      Last_Dot : Natural := 0;
   begin
      for I in Qualified'Range loop
         if Qualified (I) = '.' then
            Last_Dot := I;
         end if;
      end loop;
      return Qualified (Last_Dot + 1 .. Qualified'Last);
   end Short_Name;

   function Resolve_Type
     (Name  : String;
      Types : Mia.Model.Type_Vectors.Vector)
      return String
   is
   begin
      for T of Types loop
         declare
            Full : constant String := To_String (T.Name);
         begin
            if Full = Name or else Short_Name (Full) = Name then
               return Full;
            end if;
         end;
      end loop;
      return Name;
   end Resolve_Type;

   function Resolve_To_Json
     (Return_Type : String;
      Fn          : Mia.Model.Function_Spec;
      Types       : Mia.Model.Type_Vectors.Vector)
      return String
   is
      use type Mia.Model.Type_Kind;
   begin
      for T of Types loop
         declare
            Full : constant String := To_String (T.Name);
         begin
            if Full = Return_Type or else Short_Name (Full) = Return_Type then
               declare
                  Tj : constant String := To_String (T.To_Json);
               begin
                  if Tj /= "" then
                     return Tj;
                  end if;
               end;
               --  Auto-derive To_Json from the type's package for record types
               if T.Kind = Mia.Model.Record_Type then
                  declare
                     Pkg : constant String := Impl_Package (Full);
                  begin
                     if Pkg /= "" then
                        return Pkg & ".To_Json";
                     end if;
                  end;
               end if;
            end if;
         end;
      end loop;
      return To_String (Fn.To_Json);
   end Resolve_To_Json;

   function Json_Schema_Type (Ada_Type : String) return String is
      Lower : constant String := To_Lower (Ada_Type);
   begin
      if Lower = "boolean" then
         return "boolean";
      elsif Lower = "integer"
        or else Lower = "positive"
        or else Lower = "natural"
      then
         return "integer";
      elsif Lower = "float" or else Lower = "long_float" then
         return "number";
      else
         return "string";
      end if;
   end Json_Schema_Type;

   function Method_Image (M : Mia.Model.Http_Method) return String is
   begin
      case M is
         when Mia.Model.Get    => return "get";
         when Mia.Model.Post   => return "post";
         when Mia.Model.Put    => return "put";
         when Mia.Model.Delete => return "delete";
         when Mia.Model.Patch  => return "patch";
      end case;
   end Method_Image;

   function Method_Status (M : Mia.Model.Http_Method) return String is
   begin
      case M is
         when Mia.Model.Get    => return "AWS.Status.GET";
         when Mia.Model.Post   => return "AWS.Status.POST";
         when Mia.Model.Put    => return "AWS.Status.PUT";
         when Mia.Model.Delete => return "AWS.Status.DELETE";
         when Mia.Model.Patch  => return "AWS.Status.PATCH";
      end case;
   end Method_Status;

   --  Return the path placeholder name matching an Ada parameter name.
   function Placeholder_Of
     (Template   : String;
      Param_Name : String) return String
   is
      Lower_Name : constant String := To_Lower (Param_Name);
      Start      : Natural         := 0;
   begin
      for I in Template'Range loop
         if Template (I) = '{' then
            Start := I + 1;
         elsif Template (I) = '}' and then Start > 0 then
            declare
               Placeholder : constant String :=
                               Template (Start .. I - 1);
            begin
               if To_Lower (Placeholder) = Lower_Name then
                  return Placeholder;
               end if;
            end;
            Start := 0;
         end if;
      end loop;
      --  Not in path — query string or body; use the parameter name as key.
      return Lower_Name;
   end Placeholder_Of;

   function Is_Path_Param
     (Template   : String;
      Param_Name : String) return Boolean
   is
      Lower_Name : constant String := To_Lower (Param_Name);
      Start      : Natural         := 0;
   begin
      for I in Template'Range loop
         if Template (I) = '{' then
            Start := I + 1;
         elsif Template (I) = '}' and then Start > 0 then
            if To_Lower (Template (Start .. I - 1)) = Lower_Name then
               return True;
            end if;
            Start := 0;
         end if;
      end loop;
      return False;
   end Is_Path_Param;

   --  Build a JSON array of OpenAPI parameter objects at code-gen time.
   --  Path params use "in":"path"; remaining non-body params use "in":"query".
   --  The body param (From_Body) is omitted — it appears in requestBody.
   function Build_Params_Json
     (Fn : Mia.Model.Function_Spec) return String
   is
      J          : Unbounded_String;
      First_P    : Boolean := True;
      Path_Tmpl  : constant String := To_String (Fn.Path);
      Body_Param : constant String := To_Lower (To_String (Fn.From_Body));
   begin
      Append (J, "[");
      for P of Fn.Parameters loop
         declare
            P_Name  : constant String := To_String (P.Name);
            P_J     : constant String :=
                        Json_Schema_Type (To_String (P.Type_Name));
            In_Path : constant Boolean :=
                        Is_Path_Param (Path_Tmpl, P_Name);
            Is_Body : constant Boolean :=
                        Body_Param /= ""
                        and then To_Lower (P_Name) = Body_Param;
         begin
            if not Is_Body then
               declare
                  P_Key : constant String :=
                            Placeholder_Of (Path_Tmpl, P_Name);
               begin
                  if not First_P then
                     Append (J, ",");
                  end if;
                  First_P := False;
                  Append (J, "{""name"":""" & P_Key & """,");
                  if In_Path then
                     Append (J, """in"":""path"",""required"":true,");
                  else
                     Append (J, """in"":""query"",""required"":true,");
                  end if;
                  Append (J, """schema"":{""type"":""" & P_J & """}}");
               end;
            end if;
         end;
      end loop;
      Append (J, "]");
      return To_String (J);
   end Build_Params_Json;

   --  ---------------------------------------------------------------
   --  JSON field expression for a given Ada return type
   --  ---------------------------------------------------------------

   function Json_Set_Field (Return_Type : String) return String is
      Lower : constant String := To_Lower (Return_Type);
   begin
      if Lower = "boolean"
        or else Lower = "integer"
        or else Lower = "positive"
        or else Lower = "natural"
        or else Lower = "string"
      then
         return "Set_Field (Obj, ""result"", Result)";
      elsif Lower = "long_float" then
         return "Set_Field_Long_Float"
              & " (Obj, ""result"", Long_Float (Result))";
      elsif Lower = "float" then
         return "Set_Field (Obj, ""result"", Float (Result))";
      else
         --  Enumeration or other scalar: use 'Image as a string value.
         return "Set_Field (Obj, ""result"", Result'Image)";
      end if;
   end Json_Set_Field;

   --  ---------------------------------------------------------------
   --  Schema generation from declared types
   --  ---------------------------------------------------------------

   --  $ref to a named schema in components/schemas
   function Schema_Ref (Name : String) return String is
   begin
      return "{""$ref"":""#/components/schemas/" & Name & """}";
   end Schema_Ref;

   function Schema_For_Record
     (T     : Mia.Model.Type_Spec;
      Types : Mia.Model.Type_Vectors.Vector)
      return String
   is
      J     : Unbounded_String;
      First : Boolean := True;

      --  Emit own fields + _links as a plain object properties block
      procedure Append_Own_Properties is
      begin
         for F of T.Fields loop
            declare
               F_Name : constant String :=
                          To_Lower (To_String (F.Name));
               F_Type : constant String := To_String (F.Type_Name);
            begin
               if not First then
                  Append (J, ",");
               end if;
               First := False;
               Append (J, """" & F_Name & """:");
               Append (J, Schema_For_Type (F_Type, Types));
            end;
         end loop;
         if not T.Links.Is_Empty then
            if not First then
               Append (J, ",");
            end if;
            Append (J, """_links"":{"
                    & """type"":""object"","
                    & """properties"":{");
            declare
               First_Link : Boolean := True;
            begin
               for Lnk of T.Links loop
                  if not First_Link then
                     Append (J, ",");
                  end if;
                  First_Link := False;
                  Append
                    (J, """"
                     & To_Lower (To_String (Lnk.Name))
                     & """:{""type"":""object"","
                     & """properties"":{""href"":"
                     & "{""type"":""string""}}}");
               end loop;
            end;
            Append (J, "}}");
         end if;
      end Append_Own_Properties;

      Has_Par : constant Boolean := Length (T.Parent) > 0;
      Vtag    : constant String  := To_Lower (To_String (T.Variant_Tag));

   begin
      if Has_Par then
         --  Derived type: allOf[parent_ref, {kind_field + own_fields}]
         declare
            Par_Short : constant String :=
                          Short_Name (To_String (T.Parent));
         begin
            Append (J, "{""allOf"":[");
            Append (J, Schema_Ref (Par_Short) & ",");
            Append (J, "{""type"":""object"",""properties"":{");
            if Vtag /= "" then
               --  Concrete leaf: add kind enum as first property
               Append (J, """kind"":{""type"":""string"","
                       & """enum"":[""" & Vtag & """]}");
               First := False;
            end if;
            Append_Own_Properties;
            Append (J, "}}]}");
         end;
      else
         --  Root type (plain or abstract root): flat object
         Append (J, "{""type"":""object"",""properties"":{");
         Append_Own_Properties;
         Append (J, "}}");
      end if;
      return To_String (J);
   end Schema_For_Record;

   --  oneOf all concrete subtypes of Type_Name, with discriminator
   function Schema_For_OneOf
     (Type_Name : String;
      Types     : Mia.Model.Type_Vectors.Vector)
      return String
   is
      use type Mia.Model.Type_Kind;
      J     : Unbounded_String;
      First : Boolean := True;

      procedure Collect (Name : String) is
         Short : constant String := Short_Name (Name);
      begin
         for T of Types loop
            if T.Kind = Mia.Model.Record_Type then
               declare
                  P : constant String := To_String (T.Parent);
               begin
                  if P = Name or else Short_Name (P) = Short
                    or else P = Short or else Short_Name (P) = Name
                  then
                     if Length (T.Variant_Tag) > 0 then
                        if not First then
                           Append (J, ",");
                        end if;
                        First := False;
                        Append
                          (J, Schema_Ref
                                (Short_Name (To_String (T.Name))));
                     else
                        Collect (To_String (T.Name));
                     end if;
                  end if;
               end;
            end if;
         end loop;
      end Collect;

   begin
      Append (J, "{""oneOf"":[");
      Collect (Type_Name);
      Append (J, "],""discriminator"":{""propertyName"":""kind""}}");
      return To_String (J);
   end Schema_For_OneOf;

   function Schema_For_Type
     (Type_Name : String;
      Types     : Mia.Model.Type_Vectors.Vector)
      return String
   is
      use Mia.Model;
   begin
      for T of Types loop
         declare
            Full : constant String := To_String (T.Name);
         begin
            if Full = Type_Name or else Short_Name (Full) = Type_Name then
               case T.Kind is
                  --  Enum literals are unknown at code-gen time; the
                  --  schema is built and registered at runtime, so only
                  --  reference it here.
                  when Enum_Type   => return Schema_Ref (Short_Name (Full));
                  when Record_Type => return Schema_For_Record (T, Types);
               end case;
            end if;
         end;
      end loop;
      return "{""type"":""" & Json_Schema_Type (Type_Name) & """}";
   end Schema_For_Type;

   --  ---------------------------------------------------------------
   --  Spec file
   --  ---------------------------------------------------------------

   procedure Write_Spec
     (Pkg        : String;
      Output_Dir : String;
      File_Base  : String)
   is
      File : Ada.Text_IO.File_Type;
      Path : constant String :=
               Ada.Directories.Compose (Output_Dir, File_Base, "ads");
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line
        (File, "package " & Pkg & ".Server is");
      Ada.Text_IO.New_Line (File);
      Ada.Text_IO.Put_Line
        (File,
         "   procedure Register (Prefix : String := """");");
      Ada.Text_IO.New_Line (File);
      Ada.Text_IO.Put_Line (File, "end " & Pkg & ".Server;");
      Ada.Text_IO.Close (File);
   end Write_Spec;

   --  ---------------------------------------------------------------
   --  Body file
   --  ---------------------------------------------------------------

   procedure Write_Body
     (Spec       : Mia.Model.Package_Spec;
      Pkg        : String;
      Output_Dir : String;
      File_Base  : String)
   is
      use Mia.Model;

      File           : Ada.Text_IO.File_Type;
      Path           : constant String :=
                         Ada.Directories.Compose
                           (Output_Dir, File_Base, "adb");
      Withs          : String_Sets.Set;
      Session_Type_S : constant String := To_String (Spec.Session_Type);
      Needs_Prefix   : Boolean := False;

      function Fn_Needs_Auth (Fn : Mia.Model.Function_Spec) return Boolean is
      begin
         return Session_Type_S /= ""
           and then Fn.Auth /= Mia.Model.Anonymous;
      end Fn_Needs_Auth;

      function Return_Type_Has_Links (Type_Name : String) return Boolean is
      begin
         for T of Spec.Types loop
            declare
               Full : constant String := To_String (T.Name);
            begin
               if (Full = Type_Name
                   or else Short_Name (Full) = Type_Name)
                 and then not T.Links.Is_Empty
               then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Return_Type_Has_Links;

      function Return_Type_Is_Abstract (Type_Name : String) return Boolean is
         use type Mia.Model.Type_Kind;

         function Has_Subtypes (Name : String) return Boolean is
            Short : constant String := Short_Name (Name);
         begin
            for T of Spec.Types loop
               if T.Kind = Mia.Model.Record_Type then
                  declare
                     P : constant String := To_String (T.Parent);
                  begin
                     if P = Name or else P = Short
                       or else Short_Name (P) = Short
                     then
                        return True;
                     end if;
                  end;
               end if;
            end loop;
            return False;
         end Has_Subtypes;

      begin
         for T of Spec.Types loop
            if T.Kind = Mia.Model.Record_Type then
               declare
                  Full : constant String := To_String (T.Name);
               begin
                  if Full = Type_Name or else Short_Name (Full) = Type_Name then
                     return Length (T.Variant_Tag) = 0
                       and then (Length (T.Parent) > 0
                                 or else Has_Subtypes (Full));
                  end if;
               end;
            end if;
         end loop;
         return False;
      end Return_Type_Is_Abstract;

      procedure Collect_Withs is
         procedure Add (Dotted : String) is
            Pkg : constant String := Impl_Package (Dotted);
         begin
            if Pkg /= "" then
               String_Sets.Include (Withs, To_Unbounded_String (Pkg));
            end if;
         end Add;
      begin
         Add (Session_Type_S);
         for T of Spec.Types loop
            Add (To_String (T.To_Json));
            --  External enum types live in their declaring Ada package,
            --  needed for the runtime schema-building loop in Register.
            if T.Kind = Mia.Model.Enum_Type then
               Add (To_String (T.Name));
            end if;
         end loop;
         for F of Spec.Functions loop
            Add (To_String (F.Impl));
            Add (To_String (F.Scanner));
            Add (To_String (F.To_Json));
            Add (To_String (F.From_Json));
            Add (To_String (F.Body_Schema));
            Add (Resolve_Type (To_String (F.Return_Type), Spec.Types));
            for P of F.Parameters loop
               Add (Resolve_Type (To_String (P.Type_Name), Spec.Types));
            end loop;
         end loop;
      end Collect_Withs;

      procedure Pl (S : String) is
      begin
         Ada.Text_IO.Put_Line (File, S);
      end Pl;

      --  Emit a GNAT-style separator comment block for a subprogram.
      procedure Separator (Name : String) is
         Dashes : constant String (1 .. Name'Length + 6) :=
                    (others => '-');
      begin
         Pl ("   " & Dashes);
         Pl ("   -- " & Name & " --");
         Pl ("   " & Dashes);
         Ada.Text_IO.New_Line (File);
      end Separator;

      --  All concrete subtypes of Type_Name in this spec
      function Concrete_Subtypes
        (Type_Name : String) return Mia.Model.Type_Vectors.Vector
      is
         Result : Type_Vectors.Vector;

         procedure Collect (Name : String) is
            Short : constant String := Short_Name (Name);
         begin
            for T of Spec.Types loop
               if T.Kind = Record_Type then
                  declare
                     P : constant String := To_String (T.Parent);
                  begin
                     if P = Name or else Short_Name (P) = Name
                       or else P = Short or else Short_Name (P) = Short
                     then
                        if Length (T.Variant_Tag) > 0 then
                           Result.Append (T);
                        else
                           --  Intermediate: recurse into its subtypes
                           Collect (To_String (T.Name));
                        end if;
                     end if;
                  end;
               end if;
            end loop;
         end Collect;

      begin
         Collect (Type_Name);
         return Result;
      end Concrete_Subtypes;

      --  True when any record type in this spec names Type_Name as its
      --  parent (i.e. Type_Name is the root or an intermediate of a
      --  tagged-derivation hierarchy), regardless of Variant_Tag.
      function Has_Subtypes (Type_Name : String) return Boolean is
         Short : constant String := Short_Name (Type_Name);
      begin
         for T of Spec.Types loop
            if T.Kind = Record_Type then
               declare
                  P : constant String := To_String (T.Parent);
               begin
                  if P = Type_Name or else P = Short
                    or else Short_Name (P) = Short
                  then
                     return True;
                  end if;
               end;
            end if;
         end loop;
         return False;
      end Has_Subtypes;

      procedure Write_Array_Handler (Fn : Mia.Model.Function_Spec);

      procedure Write_Handler_Spec (Fn : Mia.Model.Function_Spec) is
         Handler_Name : constant String := "Handle_" & To_String (Fn.Name);
      begin
         Pl ("   function " & Handler_Name);
         Pl ("     (Session_Id : String;");
         Pl ("      URI        : String;");
         Pl ("      Parameters : Mia.Server.Service_Parameters)");
         Pl ("      return AWS.Response.Data;");
         Ada.Text_IO.New_Line (File);
      end Write_Handler_Spec;

      procedure Write_Handler (Fn : Mia.Model.Function_Spec) is
         Fn_Name      : constant String  := To_String (Fn.Name);
         Ret_Type     : constant String  :=
                          Resolve_Type
                            (To_String (Fn.Return_Type), Spec.Types);
         Path_Tmpl    : constant String  := To_String (Fn.Path);
         Impl_Name    : constant String  := To_String (Fn.Impl);
         To_Json_Fn   : constant String  :=
                          Resolve_To_Json (Ret_Type, Fn, Spec.Types);
         Has_To_Json  : constant Boolean := To_Json_Fn /= "";
         Has_Links    : constant Boolean :=
                          Return_Type_Has_Links (Ret_Type);
         Has_Session  : constant Boolean := Fn_Needs_Auth (Fn);
         Handler_Name : constant String  := "Handle_" & Fn_Name;

         procedure Put_Sig is
         begin
            Pl ("   function " & Handler_Name);
            Pl ("     (Session_Id : String;");
            Pl ("      URI        : String;");
            Pl ("      Parameters : Mia.Server.Service_Parameters)");
            Pl ("      return AWS.Response.Data");
         end Put_Sig;

         procedure Emit_Params (Indent : String) is
            From_Body_Name : constant String :=
                               To_Lower (To_String (Fn.From_Body));
            From_Json_Name : constant String :=
                               To_String (Fn.From_Json);
         begin
            for P of Fn.Parameters loop
               declare
                  P_Name : constant String := To_String (P.Name);
                  P_Type : constant String :=
                             Resolve_Type
                               (To_String (P.Type_Name), Spec.Types);
               begin
                  if From_Body_Name /= ""
                    and then To_Lower (P_Name) = From_Body_Name
                  then
                     Pl (Indent & P_Name
                         & " : constant " & P_Type & " :=");
                     Pl (Indent & "            "
                         & From_Json_Name
                         & " (Parameters.Value (""__body__""));");
                  else
                     declare
                        Key : constant String :=
                                Placeholder_Of (Path_Tmpl, P_Name);
                     begin
                        if To_Lower (P_Type) = "string" then
                           Pl (Indent & P_Name
                               & " : constant String :=");
                           Pl (Indent & "            "
                               & "Parameters.Value ("""
                               & Key & """);");
                        else
                           Pl (Indent & P_Name
                               & " : constant " & P_Type & " :=");
                           Pl (Indent & "            "
                               & P_Type
                               & "'Value (Parameters.Value ("""
                               & Key & """));");
                        end if;
                     end;
                  end if;
               end;
            end loop;
         end Emit_Params;

      begin
         if Length (Fn.From_Body) > 0
           and then Fn.Method = Mia.Model.Get
         then
            raise Generator_Error
              with "From_Body cannot be used with GET: " & Fn_Name;
         end if;

         Separator (Handler_Name);

         Put_Sig;
         Pl ("   is");

         if Has_Session then
            Pl ("      pragma Unreferenced (URI"
                & (if Parameter_Vectors.Is_Empty (Fn.Parameters)
                   then ", Parameters" else "") & ");");
            Ada.Text_IO.New_Line (File);
            Pl ("      Raw : constant access"
                & " Mia.Sessions.Session_Interface'Class :=");
            Pl ("              Mia.Sessions.Get (Session_Id);");
            Pl ("   begin");
            Pl ("      if Raw = null then");
            Pl ("         return AWS.Response.Build");
            Pl ("           (""application/json"",");
            Pl ("            "
                & Ada_Lit ("{""error"":""unauthorized""}") & ",");
            Pl ("            AWS.Messages.S401);");
            Pl ("      end if;");
            Pl ("      declare");
            if not Has_To_Json then
               Pl ("         use GNATCOLL.JSON;");
               Ada.Text_IO.New_Line (File);
            end if;
            Pl ("         Session : constant Session_Reference :=");
            Pl ("                     Session_Reference (Raw);");
            Emit_Params ("         ");
            Pl ("         Result : constant "
                & (if Return_Type_Is_Abstract (Ret_Type)
                   then Ret_Type & "'Class"
                   else Ret_Type)
                & " :=");
            declare
               Call : Unbounded_String :=
                        To_Unbounded_String
                          ("                   " & Impl_Name
                           & " (Session");
            begin
               for P of Fn.Parameters loop
                  Append (Call, ", ");
                  Append (Call, To_String (P.Name));
               end loop;
               Append (Call, ");");
               Pl (To_String (Call));
            end;
            if not Has_To_Json then
               Pl ("         Obj : constant JSON_Value"
                   & " := Create_Object;");
            end if;
            Pl ("      begin");
            if Has_To_Json then
               Pl ("         declare");
               Pl ("            S : constant String :=");
               if Has_Links then
                  Pl ("                     " & To_Json_Fn & " (Result,");
                  Pl ("                       Ada.Strings.Unbounded"
                      & ".To_String (Registered_Prefix));");
               else
                  Pl ("                     " & To_Json_Fn & " (Result);");
               end if;
               Pl ("         begin");
               Pl ("            return AWS.Response.Build");
               Pl ("              (""application/json"", S);");
               Pl ("         end;");
            else
               Pl ("         " & Json_Set_Field (Ret_Type) & ";");
               Ada.Text_IO.New_Line (File);
               Pl ("         declare");
               Pl ("            S : constant String := Write (Obj);");
               Pl ("         begin");
               Pl ("            return AWS.Response.Build");
               Pl ("              (""application/json"", S);");
               Pl ("         end;");
            end if;
            Pl ("      end;");

         else
            Pl ("      pragma Unreferenced (Session_Id, URI"
                & (if Parameter_Vectors.Is_Empty (Fn.Parameters)
                   then ", Parameters" else "") & ");");
            if not Has_To_Json then
               Pl ("      use GNATCOLL.JSON;");
            end if;
            Ada.Text_IO.New_Line (File);
            Emit_Params ("      ");
            Pl ("      Result : constant "
                & (if Return_Type_Is_Abstract (Ret_Type)
                   then Ret_Type & "'Class"
                   else Ret_Type)
                & " :=");
            declare
               Call : Unbounded_String :=
                        To_Unbounded_String
                          ("                 " & Impl_Name);
            begin
               if not Mia.Model.Parameter_Vectors.Is_Empty
                        (Fn.Parameters)
               then
                  Append (Call, " (");
                  for I in Fn.Parameters.First_Index
                           .. Fn.Parameters.Last_Index
                  loop
                     if I > Fn.Parameters.First_Index then
                        Append (Call, ", ");
                     end if;
                     Append (Call,
                             To_String
                               (Fn.Parameters.Element (I).Name));
                  end loop;
                  Append (Call, ")");
               end if;
               Append (Call, ";");
               Pl (To_String (Call));
            end;
            if not Has_To_Json then
               Pl ("      Obj    : constant JSON_Value"
                   & " := Create_Object;");
            end if;
            Pl ("   begin");
            if Has_To_Json then
               Pl ("      declare");
               Pl ("         S : constant String :=");
               if Has_Links then
                  Pl ("                  " & To_Json_Fn & " (Result,");
                  Pl ("                    Ada.Strings.Unbounded"
                      & ".To_String (Registered_Prefix));");
               else
                  Pl ("                  " & To_Json_Fn & " (Result);");
               end if;
               Pl ("      begin");
               Pl ("         return AWS.Response.Build");
               Pl ("           (""application/json"", S);");
               Pl ("      end;");
            else
               Pl ("      " & Json_Set_Field (Ret_Type) & ";");
               Ada.Text_IO.New_Line (File);
               Pl ("      declare");
               Pl ("         S : constant String := Write (Obj);");
               Pl ("      begin");
               Pl ("         return AWS.Response.Build");
               Pl ("           (""application/json"", S);");
               Pl ("      end;");
            end if;
         end if;

         Pl ("   end " & Handler_Name & ";");
         Ada.Text_IO.New_Line (File);
      end Write_Handler;

      procedure Write_Array_Handler (Fn : Mia.Model.Function_Spec) is
         Fn_Name      : constant String  := To_String (Fn.Name);
         Elem_Type    : constant String  :=
                          Resolve_Type
                            (To_String (Fn.Return_Type), Spec.Types);
         Scanner_Name : constant String  := To_String (Fn.Scanner);
         To_Json_Fn        : constant String  :=
                               Resolve_To_Json (Elem_Type, Fn, Spec.Types);
         Elem_Has_Links    : constant Boolean :=
                               Return_Type_Has_Links (Elem_Type);
         Elem_Polymorphic  : constant Boolean :=
                               not Concrete_Subtypes (Elem_Type).Is_Empty
                               or else Has_Subtypes (Elem_Type);
         Cb_Elem_Type      : constant String :=
                               (if Elem_Polymorphic
                                then Elem_Type & "'Class"
                                else Elem_Type);
         Has_Session       : constant Boolean := Fn_Needs_Auth (Fn);
         Handler_Name : constant String  := "Handle_" & Fn_Name;
         Path_Tmpl    : constant String  := To_String (Fn.Path);

         procedure Put_Sig is
         begin
            Pl ("   function " & Handler_Name);
            Pl ("     (Session_Id : String;");
            Pl ("      URI        : String;");
            Pl ("      Parameters : Mia.Server.Service_Parameters)");
            Pl ("      return AWS.Response.Data");
         end Put_Sig;

         procedure Emit_Params (Indent : String) is
         begin
            for P of Fn.Parameters loop
               declare
                  P_Name : constant String := To_String (P.Name);
                  P_Type : constant String :=
                             Resolve_Type
                               (To_String (P.Type_Name), Spec.Types);
                  Key    : constant String :=
                             Placeholder_Of (Path_Tmpl, P_Name);
               begin
                  if To_Lower (P_Type) = "string" then
                     Pl (Indent & P_Name & " : constant String :=");
                     Pl (Indent & "            "
                         & "Parameters.Value (""" & Key & """);");
                  else
                     Pl (Indent & P_Name
                         & " : constant " & P_Type & " :=");
                     Pl (Indent & "            "
                         & P_Type
                         & "'Value (Parameters.Value ("""
                         & Key & """));");
                  end if;
               end;
            end loop;
         end Emit_Params;

         procedure Emit_Scanner_Call (Indent : String) is
            Call : Unbounded_String :=
                     To_Unbounded_String (Indent & Scanner_Name & " (");
            First : Boolean := True;
         begin
            if Has_Session then
               Append (Call, "Session");
               First := False;
            end if;
            for I in Fn.Parameters.First_Index .. Fn.Parameters.Last_Index
            loop
               if not First then
                  Append (Call, ", ");
               end if;
               First := False;
               Append (Call, To_String (Fn.Parameters.Element (I).Name));
            end loop;
            if not First then
               Append (Call, ", ");
            end if;
            Append (Call, "Cb'Access);");
            Pl (To_String (Call));
         end Emit_Scanner_Call;

         procedure Emit_Cb_And_Tail (Indent : String) is
         begin
            Pl (Indent & "Items : GNATCOLL.JSON.JSON_Array;");
            Ada.Text_IO.New_Line (File);
            Pl (Indent & "procedure Cb (Element : "
                & Cb_Elem_Type & ") is");
            Pl (Indent & "begin");
            if To_Json_Fn /= "" then
               Pl (Indent & "   GNATCOLL.JSON.Append");
               Pl (Indent & "     (Items,");
               if Elem_Has_Links or else Elem_Polymorphic then
                  Pl (Indent & "      GNATCOLL.JSON.Read");
                  Pl (Indent & "        (" & To_Json_Fn & " (Element,");
                  Pl (Indent & "         Ada.Strings.Unbounded"
                      & ".To_String (Registered_Prefix))));");
               else
                  Pl (Indent & "      GNATCOLL.JSON.Read"
                      & " (" & To_Json_Fn & " (Element)));");
               end if;
            else
               Pl (Indent & "   GNATCOLL.JSON.Append");
               Pl (Indent & "     (Items, GNATCOLL.JSON.Create (Element));");
            end if;
            Pl (Indent & "end Cb;");
         end Emit_Cb_And_Tail;

      begin
         if To_Json_Fn = "" then
            raise Generator_Error
              with "array return type requires To_Json on element type: "
                   & Elem_Type;
         end if;

         Separator (Handler_Name);
         Put_Sig;
         Pl ("   is");

         if Has_Session then
            Pl ("      pragma Unreferenced (URI"
                & (if Parameter_Vectors.Is_Empty (Fn.Parameters)
                   then ", Parameters" else "") & ");");
            Ada.Text_IO.New_Line (File);
            Pl ("      Raw : constant access"
                & " Mia.Sessions.Session_Interface'Class :=");
            Pl ("              Mia.Sessions.Get (Session_Id);");
            Pl ("   begin");
            Pl ("      if Raw = null then");
            Pl ("         return AWS.Response.Build");
            Pl ("           (""application/json"",");
            Pl ("            "
                & Ada_Lit ("{""error"":""unauthorized""}") & ",");
            Pl ("            AWS.Messages.S401);");
            Pl ("      end if;");
            Pl ("      declare");
            Pl ("         Session : constant Session_Reference :=");
            Pl ("                     Session_Reference (Raw);");
            Emit_Params ("         ");
            Emit_Cb_And_Tail ("         ");
            Pl ("      begin");
            Emit_Scanner_Call ("         ");
            Pl ("         declare");
            Pl ("            S : constant String :=");
            Pl ("                  GNATCOLL.JSON.Write");
            Pl ("                    (GNATCOLL.JSON.Create (Items));");
            Pl ("         begin");
            Pl ("            return AWS.Response.Build");
            Pl ("              (""application/json"", S);");
            Pl ("         end;");
            Pl ("      end;");
         else
            Pl ("      pragma Unreferenced (Session_Id, URI"
                & (if Parameter_Vectors.Is_Empty (Fn.Parameters)
                   then ", Parameters" else "") & ");");
            Ada.Text_IO.New_Line (File);
            Emit_Params ("      ");
            Emit_Cb_And_Tail ("      ");
            Pl ("   begin");
            Emit_Scanner_Call ("      ");
            Pl ("      declare");
            Pl ("         S : constant String :=");
            Pl ("               GNATCOLL.JSON.Write");
            Pl ("                 (GNATCOLL.JSON.Create (Items));");
            Pl ("      begin");
            Pl ("         return AWS.Response.Build");
            Pl ("           (""application/json"", S);");
            Pl ("      end;");
         end if;

         Pl ("   end " & Handler_Name & ";");
         Ada.Text_IO.New_Line (File);
      end Write_Array_Handler;

   begin
      Collect_Withs;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);

      Pl ("with AWS.Response;");
      Pl ("with AWS.Status;");
      declare
         Needs_Json    : Boolean := False;
         Needs_Session : Boolean := False;
         Has_Enums     : constant Boolean :=
                           (for some T of Spec.Types =>
                              T.Kind = Mia.Model.Enum_Type);
      begin
         for Fn of Spec.Functions loop
            if Fn.Is_Array
              or else Resolve_To_Json
                        (Resolve_Type (To_String (Fn.Return_Type),
                                       Spec.Types),
                         Fn, Spec.Types) = ""
            then
               Needs_Json := True;
            end if;
            if Fn_Needs_Auth (Fn) then
               Needs_Session := True;
            end if;
            declare
               Elem : constant String :=
                        Resolve_Type
                          (To_String (Fn.Return_Type), Spec.Types);
            begin
               if Return_Type_Has_Links (Elem)
                 or else not Concrete_Subtypes (Elem).Is_Empty
                 or else Has_Subtypes (Elem)
               then
                  Needs_Prefix := True;
               end if;
            end;
         end loop;
         if Needs_Json then
            Pl ("with GNATCOLL.JSON;");
         end if;
         if Needs_Session then
            Pl ("with AWS.Messages;");
            Pl ("with Mia.Sessions;");
         end if;
         if Needs_Prefix or else Has_Enums then
            Pl ("with Ada.Strings.Unbounded;");
         end if;
         --  Runtime enum schema building lowercases T'Image.
         if Has_Enums then
            Pl ("with Ada.Characters.Handling;");
         end if;
      end;
      for W of Withs loop
         Pl ("with " & To_String (W) & ";");
      end loop;
      Pl ("with Mia.Registry;");
      Pl ("with Mia.Server;");
      Ada.Text_IO.New_Line (File);
      Pl ("package body " & Pkg & ".Server is");
      Ada.Text_IO.New_Line (File);
      Pl ("   pragma Style_Checks (""-M"");");
      Ada.Text_IO.New_Line (File);
      if Session_Type_S /= "" then
         Pl ("   type Session_Reference is");
         Pl ("     not null access all " & Session_Type_S & "'Class;");
         Ada.Text_IO.New_Line (File);
      end if;
      if Needs_Prefix then
         Pl ("   Registered_Prefix :"
             & " Ada.Strings.Unbounded.Unbounded_String;");
         Ada.Text_IO.New_Line (File);
      end if;

      for Fn of Spec.Functions loop
         Write_Handler_Spec (Fn);
      end loop;
      for Fn of Spec.Functions loop
         if Fn.Is_Array then
            Write_Array_Handler (Fn);
         else
            Write_Handler (Fn);
         end if;
      end loop;

      Separator ("Register");
      Pl ("   procedure Register (Prefix : String := """") is");
      Pl ("   begin");
      if Needs_Prefix then
         Pl ("      Registered_Prefix :=");
         Pl ("        Ada.Strings.Unbounded"
             & ".To_Unbounded_String (Prefix);");
      end if;
      --  Register named schemas for record types in the spec
      for T of Spec.Types loop
         if T.Kind = Mia.Model.Record_Type then
            declare
               T_Short  : constant String :=
                            Short_Name (To_String (T.Name));
               T_Schema : constant String :=
                            Schema_For_Record (T, Spec.Types);
            begin
               Pl ("      Mia.Registry.Register_Schema");
               Pl ("        (""" & T_Short & """,");
               Pl ("         " & Ada_Lit (T_Schema) & ");");
            end;
         end if;
      end loop;
      --  Register string-enum schemas for external enum types, building the
      --  literal list at runtime from the type's attributes.
      for T of Spec.Types loop
         if T.Kind = Mia.Model.Enum_Type then
            declare
               Q : constant String := To_String (T.Name);
               S : constant String := Short_Name (Q);
            begin
               Pl ("      declare");
               Pl ("         use type " & Q & ";");
               Pl ("         Buf   : Ada.Strings.Unbounded"
                   & ".Unbounded_String;");
               Pl ("         Item  : " & Q & " := " & Q & "'First;");
               Pl ("         First : Boolean := True;");
               Pl ("      begin");
               Pl ("         Ada.Strings.Unbounded.Append");
               Pl ("           (Buf, ""{""""type"""":""""string"""","
                   & """""enum"""":["");");
               Pl ("         loop");
               Pl ("            if not First then");
               Pl ("               Ada.Strings.Unbounded.Append"
                   & " (Buf, "","");");
               Pl ("            end if;");
               Pl ("            First := False;");
               Pl ("            Ada.Strings.Unbounded.Append");
               Pl ("              (Buf, '""' & Ada.Characters.Handling"
                   & ".To_Lower");
               Pl ("                       (" & Q
                   & "'Image (Item)) & '""');");
               Pl ("            exit when Item = " & Q & "'Last;");
               Pl ("            Item := " & Q & "'Succ (Item);");
               Pl ("         end loop;");
               Pl ("         Ada.Strings.Unbounded.Append (Buf, ""]}"");");
               Pl ("         Mia.Registry.Register_Schema");
               Pl ("           (""" & S
                   & """, Ada.Strings.Unbounded.To_String (Buf));");
               Pl ("      end;");
            end;
         end if;
      end loop;
      for Fn of Spec.Functions loop
         declare
            Fn_Name   : constant String  := To_String (Fn.Name);
            Template  : constant String  := To_String (Fn.Path);
            Method_S  : constant String  := Method_Status (Fn.Method);
            Params_J  : constant String  := Build_Params_Json (Fn);
            Anon      : constant Boolean := not Fn_Needs_Auth (Fn);
            Schema_Fn : constant String  := To_String (Fn.Body_Schema);
         begin
            Pl ("      Mia.Server.Register");
            Pl ("        (Route           => Prefix & ""/"
                & Template & """,");
            Pl ("         Handler         => Handle_"
                & Fn_Name & "'Access,");
            Pl ("         Method          => " & Method_S & ",");
            Pl ("         Allow_Anonymous => "
                & (if Anon then "True" else "False") & ");");
            Pl ("      Mia.Registry.Register_Route");
            Pl ("        (Path        => Prefix & ""/"
                & Template & """,");
            Pl ("         Method      => """
                & Method_Image (Fn.Method) & """,");
            Pl ("         Operation   => """ & Fn_Name & """,");
            Pl ("         Path_Params     => "
                & Ada_Lit (Params_J) & ",");
            declare
               Elem_Type_S  : constant String :=
                                Resolve_Type
                                  (To_String (Fn.Return_Type), Spec.Types);
               Is_Poly      : constant Boolean :=
                                not (for all T of Spec.Types =>
                                       T.Kind /= Mia.Model.Record_Type
                                       or else Length (T.Parent) = 0
                                       or else (To_String (T.Parent)
                                                  /= Elem_Type_S
                                                and then
                                                Short_Name
                                                  (To_String (T.Parent))
                                                  /= Short_Name
                                                       (Elem_Type_S)));
               --  Use $ref for named schemas; inline for scalars
               Is_Named     : constant Boolean :=
                                Schema_For_Type (Elem_Type_S, Spec.Types)
                                  /= "{""type"":"""
                                     & Json_Schema_Type (Elem_Type_S)
                                     & """}";
               Elem_Schema  : constant String :=
                                (if Is_Poly
                                 then Schema_For_OneOf
                                        (Elem_Type_S, Spec.Types)
                                 elsif Is_Named
                                 then Schema_Ref
                                        (Short_Name (Elem_Type_S))
                                 else Schema_For_Type
                                        (Elem_Type_S, Spec.Types));
               Has_To_Json  : constant Boolean :=
                                Resolve_To_Json
                                  (Elem_Type_S, Fn, Spec.Types) /= "";
               Ret_Schema   : constant String :=
                                Ada_Lit
                                  (if Fn.Is_Array then
                                     "{""type"":""array"",""items"":"
                                     & Elem_Schema & "}"
                                   elsif Has_To_Json or else Is_Poly then
                                     Elem_Schema
                                   else
                                     "{""type"":""object"","
                                     & """properties"":{"
                                     & """result"":"
                                     & Elem_Schema & "}}");
            begin
               if Schema_Fn /= "" then
                  Pl ("         Result_Schema   => " & Ret_Schema & ",");
                  Pl ("         Allow_Anonymous => "
                      & (if Anon then "True" else "False") & ",");
                  Pl ("         Body_Schema     => "
                      & Ada_Lit
                          (Schema_For_Type (Schema_Fn, Spec.Types))
                      & ");");
               else
                  Pl ("         Result_Schema   => " & Ret_Schema & ",");
                  Pl ("         Allow_Anonymous => "
                      & (if Anon then "True" else "False") & ");");
               end if;
            end;
         end;
      end loop;
      Pl ("   end Register;");
      Ada.Text_IO.New_Line (File);
      Pl ("end " & Pkg & ".Server;");

      Ada.Text_IO.Close (File);
   end Write_Body;

   --  ---------------------------------------------------------------
   --  Type package generation
   --  ---------------------------------------------------------------

   procedure Write_Type_Package
     (Spec       : Mia.Model.Package_Spec;
      Pkg_Name   : String;
      Output_Dir : String)
   is
      use Mia.Model;

      File_Base : constant String := Package_To_File (Pkg_Name);

      --  True when the field type is Ada String (stored as Unbounded_String)
      function Is_String_Field (Field_Type : String) return Boolean is
      begin
         return To_Lower (Field_Type) = "string";
      end Is_String_Field;

      function Is_Float_Field (Field_Type : String) return Boolean is
         Lower : constant String := To_Lower (Field_Type);
      begin
         return Lower = "float" or else Lower = "long_float";
      end Is_Float_Field;

      function Is_Bool_Field (Field_Type : String) return Boolean is
      begin
         return To_Lower (Field_Type) = "boolean";
      end Is_Bool_Field;

      function Is_Int_Field (Field_Type : String) return Boolean is
         Lower : constant String := To_Lower (Field_Type);
      begin
         return Lower = "integer"
           or else Lower = "positive"
           or else Lower = "natural";
      end Is_Int_Field;

      --  True when the field type names a declared (external) enum type
      function Is_Enum_Field (Field_Type : String) return Boolean is
      begin
         for T of Spec.Types loop
            if T.Kind = Enum_Type then
               declare
                  Full : constant String := To_String (T.Name);
               begin
                  if Full = Field_Type
                    or else Short_Name (Full) = Field_Type
                  then
                     return True;
                  end if;
               end;
            end if;
         end loop;
         return False;
      end Is_Enum_Field;

      --  Ada type used in signatures (accessors, Create params); enum
      --  fields resolve to their fully-qualified declaring name.
      function Field_Ada_Type (Field_Type : String) return String is
      begin
         if Is_Enum_Field (Field_Type) then
            return Resolve_Type (Field_Type, Spec.Types);
         else
            return Field_Type;
         end if;
      end Field_Ada_Type;

      --  Storage type used in the private record body
      function Storage_Type (Field_Type : String) return String is
      begin
         if Is_String_Field (Field_Type) then
            return "Ada.Strings.Unbounded.Unbounded_String";
         else
            return Field_Ada_Type (Field_Type);
         end if;
      end Storage_Type;

      --  True when the type belongs to the package being generated
      function Type_In_Pkg (T : Type_Spec) return Boolean is
      begin
         return T.Kind = Record_Type
           and then Impl_Package (To_String (T.Name)) = Pkg_Name;
      end Type_In_Pkg;

      --  True when any function returns this type (direct or array element)
      function Type_Needs_To_Json (Full_Name : String) return Boolean is
         Short : constant String := Short_Name (Full_Name);
      begin
         for Fn of Spec.Functions loop
            declare
               Ret : constant String := To_String (Fn.Return_Type);
            begin
               if Ret = Full_Name or else Ret = Short then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Type_Needs_To_Json;

      --  True when any function takes this type as a parameter
      function Type_Needs_From_Json (Full_Name : String) return Boolean is
         Short : constant String := Short_Name (Full_Name);
      begin
         for Fn of Spec.Functions loop
            for P of Fn.Parameters loop
               declare
                  Pt : constant String := To_String (P.Type_Name);
               begin
                  if Pt = Full_Name or else Pt = Short then
                     return True;
                  end if;
               end;
            end loop;
         end loop;
         return False;
      end Type_Needs_From_Json;

      function Is_Concrete (T : Type_Spec) return Boolean is
      begin
         return T.Kind = Record_Type
           and then Length (T.Variant_Tag) > 0;
      end Is_Concrete;

      --  Topological sort: parents before children
      function Sorted_Types return Type_Vectors.Vector is
         Result  : Type_Vectors.Vector;
         Emitted : String_Sets.Set;
         Changed : Boolean;
      begin
         --  Roots first: no parent, or parent in a different package
         for T of Spec.Types loop
            if Type_In_Pkg (T) then
               declare
                  P : constant String := To_String (T.Parent);
               begin
                  if P = "" or else Impl_Package (P) /= Pkg_Name then
                     Result.Append (T);
                     String_Sets.Include (Emitted, T.Name);
                  end if;
               end;
            end if;
         end loop;
         --  Iteratively append types whose parent is already emitted
         loop
            Changed := False;
            for T of Spec.Types loop
               if Type_In_Pkg (T)
                 and then not String_Sets.Contains (Emitted, T.Name)
               then
                  declare
                     P : constant String := To_String (T.Parent);
                  begin
                     if P /= ""
                       and then Impl_Package (P) = Pkg_Name
                       and then String_Sets.Contains
                                  (Emitted, T.Parent)
                     then
                        Result.Append (T);
                        String_Sets.Include (Emitted, T.Name);
                        Changed := True;
                     end if;
                  end;
               end if;
            end loop;
            exit when not Changed;
         end loop;
         --  Any remaining type indicates a cycle or missing parent
         for T of Spec.Types loop
            if Type_In_Pkg (T)
              and then not String_Sets.Contains (Emitted, T.Name)
            then
               raise Generator_Error
                 with "type inheritance cycle or unknown parent: "
                      & To_String (T.Name);
            end if;
         end loop;
         return Result;
      end Sorted_Types;

      --  Collect all fields for T, ancestors first, own fields last
      function All_Fields
        (T : Type_Spec) return Type_Field_Vectors.Vector
      is
         Result : Type_Field_Vectors.Vector;

         procedure Add (Current : Type_Spec) is
            P : constant String := To_String (Current.Parent);
         begin
            if P /= "" then
               for Ancestor of Spec.Types loop
                  declare
                     Full : constant String :=
                              To_String (Ancestor.Name);
                  begin
                     if Full = P
                       or else Short_Name (Full) = P
                     then
                        Add (Ancestor);
                        exit;
                     end if;
                  end;
               end loop;
            end if;
            for F of Current.Fields loop
               Result.Append (F);
            end loop;
         end Add;

      begin
         Add (T);
         return Result;
      end All_Fields;

      --  True when any field (own or inherited) needs Fmt_Float
      function Type_Has_Float_Fields (T : Type_Spec) return Boolean is
      begin
         for F of All_Fields (T) loop
            if Is_Float_Field (To_String (F.Type_Name)) then
               return True;
            end if;
         end loop;
         return False;
      end Type_Has_Float_Fields;

      --  True when any field (own or inherited) needs Quote
      function Type_Has_String_Fields (T : Type_Spec) return Boolean is
      begin
         for F of All_Fields (T) loop
            if Is_String_Field (To_String (F.Type_Name)) then
               return True;
            end if;
         end loop;
         return False;
      end Type_Has_String_Fields;

      --  True when any field (own or inherited) is an enum (serialized as
      --  a quoted, lowercased string).
      function Type_Has_Enum_Fields (T : Type_Spec) return Boolean is
      begin
         for F of All_Fields (T) loop
            if Is_Enum_Field (To_String (F.Type_Name)) then
               return True;
            end if;
         end loop;
         return False;
      end Type_Has_Enum_Fields;

      --  Declaring Ada packages of every enum referenced by a field of a
      --  record in this package; needed as with-clauses.
      function Enum_Packages return String_Sets.Set is
         Result : String_Sets.Set;
      begin
         for T of Spec.Types loop
            if Type_In_Pkg (T) then
               for F of All_Fields (T) loop
                  declare
                     FT : constant String := To_String (F.Type_Name);
                  begin
                     if Is_Enum_Field (FT) then
                        declare
                           P : constant String :=
                                 Impl_Package
                                   (Resolve_Type (FT, Spec.Types));
                        begin
                           if P /= "" and then P /= Pkg_Name then
                              String_Sets.Include
                                (Result, To_Unbounded_String (P));
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end if;
         end loop;
         return Result;
      end Enum_Packages;

      --  True when any type in this package has a String field
      function Has_String_Fields return Boolean is
      begin
         for T of Spec.Types loop
            if Type_In_Pkg (T) then
               for F of T.Fields loop
                  if Is_String_Field (To_String (F.Type_Name)) then
                     return True;
                  end if;
               end loop;
            end if;
         end loop;
         return False;
      end Has_String_Fields;

      --  True when any type in this package needs a body
      function Needs_Body return Boolean is
      begin
         for T of Spec.Types loop
            if Type_In_Pkg (T) then
               --  Concrete types always need a To_Json override
               if Is_Concrete (T) then
                  return True;
               end if;
               declare
                  Full : constant String := To_String (T.Name);
               begin
                  if Type_Needs_To_Json (Full)
                    or else Type_Needs_From_Json (Full)
                  then
                     return True;
                  end if;
               end;
            end if;
         end loop;
         return False;
      end Needs_Body;

      --  Return the Path template of a function by name
      function Find_Function_Path (Fn_Name : String) return String is
      begin
         for Fn of Spec.Functions loop
            if To_String (Fn.Name) = Fn_Name then
               return To_String (Fn.Path);
            end if;
         end loop;
         raise Generator_Error
           with "links: unknown function '" & Fn_Name & "'";
      end Find_Function_Path;

      --  Build an Ada string expression for the href of a link.
      --  E.g. path "factions/{faction_name}", binding
      --  Faction_Name => Identifier  =>  "/factions/" & Self.Identifier
      function Build_Href_Expr
        (Template : String;
         Bindings : Binding_Vectors.Vector)
         return String
      is
         Result  : Unbounded_String;
         Literal : Unbounded_String := To_Unbounded_String ("/");
         I       : Positive := Template'First;

         procedure Flush_Literal is
         begin
            if Length (Literal) > 0 then
               if Length (Result) > 0 then
                  Append (Result, " & ");
               end if;
               Append (Result, """" & To_String (Literal) & """");
               Literal := Null_Unbounded_String;
            end if;
         end Flush_Literal;

      begin
         while I <= Template'Last loop
            if Template (I) = '{' then
               declare
                  J : Positive := I + 1;
               begin
                  while J <= Template'Last
                    and then Template (J) /= '}'
                  loop
                     J := J + 1;
                  end loop;
                  declare
                     Key   : constant String :=
                               To_Lower (Template (I + 1 .. J - 1));
                     Found : Boolean := False;
                  begin
                     Flush_Literal;
                     for B of Bindings loop
                        if To_Lower (To_String (B.Param_Name)) = Key
                        then
                           if Length (Result) > 0 then
                              Append (Result, " & ");
                           end if;
                           Append
                             (Result,
                              To_String (B.Field_Name)
                              & " (Self)");
                           Found := True;
                           exit;
                        end if;
                     end loop;
                     if not Found then
                        raise Generator_Error
                          with "links: no binding for path"
                               & " parameter '" & Key & "'";
                     end if;
                     I := J + 1;
                  end;
               end;
            else
               Append (Literal, Template (I));
               I := I + 1;
            end if;
         end loop;
         Flush_Literal;
         return To_String (Result);
      end Build_Href_Expr;

      --  Emit parameter declarations for Create, one line per field
      procedure Emit_Param_List
        (File   : Ada.Text_IO.File_Type;
         Fields : Type_Field_Vectors.Vector)
      is
         Last : constant Natural :=
                  (if Fields.Is_Empty then 0 else Fields.Last_Index);
      begin
         for I in Fields.First_Index .. Fields.Last_Index loop
            declare
               F       : constant Type_Field := Fields.Element (I);
               F_Name  : constant String     := To_String (F.Name);
               F_Type  : constant String     := To_String (F.Type_Name);
               Prefix  : constant String     :=
                           (if I = Fields.First_Index
                            then "     (" else "      ");
               Suffix  : constant String     :=
                           (if I = Last then ")" else ";");
            begin
               Ada.Text_IO.Put_Line
                 (File, Prefix & F_Name & " : "
                        & Field_Ada_Type (F_Type) & Suffix);
            end;
         end loop;
      end Emit_Param_List;

      --  True when any type in this package names T as its parent
      function Has_Subtypes (Full_Name : String) return Boolean is
         Short : constant String := Short_Name (Full_Name);
      begin
         for T of Spec.Types loop
            if Type_In_Pkg (T) then
               declare
                  P : constant String := To_String (T.Parent);
               begin
                  if P = Full_Name or else P = Short
                    or else Short_Name (P) = Short
                  then
                     return True;
                  end if;
               end;
            end if;
         end loop;
         return False;
      end Has_Subtypes;

      --  Type is in an inheritance hierarchy and has no Variant_Tag
      function Is_Abstract_Type (T : Type_Spec) return Boolean is
         Full : constant String := To_String (T.Name);
      begin
         return T.Kind = Record_Type
           and then Length (T.Variant_Tag) = 0
           and then (Length (T.Parent) > 0 or else Has_Subtypes (Full));
      end Is_Abstract_Type;

      --  ---------------------------------------------------------------
      --  Spec file
      --  ---------------------------------------------------------------

      procedure Emit_Spec is
         File : Ada.Text_IO.File_Type;
         Path : constant String :=
                  Ada.Directories.Compose (Output_Dir, File_Base, "ads");

         procedure Pl (S : String) is
         begin
            Ada.Text_IO.Put_Line (File, S);
         end Pl;

      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);

         declare
            Enum_Pkgs : constant String_Sets.Set := Enum_Packages;
         begin
            if Has_String_Fields then
               Pl ("with Ada.Strings.Unbounded;");
            end if;
            --  Enum fields are stored and accessed as their external type.
            for P of Enum_Pkgs loop
               Pl ("with " & To_String (P) & ";");
            end loop;
            if Has_String_Fields or else not Enum_Pkgs.Is_Empty then
               Ada.Text_IO.New_Line (File);
            end if;
         end;
         Pl ("package " & Pkg_Name & " is");
         Ada.Text_IO.New_Line (File);
         Pl ("   pragma Style_Checks (""-M"");");

         declare
            Sorted : constant Type_Vectors.Vector := Sorted_Types;
         begin
            --  ---- Visible part ----------------------------------------
            for T of Sorted loop
               declare
                  Type_Name    : constant String :=
                                   Short_Name (To_String (T.Name));
                  Full_Name    : constant String := To_String (T.Name);
                  Abstract_T   : constant Boolean := Is_Abstract_Type (T);
                  Concrete_T   : constant Boolean := Is_Concrete (T);
                  Has_Par      : constant Boolean :=
                                   Length (T.Parent) > 0;
                  Par_Short    : constant String :=
                                   (if Has_Par
                                    then Short_Name (To_String (T.Parent))
                                    else "");
                  Needs_To_J   : constant Boolean :=
                                   Type_Needs_To_Json (Full_Name);
                  Needs_From_J : constant Boolean :=
                                   Type_Needs_From_Json (Full_Name);
               begin
                  Ada.Text_IO.New_Line (File);

                  --  Type declaration
                  if Abstract_T and then Has_Par then
                     Pl ("   type " & Type_Name
                         & " is abstract new " & Par_Short
                         & " with private;");
                  elsif Abstract_T then
                     Pl ("   type " & Type_Name
                         & " is abstract tagged private;");
                  elsif Concrete_T and then Has_Par then
                     Pl ("   type " & Type_Name
                         & " is new " & Par_Short & " with private;");
                  else
                     Pl ("   type " & Type_Name & " is tagged private;");
                  end if;
                  Ada.Text_IO.New_Line (File);

                  --  Create (not for abstract types)
                  if not Abstract_T then
                     declare
                        All_Flds : constant Type_Field_Vectors.Vector :=
                                     All_Fields (T);
                     begin
                        Pl ("   function Create");
                        Emit_Param_List (File, All_Flds);
                        Pl ("      return " & Type_Name & ";");
                        Ada.Text_IO.New_Line (File);
                     end;
                  end if;

                  --  Accessors for own fields only
                  for F of T.Fields loop
                     declare
                        F_Name : constant String := To_String (F.Name);
                        F_Type : constant String := To_String (F.Type_Name);
                     begin
                        Pl ("   function " & F_Name
                            & " (Self : " & Type_Name
                            & ") return " & Field_Ada_Type (F_Type)
                            & ";");
                     end;
                  end loop;

                  --  To_Json / From_Json
                  Ada.Text_IO.New_Line (File);
                  if Abstract_T then
                     --  Abstract types always need a dispatching To_Json
                     if Has_Par then
                        Pl ("   overriding function To_Json");
                     else
                        Pl ("   function To_Json");
                     end if;
                     Pl ("     (Self   : " & Type_Name & ";");
                     Pl ("      Prefix : String := """") return String"
                         & " is abstract;");
                  elsif Concrete_T and then Has_Par then
                     --  Concrete derived: always overrides
                     Pl ("   overriding function To_Json");
                     Pl ("     (Self   : " & Type_Name & ";");
                     Pl ("      Prefix : String := """") return String;");
                     if Needs_From_J then
                        Pl ("   function From_Json"
                            & " (Json : String) return "
                            & Type_Name & ";");
                     end if;
                  else
                     --  Plain root or concrete root without parent
                     if Needs_To_J then
                        if not T.Links.Is_Empty then
                           Pl ("   function To_Json");
                           Pl ("     (Self   : " & Type_Name & ";");
                           Pl ("      Prefix : String := """")"
                               & " return String;");
                        else
                           Pl ("   function To_Json"
                               & " (Self : " & Type_Name
                               & ") return String;");
                        end if;
                     end if;
                     if Needs_From_J then
                        Pl ("   function From_Json"
                            & " (Json : String) return "
                            & Type_Name & ";");
                     end if;
                  end if;
               end;
            end loop;

            --  ---- Private part ----------------------------------------
            Ada.Text_IO.New_Line (File);
            Pl ("private");

            for T of Sorted loop
               declare
                  Type_Name  : constant String :=
                                 Short_Name (To_String (T.Name));
                  Abstract_T : constant Boolean := Is_Abstract_Type (T);
                  Concrete_T : constant Boolean := Is_Concrete (T);
                  Has_Par    : constant Boolean :=
                                 Length (T.Parent) > 0;
                  Par_Short  : constant String :=
                                 (if Has_Par
                                  then Short_Name (To_String (T.Parent))
                                  else "");
                  All_Flds   : constant Type_Field_Vectors.Vector :=
                                 All_Fields (T);
                  Own_Last   : constant Natural :=
                                 (if T.Fields.Is_Empty then 0
                                  else T.Fields.Last_Index);
                  All_Last   : constant Natural :=
                                 (if All_Flds.Is_Empty then 0
                                  else All_Flds.Last_Index);
               begin
                  Ada.Text_IO.New_Line (File);

                  --  Full type declaration
                  if Abstract_T and then Has_Par then
                     if T.Fields.Is_Empty then
                        Pl ("   type " & Type_Name
                            & " is abstract new " & Par_Short
                            & " with null record;");
                     else
                        Pl ("   type " & Type_Name
                            & " is abstract new " & Par_Short
                            & " with record");
                        for F of T.Fields loop
                           Pl ("      " & To_String (F.Name) & " : "
                               & Storage_Type (To_String (F.Type_Name))
                               & ";");
                        end loop;
                        Pl ("   end record;");
                     end if;
                  elsif Abstract_T then
                     if T.Fields.Is_Empty then
                        Pl ("   type " & Type_Name
                            & " is abstract tagged null record;");
                     else
                        Pl ("   type " & Type_Name
                            & " is abstract tagged record");
                        for F of T.Fields loop
                           Pl ("      " & To_String (F.Name) & " : "
                               & Storage_Type (To_String (F.Type_Name))
                               & ";");
                        end loop;
                        Pl ("   end record;");
                     end if;
                  elsif Concrete_T and then Has_Par then
                     if T.Fields.Is_Empty then
                        Pl ("   type " & Type_Name
                            & " is new " & Par_Short
                            & " with null record;");
                     else
                        Pl ("   type " & Type_Name
                            & " is new " & Par_Short & " with record");
                        for F of T.Fields loop
                           Pl ("      " & To_String (F.Name) & " : "
                               & Storage_Type (To_String (F.Type_Name))
                               & ";");
                        end loop;
                        Pl ("   end record;");
                     end if;
                  else
                     --  Plain or concrete root
                     if T.Fields.Is_Empty then
                        Pl ("   type " & Type_Name
                            & " is tagged null record;");
                     else
                        Pl ("   type " & Type_Name
                            & " is tagged record");
                        for F of T.Fields loop
                           Pl ("      " & To_String (F.Name) & " : "
                               & Storage_Type (To_String (F.Type_Name))
                               & ";");
                        end loop;
                        Pl ("   end record;");
                     end if;
                  end if;

                  if not Abstract_T then
                     Ada.Text_IO.New_Line (File);
                     --  Create expression function
                     Pl ("   function Create");
                     Emit_Param_List (File, All_Flds);
                     Pl ("      return " & Type_Name);
                     --  Qualified record aggregate: valid in private section
                     --  where all inherited components are visible.
                     Pl ("   is (" & Type_Name & "'");
                     for I in All_Flds.First_Index
                              .. All_Flds.Last_Index
                     loop
                        declare
                           F       : constant Type_Field :=
                                       All_Flds.Element (I);
                           F_Name  : constant String :=
                                       To_String (F.Name);
                           F_Type  : constant String :=
                                       To_String (F.Type_Name);
                           Is_Last : constant Boolean := (I = All_Last);
                           Init    : constant String :=
                                       (if Is_String_Field (F_Type)
                                        then "Ada.Strings.Unbounded"
                                             & ".To_Unbounded_String ("
                                             & F_Name & ")"
                                        else F_Name);
                           Pfx     : constant String :=
                                       (if I = All_Flds.First_Index
                                        then "         ("
                                        else "          ");
                           Sfx     : constant String :=
                                       (if Is_Last then "));" else ",");
                        begin
                           Pl (Pfx & F_Name & " => " & Init & Sfx);
                        end;
                     end loop;
                     Ada.Text_IO.New_Line (File);
                  end if;

                  --  Accessor expression functions for OWN fields only
                  for F of T.Fields loop
                     declare
                        F_Name : constant String := To_String (F.Name);
                        F_Type : constant String :=
                                   To_String (F.Type_Name);
                        Expr   : constant String :=
                                   (if Is_String_Field (F_Type)
                                    then "Ada.Strings.Unbounded"
                                         & ".To_String (Self."
                                         & F_Name & ")"
                                    else "Self." & F_Name);
                     begin
                        Pl ("   function " & F_Name
                            & " (Self : " & Type_Name
                            & ") return " & Field_Ada_Type (F_Type));
                        Pl ("   is (" & Expr & ");");
                     end;
                  end loop;

                  pragma Unreferenced (Own_Last);
               end;
            end loop;
         end;

         Ada.Text_IO.New_Line (File);
         Pl ("end " & Pkg_Name & ";");
         Ada.Text_IO.Close (File);
      end Emit_Spec;

      --  ---------------------------------------------------------------
      --  Body file (To_Json and From_Json implementations)
      --  ---------------------------------------------------------------

      procedure Emit_Body is
         File : Ada.Text_IO.File_Type;
         Path : constant String :=
                  Ada.Directories.Compose (Output_Dir, File_Base, "adb");

         procedure Pl (S : String) is
         begin
            Ada.Text_IO.Put_Line (File, S);
         end Pl;

      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);

         declare
            Sorted        : constant Type_Vectors.Vector := Sorted_Types;
            Need_GNATCOLL : Boolean := False;
            Need_Float_IO : Boolean := False;
            Need_Fixed    : Boolean := False;
            Enum_Pkgs     : constant String_Sets.Set := Enum_Packages;
         begin
            --  Determine required with clauses
            for T of Sorted loop
               if Is_Abstract_Type (T) then
                  null;  --  abstract types have no body
               else
                  declare
                     Full     : constant String := To_String (T.Name);
                     All_Flds : constant Type_Field_Vectors.Vector :=
                                  All_Fields (T);
                  begin
                     if Is_Concrete (T)
                       or else Type_Needs_To_Json (Full)
                     then
                        for F of All_Flds loop
                           declare
                              FT : constant String :=
                                     To_String (F.Type_Name);
                           begin
                              if Is_Float_Field (FT) then
                                 Need_Float_IO := True;
                                 Need_Fixed    := True;
                              elsif Is_Int_Field (FT) then
                                 Need_Fixed := True;
                              end if;
                           end;
                        end loop;
                     end if;
                     if Type_Needs_From_Json (Full) then
                        Need_GNATCOLL := True;
                     end if;
                  end;
               end if;
            end loop;
            if Need_GNATCOLL then
               Pl ("with GNATCOLL.JSON;");
            end if;
            if Need_Float_IO then
               Pl ("with Ada.Text_IO;");
            end if;
            if Need_Fixed then
               Pl ("with Ada.Strings.Fixed;");
            end if;
            --  Enum fields lowercase T'Image and reference T'Value.
            if not Enum_Pkgs.Is_Empty then
               Pl ("with Ada.Characters.Handling;");
            end if;
            for P of Enum_Pkgs loop
               Pl ("with " & To_String (P) & ";");
            end loop;

            Ada.Text_IO.New_Line (File);
            Pl ("package body " & Pkg_Name & " is");
            Ada.Text_IO.New_Line (File);
            Pl ("   pragma Style_Checks (""-M"");");

            for T of Sorted loop
               if Is_Abstract_Type (T) then
                  null;  --  no body for abstract types
               else
                  declare
                     Type_Name    : constant String :=
                                      Short_Name (To_String (T.Name));
                     Full_Name    : constant String := To_String (T.Name);
                     Concrete_T   : constant Boolean := Is_Concrete (T);
                     Has_Par      : constant Boolean :=
                                      Length (T.Parent) > 0;
                     Vtag         : constant String :=
                                      To_String (T.Variant_Tag);
                     All_Flds     : constant Type_Field_Vectors.Vector :=
                                      All_Fields (T);
                     All_Last     : constant Natural :=
                                      (if All_Flds.Is_Empty then 0
                                       else All_Flds.Last_Index);
                     Needs_To_J   : constant Boolean :=
                                      Concrete_T
                                      or else Type_Needs_To_Json (Full_Name);
                     Needs_From_J : constant Boolean :=
                                      Type_Needs_From_Json (Full_Name);
                  begin
                     --  To_Json
                     if Needs_To_J then
                        Ada.Text_IO.New_Line (File);
                        if Concrete_T and then Has_Par then
                           Pl ("   overriding function To_Json");
                           Pl ("     (Self   : " & Type_Name & ";");
                           Pl ("      Prefix : String := """")"
                               & " return String is");
                        elsif not T.Links.Is_Empty then
                           Pl ("   function To_Json");
                           Pl ("     (Self   : " & Type_Name & ";");
                           Pl ("      Prefix : String := """")"
                               & " return String is");
                        else
                           Pl ("   function To_Json"
                               & " (Self : " & Type_Name
                               & ") return String is");
                        end if;
                        --  Helpers
                        if Type_Has_Float_Fields (T) then
                           Pl ("      function Fmt_Float"
                               & " (V : Long_Float) return String is");
                           Pl ("         package LF_IO is new"
                               & " Ada.Text_IO.Float_IO (Long_Float);");
                           Pl ("         S : String (1 .. 50)"
                               & " := [others => ' '];");
                           Pl ("      begin");
                           Pl ("         LF_IO.Put (To => S, Item => V,"
                               & " Aft => 15, Exp => 0);");
                           Pl ("         return Ada.Strings.Fixed.Trim"
                               & " (S, Ada.Strings.Both);");
                           Pl ("      end Fmt_Float;");
                        end if;
                        if Type_Has_String_Fields (T)
                          or else Type_Has_Enum_Fields (T)
                          or else not T.Links.Is_Empty
                        then
                           Pl ("      function Quote (S : String)"
                               & " return String is");
                           Pl ("         R : String"
                               & " (1 .. S'Length * 2 + 2);");
                           Pl ("         P : Positive := 2;");
                           Pl ("      begin");
                           Pl ("         R (1) := '""';");
                           Pl ("         for C of S loop");
                           Pl ("            if C = '""' or else C = '\'"
                               & " then");
                           Pl ("               R (P) := '\'; P := P + 1;");
                           Pl ("            end if;");
                           Pl ("            R (P) := C; P := P + 1;");
                           Pl ("         end loop;");
                           Pl ("         R (P) := '""';");
                           Pl ("         return R (1 .. P);");
                           Pl ("      end Quote;");
                        end if;
                        Pl ("   begin");
                        declare
                           DQ          : constant String := (1 => '"');
                           First_Field : Boolean := True;
                        begin
                           Pl ("      return");
                           Pl ("        " & Ada_Lit ("{") & " &");
                           --  kind field first for concrete derived types
                           if Concrete_T and then Vtag /= "" then
                              Pl ("        "
                                  & Ada_Lit (DQ & "kind" & DQ & ":")
                                  & " & "
                                  & Ada_Lit (DQ & Vtag & DQ) & " &");
                              First_Field := False;
                           end if;
                           --  All fields (inherited + own)
                           for F of All_Flds loop
                              declare
                                 F_Name : constant String :=
                                            To_String (F.Name);
                                 F_Type : constant String :=
                                            To_String (F.Type_Name);
                                 Key    : constant String :=
                                            (if First_Field
                                             then DQ & To_Lower (F_Name)
                                                  & DQ & ":"
                                             else "," & DQ
                                                  & To_Lower (F_Name)
                                                  & DQ & ":");
                                 Val    : constant String :=
                                            (if Is_String_Field (F_Type)
                                             then "Quote ("
                                                  & F_Name & " (Self))"
                                             elsif Is_Float_Field (F_Type)
                                             then
                                                (if To_Lower (F_Type)
                                                    = "long_float"
                                                 then "Fmt_Float ("
                                                      & F_Name & " (Self))"
                                                 else "Fmt_Float (Long_Float ("
                                                      & F_Name & " (Self)))")
                                             elsif Is_Bool_Field (F_Type)
                                             then "(if " & F_Name
                                                  & " (Self) then "
                                                  & Ada_Lit ("true")
                                                  & " else "
                                                  & Ada_Lit ("false") & ")"
                                             elsif Is_Enum_Field (F_Type)
                                             then "Quote"
                                                  & " (Ada.Characters.Handling"
                                                  & ".To_Lower ("
                                                  & Field_Ada_Type (F_Type)
                                                  & "'Image ("
                                                  & F_Name & " (Self))))"
                                             else
                                                "Ada.Strings.Fixed.Trim ("
                                                & F_Name & " (Self)'Image,"
                                                & " Ada.Strings.Left)");
                              begin
                                 Pl ("        " & Ada_Lit (Key)
                                     & " & " & Val & " &");
                                 First_Field := False;
                              end;
                           end loop;
                           --  _links
                           if not T.Links.Is_Empty then
                              Pl ("        "
                                  & Ada_Lit
                                      ("," & DQ & "_links" & DQ & ":{")
                                  & " &");
                              declare
                                 First_Link : Boolean := True;
                              begin
                                 for Lnk of T.Links loop
                                    declare
                                       Lnk_Name : constant String :=
                                                    To_Lower (To_String
                                                      (Lnk.Name));
                                       Path  : constant String :=
                                                 Find_Function_Path
                                                   (To_String
                                                      (Lnk.Function_Name));
                                       Href  : constant String :=
                                                 Build_Href_Expr
                                                   (Path, Lnk.Bindings);
                                       Lnk_Key : constant String :=
                                                   (if First_Link
                                                    then DQ & Lnk_Name
                                                         & DQ & ":{" & DQ
                                                         & "href" & DQ & ":"
                                                    else "," & DQ & Lnk_Name
                                                         & DQ & ":{" & DQ
                                                         & "href" & DQ & ":");
                                    begin
                                       Pl ("        "
                                           & Ada_Lit (Lnk_Key)
                                           & " & Quote (Prefix & "
                                           & Href & ") & "
                                           & Ada_Lit ("}") & " &");
                                       First_Link := False;
                                    end;
                                 end loop;
                              end;
                              Pl ("        " & Ada_Lit ("}}") & ";");
                           else
                              Pl ("        " & Ada_Lit ("}") & ";");
                           end if;
                        end;
                        Pl ("   end To_Json;");
                     end if;

                     --  From_Json: use All_Fields for Create call
                     if Needs_From_J then
                        Ada.Text_IO.New_Line (File);
                        Pl ("   function From_Json"
                            & " (Json : String) return "
                            & Type_Name & " is");
                        Pl ("      Obj : constant"
                            & " GNATCOLL.JSON.JSON_Value :=");
                        Pl ("              GNATCOLL.JSON.Read (Json);");
                        Pl ("   begin");
                        Pl ("      return Create");
                        for I in All_Flds.First_Index
                                 .. All_Flds.Last_Index
                        loop
                           declare
                              F       : constant Type_Field :=
                                          All_Flds.Element (I);
                              F_Name  : constant String :=
                                          To_String (F.Name);
                              F_Type  : constant String :=
                                          To_String (F.Type_Name);
                              Is_Last : constant Boolean :=
                                          (I = All_Last);
                              Pfx     : constant String :=
                                          (if I = All_Flds.First_Index
                                           then "        ("
                                           else "         ");
                              Sfx     : constant String :=
                                          (if Is_Last then ");" else ",");
                              Get_Exp : constant String :=
                                          "GNATCOLL.JSON.Get (Obj, """
                                          & To_Lower (F_Name) & """)";
                              --  Enum fields arrive as a JSON string; 'Value
                              --  maps it back (case-insensitively) to the
                              --  external enumeration value.
                              Val_Exp : constant String :=
                                          (if Is_Enum_Field (F_Type)
                                           then Field_Ada_Type (F_Type)
                                                & "'Value (String'("
                                                & Get_Exp & "))"
                                           else Get_Exp);
                           begin
                              Pl (Pfx & F_Name & " => " & Val_Exp & Sfx);
                           end;
                        end loop;
                        Pl ("   end From_Json;");
                     end if;

                     pragma Unreferenced (All_Last);
                  end;
               end if;
            end loop;
         end;

         Ada.Text_IO.New_Line (File);
         Pl ("end " & Pkg_Name & ";");
         Ada.Text_IO.Close (File);
      end Emit_Body;

   begin
      Emit_Spec;
      if Needs_Body then
         Emit_Body;
      end if;
   end Write_Type_Package;

   --  ---------------------------------------------------------------

   procedure Generate
     (Spec       : Mia.Model.Package_Spec;
      Output_Dir : String)
   is
      use Mia.Model;
      Pkg       : constant String := To_String (Spec.Name);
      File_Base : constant String := Package_To_File (Pkg) & "-server";
      Pkg_Set   : String_Sets.Set;
   begin
      if not Ada.Directories.Exists (Output_Dir) then
         Ada.Directories.Create_Directory (Output_Dir);
      end if;

      --  Collect unique Ada packages implied by declared record types
      for T of Spec.Types loop
         if T.Kind = Record_Type then
            declare
               Pkg_Name : constant String := Impl_Package (To_String (T.Name));
            begin
               if Pkg_Name /= "" then
                  String_Sets.Include
                    (Pkg_Set, To_Unbounded_String (Pkg_Name));
               end if;
            end;
         end if;
      end loop;

      --  Generate one package per unique type package name
      for Pkg_Name of Pkg_Set loop
         Write_Type_Package (Spec, To_String (Pkg_Name), Output_Dir);
      end loop;

      --  Generate the server dispatcher package
      Write_Spec (Pkg, Output_Dir, File_Base);
      Write_Body (Spec, Pkg, Output_Dir, File_Base);
   end Generate;

end Mia.Generator;
