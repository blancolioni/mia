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

   function Schema_For_Enum
     (T : Mia.Model.Type_Spec) return String;

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
      elsif Lower = "float" or else Lower = "long_float" then
         return "Set_Field (Obj, ""result"", Float (Result))";
      else
         --  Enumeration or other scalar: use 'Image as a string value.
         return "Set_Field (Obj, ""result"", Result'Image)";
      end if;
   end Json_Set_Field;

   --  ---------------------------------------------------------------
   --  Schema generation from declared types
   --  ---------------------------------------------------------------

   function Schema_For_Enum
     (T : Mia.Model.Type_Spec) return String
   is
      J     : Unbounded_String;
      First : Boolean := True;
   begin
      Append (J, "{""type"":""string"",""enum"":[");
      for Lit of T.Literals loop
         if not First then
            Append (J, ",");
         end if;
         First := False;
         Append (J, """" & To_String (Lit) & """");
      end loop;
      Append (J, "]}");
      return To_String (J);
   end Schema_For_Enum;

   function Schema_For_Record
     (T     : Mia.Model.Type_Spec;
      Types : Mia.Model.Type_Vectors.Vector)
      return String
   is
      J     : Unbounded_String;
      First : Boolean := True;
   begin
      Append (J, "{""type"":""object"",""properties"":{");
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
      Append (J, "}}");
      return To_String (J);
   end Schema_For_Record;

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
                  when Enum_Type   => return Schema_For_Enum (T);
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

      function Fn_Needs_Auth (Fn : Mia.Model.Function_Spec) return Boolean is
      begin
         return Session_Type_S /= ""
           and then Fn.Auth /= Mia.Model.Anonymous;
      end Fn_Needs_Auth;

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
            Pl ("         Result : constant " & Ret_Type & " :=");
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
               Pl ("                     " & To_Json_Fn & " (Result);");
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
            Pl ("      Result : constant " & Ret_Type & " :=");
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
               Pl ("                  " & To_Json_Fn & " (Result);");
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
         To_Json_Fn   : constant String  :=
                          Resolve_To_Json (Elem_Type, Fn, Spec.Types);
         Has_Session  : constant Boolean := Fn_Needs_Auth (Fn);
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
            Pl (Indent & "procedure Cb (Element : " & Elem_Type & ") is");
            Pl (Indent & "begin");
            if To_Json_Fn /= "" then
               Pl (Indent & "   GNATCOLL.JSON.Append");
               Pl (Indent & "     (Items,");
               Pl (Indent & "      GNATCOLL.JSON.Read"
                   & " (" & To_Json_Fn & " (Element)));");
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
         end loop;
         if Needs_Json then
            Pl ("with GNATCOLL.JSON;");
         end if;
         if Needs_Session then
            Pl ("with AWS.Messages;");
            Pl ("with Mia.Sessions;");
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
      if Session_Type_S /= "" then
         Pl ("   type Session_Reference is");
         Pl ("     not null access all " & Session_Type_S & "'Class;");
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
               Elem_Type_S : constant String :=
                               Resolve_Type
                                 (To_String (Fn.Return_Type), Spec.Types);
               Elem_Schema : constant String :=
                               Schema_For_Type (Elem_Type_S, Spec.Types);
               Has_To_Json : constant Boolean :=
                               Resolve_To_Json
                                 (Elem_Type_S, Fn, Spec.Types) /= "";
               Ret_Schema  : constant String :=
                               Ada_Lit
                                 (if Fn.Is_Array then
                                    "{""type"":""array"",""items"":"
                                    & Elem_Schema & "}"
                                  elsif Has_To_Json then
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

      --  Storage type used in the private record body
      function Storage_Type (Field_Type : String) return String is
      begin
         if Is_String_Field (Field_Type) then
            return "Ada.Strings.Unbounded.Unbounded_String";
         else
            return Field_Type;
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

      --  Capitalise the first character of a string
      function Cap_First (S : String) return String is
      begin
         if S'Length = 0 then
            return S;
         end if;
         return Ada.Characters.Handling.To_Upper (S (S'First))
                & S (S'First + 1 .. S'Last);
      end Cap_First;

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

      --  True when any type in this package needs To_Json or From_Json
      function Needs_Body return Boolean is
      begin
         for T of Spec.Types loop
            if Type_In_Pkg (T) then
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
                 (File, Prefix & F_Name & " : " & F_Type & Suffix);
            end;
         end loop;
      end Emit_Param_List;

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

         if Has_String_Fields then
            Pl ("with Ada.Strings.Unbounded;");
            Ada.Text_IO.New_Line (File);
         end if;
         Pl ("package " & Pkg_Name & " is");

         --  Visible part: one block per type
         for T of Spec.Types loop
            if Type_In_Pkg (T) then
               declare
                  Type_Name    : constant String  :=
                                   Short_Name (To_String (T.Name));
                  Full_Name    : constant String  := To_String (T.Name);
                  Needs_To_J   : constant Boolean :=
                                   Type_Needs_To_Json (Full_Name);
                  Needs_From_J : constant Boolean :=
                                   Type_Needs_From_Json (Full_Name);
               begin
                  Ada.Text_IO.New_Line (File);
                  Pl ("   type " & Type_Name & " is tagged private;");
                  Ada.Text_IO.New_Line (File);

                  --  Create
                  Pl ("   function Create");
                  Emit_Param_List (File, T.Fields);
                  Pl ("      return " & Type_Name & ";");
                  Ada.Text_IO.New_Line (File);

                  --  Accessors
                  for F of T.Fields loop
                     declare
                        F_Name : constant String := To_String (F.Name);
                        F_Type : constant String := To_String (F.Type_Name);
                     begin
                        Pl ("   function " & F_Name
                            & " (Self : " & Type_Name
                            & ") return " & F_Type & ";");
                     end;
                  end loop;

                  --  To_Json / From_Json declarations
                  if Needs_To_J or else Needs_From_J then
                     Ada.Text_IO.New_Line (File);
                  end if;
                  if Needs_To_J then
                     Pl ("   function To_Json"
                         & " (Self : " & Type_Name & ") return String;");
                  end if;
                  if Needs_From_J then
                     Pl ("   function From_Json"
                         & " (Json : String) return " & Type_Name & ";");
                  end if;
               end;
            end if;
         end loop;

         --  Private part: full type + expression function completions
         Ada.Text_IO.New_Line (File);
         Pl ("private");

         for T of Spec.Types loop
            if Type_In_Pkg (T) then
               declare
                  Type_Name : constant String :=
                                Short_Name (To_String (T.Name));
                  Last      : constant Natural :=
                                (if T.Fields.Is_Empty then 0
                                 else T.Fields.Last_Index);
               begin
                  Ada.Text_IO.New_Line (File);

                  --  Full record declaration
                  Pl ("   type " & Type_Name & " is tagged record");
                  for F of T.Fields loop
                     Pl ("      " & To_String (F.Name) & " : "
                         & Storage_Type (To_String (F.Type_Name)) & ";");
                  end loop;
                  Pl ("   end record;");
                  Ada.Text_IO.New_Line (File);

                  --  Create expression function
                  Pl ("   function Create");
                  Emit_Param_List (File, T.Fields);
                  Pl ("      return " & Type_Name);
                  Pl ("   is (" & Type_Name & "'");
                  for I in T.Fields.First_Index .. T.Fields.Last_Index loop
                     declare
                        F       : constant Type_Field := T.Fields.Element (I);
                        F_Name  : constant String     := To_String (F.Name);
                        F_Type  : constant String     :=
                                    To_String (F.Type_Name);
                        Is_Last : constant Boolean    := (I = Last);
                        Init    : constant String     :=
                                    (if Is_String_Field (F_Type)
                                     then "Ada.Strings.Unbounded"
                                          & ".To_Unbounded_String ("
                                          & F_Name & ")"
                                     else F_Name);
                        Prefix  : constant String     :=
                                    (if I = T.Fields.First_Index
                                     then "         (" else "          ");
                        Suffix  : constant String     :=
                                    (if Is_Last then "));" else ",");
                     begin
                        Pl (Prefix & F_Name & " => " & Init & Suffix);
                     end;
                  end loop;
                  Ada.Text_IO.New_Line (File);

                  --  Accessor expression functions
                  for F of T.Fields loop
                     declare
                        F_Name : constant String := To_String (F.Name);
                        F_Type : constant String := To_String (F.Type_Name);
                        Expr   : constant String :=
                                   (if Is_String_Field (F_Type)
                                    then "Ada.Strings.Unbounded"
                                         & ".To_String (Self." & F_Name & ")"
                                    else "Self." & F_Name);
                     begin
                        Pl ("   function " & F_Name
                            & " (Self : " & Type_Name & ") return " & F_Type);
                        Pl ("   is (" & Expr & ");");
                     end;
                  end loop;
               end;
            end if;
         end loop;

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

         Pl ("with GNATCOLL.JSON;");
         Ada.Text_IO.New_Line (File);
         Pl ("package body " & Pkg_Name & " is");

         for T of Spec.Types loop
            if Type_In_Pkg (T) then
               declare
                  Type_Name    : constant String  :=
                                   Short_Name (To_String (T.Name));
                  Full_Name    : constant String  := To_String (T.Name);
                  Needs_To_J   : constant Boolean :=
                                   Type_Needs_To_Json (Full_Name);
                  Needs_From_J : constant Boolean :=
                                   Type_Needs_From_Json (Full_Name);
                  Last         : constant Natural :=
                                   (if T.Fields.Is_Empty then 0
                                    else T.Fields.Last_Index);
               begin
                  --  To_Json
                  if Needs_To_J then
                     Ada.Text_IO.New_Line (File);
                     Pl ("   function To_Json"
                         & " (Self : " & Type_Name & ") return String is");
                     Pl ("      Obj : constant GNATCOLL.JSON.JSON_Value :=");
                     Pl ("              GNATCOLL.JSON.Create_Object;");
                     Pl ("   begin");
                     for F of T.Fields loop
                        declare
                           F_Name : constant String := To_String (F.Name);
                           Value  : constant String :=
                                      F_Name & " (Self)";
                        begin
                           Pl ("      GNATCOLL.JSON.Set_Field");
                           Pl ("        (Obj, """ & To_Lower (F_Name)
                               & """, " & Value & ");");
                        end;
                     end loop;
                     if not T.Links.Is_Empty then
                        Pl ("      declare");
                        Pl ("         Links_Val : constant"
                            & " GNATCOLL.JSON.JSON_Value :=");
                        Pl ("                       "
                            & "GNATCOLL.JSON.Create_Object;");
                        for Lnk of T.Links loop
                           declare
                              Var : constant String :=
                                      "Link_"
                                      & Cap_First (To_String (Lnk.Name));
                           begin
                              Pl ("         " & Var
                                  & " : constant"
                                  & " GNATCOLL.JSON.JSON_Value :=");
                              Pl ("                       "
                                  & "GNATCOLL.JSON.Create_Object;");
                           end;
                        end loop;
                        Pl ("      begin");
                        for Lnk of T.Links loop
                           declare
                              Lnk_Name : constant String :=
                                           To_String (Lnk.Name);
                              Var      : constant String :=
                                           "Link_" & Cap_First (Lnk_Name);
                              Path     : constant String :=
                                           Find_Function_Path
                                             (To_String
                                                (Lnk.Function_Name));
                              Href     : constant String :=
                                           Build_Href_Expr
                                             (Path, Lnk.Bindings);
                           begin
                              Pl ("         GNATCOLL.JSON.Set_Field");
                              Pl ("           (" & Var
                                  & ", ""href"", " & Href & ");");
                              Pl ("         GNATCOLL.JSON.Set_Field");
                              Pl ("           (Links_Val, """
                                  & To_Lower (Lnk_Name)
                                  & """, " & Var & ");");
                           end;
                        end loop;
                        Pl ("         GNATCOLL.JSON.Set_Field");
                        Pl ("           (Obj, ""_links"", Links_Val);");
                        Pl ("      end;");
                     end if;
                     Pl ("      return GNATCOLL.JSON.Write (Obj);");
                     Pl ("   end To_Json;");
                  end if;

                  --  From_Json
                  if Needs_From_J then
                     Ada.Text_IO.New_Line (File);
                     Pl ("   function From_Json"
                         & " (Json : String) return " & Type_Name & " is");
                     Pl ("      Obj : constant GNATCOLL.JSON.JSON_Value :=");
                     Pl ("              GNATCOLL.JSON.Read (Json);");
                     Pl ("   begin");
                     Pl ("      return Create");
                     for I in T.Fields.First_Index .. T.Fields.Last_Index loop
                        declare
                           F       : constant Type_Field :=
                                       T.Fields.Element (I);
                           F_Name  : constant String     := To_String (F.Name);
                           Is_Last : constant Boolean    := (I = Last);
                           Prefix  : constant String     :=
                                       (if I = T.Fields.First_Index
                                        then "        (" else "         ");
                           Suffix  : constant String     :=
                                       (if Is_Last then ");" else ",");
                        begin
                           Pl (Prefix & F_Name
                               & " => GNATCOLL.JSON.Get (Obj, """
                               & To_Lower (F_Name) & """)" & Suffix);
                        end;
                     end loop;
                     Pl ("   end From_Json;");
                  end if;
               end;
            end if;
         end loop;

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
