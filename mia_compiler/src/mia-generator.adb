with Ada.Characters.Handling;
with Ada.Containers.Ordered_Sets;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Mia.Generator is

   use Ada.Strings.Unbounded;

   --  ---------------------------------------------------------------
   --  General utilities
   --  ---------------------------------------------------------------

   function To_Lower (S : String) return String
     renames Ada.Characters.Handling.To_Lower;

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

   --  Forward declaration for mutual recursion.
   function Schema_For_Type
     (Type_Name : String;
      Types     : Mia.Model.Type_Vectors.Vector)
      return String;

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

   package String_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => Unbounded_String,
      "<"          => Ada.Strings.Unbounded."<",
      "="          => Ada.Strings.Unbounded."=");

   procedure Write_Body
     (Spec       : Mia.Model.Package_Spec;
      Pkg        : String;
      Output_Dir : String;
      File_Base  : String)
   is
      use Mia.Model;

      File  : Ada.Text_IO.File_Type;
      Path  : constant String :=
                Ada.Directories.Compose (Output_Dir, File_Base, "adb");
      Withs          : String_Sets.Set;
      Session_Type_S : constant String :=
                         To_String (Spec.Session_Type);

      function Fn_Needs_Auth (Fn : Mia.Model.Function_Spec)
        return Boolean
      is
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
         for F of Spec.Functions loop
            Add (To_String (F.Impl));
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

      procedure Write_Handler_Spec (Fn : Mia.Model.Function_Spec) is
         Handler_Name : constant String :=
                          "Handle_" & To_String (Fn.Name);
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
         To_Json_Fn   : constant String  := To_String (Fn.To_Json);
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
            Pl ("      pragma Unreferenced (URI);");
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
            Pl ("         Session : constant not null access "
                & Session_Type_S & " :=");
            Pl ("                     "
                & Session_Type_S & " (Raw.all)'Access;");
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
            Pl ("      pragma Unreferenced (Session_Id, URI);");
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
            if To_String (Fn.To_Json) = "" then
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

      for Fn of Spec.Functions loop
         Write_Handler_Spec (Fn);
      end loop;
      for Fn of Spec.Functions loop
         Write_Handler (Fn);
      end loop;

      Separator ("Register");
      Pl ("   procedure Register (Prefix : String := """") is");
      Pl ("   begin");
      for Fn of Spec.Functions loop
         declare
            Fn_Name     : constant String  := To_String (Fn.Name);
            Template    : constant String  := To_String (Fn.Path);
            Method_S    : constant String  := Method_Status (Fn.Method);
            Params_J    : constant String  := Build_Params_Json (Fn);
            Anon        : constant Boolean := not Fn_Needs_Auth (Fn);
            Schema_Fn   : constant String  :=
                            To_String (Fn.Body_Schema);
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
            Pl ("         Path_Params => "
                & Ada_Lit (Params_J) & ",");
            declare
               Ret_Schema : constant String :=
                              Ada_Lit
                                (Schema_For_Type
                                   (Resolve_Type
                                      (To_String (Fn.Return_Type),
                                       Spec.Types),
                                    Spec.Types));
            begin
               if Schema_Fn /= "" then
                  Pl ("         Result_Schema => " & Ret_Schema & ",");
                  Pl ("         Body_Schema   => "
                      & Ada_Lit
                          (Schema_For_Type (Schema_Fn, Spec.Types))
                      & ");");
               else
                  Pl ("         Result_Schema => " & Ret_Schema & ");");
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

   procedure Generate
     (Spec       : Mia.Model.Package_Spec;
      Output_Dir : String)
   is
      Pkg       : constant String := To_String (Spec.Name);
      File_Base : constant String :=
                    Package_To_File (Pkg) & "-server";
   begin
      if not Ada.Directories.Exists (Output_Dir) then
         Ada.Directories.Create_Directory (Output_Dir);
      end if;
      Write_Spec (Pkg, Output_Dir, File_Base);
      Write_Body (Spec, Pkg, Output_Dir, File_Base);
   end Generate;

end Mia.Generator;
