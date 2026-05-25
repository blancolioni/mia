with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package body Mia.Registry is

   use Ada.Strings.Unbounded;

   type Route_Info is record
      Path            : Unbounded_String;
      Method          : Unbounded_String;
      Operation       : Unbounded_String;
      Path_Params     : Unbounded_String;
      Result_Schema   : Unbounded_String;
      Allow_Anonymous : Boolean;
      Body_Schema     : Unbounded_String;
   end record;

   package Route_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Route_Info);

   Routes : Route_Vectors.Vector;

   -------------------
   -- Build_Swagger --
   -------------------

   function Build_Swagger return String is
      Q        : constant Character := '"';
      J        : Unbounded_String;
      First    : Boolean := True;
      Has_Auth : Boolean := False;
   begin
      for R of Routes loop
         if not R.Allow_Anonymous then
            Has_Auth := True;
            exit;
         end if;
      end loop;

      Append (J, "{" & Q & "openapi" & Q & ":" & Q & "3.0.0" & Q & ",");
      Append (J, Q & "info" & Q & ":{"
              & Q & "title" & Q & ":" & Q & "API" & Q & ","
              & Q & "version" & Q & ":" & Q & "1.0.0" & Q & "},");
      if Has_Auth then
         Append (J, Q & "components" & Q & ":{"
                 & Q & "securitySchemes" & Q & ":{"
                 & Q & "bearerAuth" & Q & ":{"
                 & Q & "type" & Q & ":" & Q & "http" & Q & ","
                 & Q & "scheme" & Q & ":" & Q & "bearer" & Q
                 & "}}},");
      end if;
      Append (J, Q & "paths" & Q & ":{");
      for R of Routes loop
         if not First then
            Append (J, ",");
         end if;
         First := False;
         Append (J, Q & To_String (R.Path) & Q & ":{");
         Append (J, Q & To_String (R.Method) & Q & ":{");
         Append (J, Q & "operationId" & Q & ":"
                 & Q & To_String (R.Operation) & Q & ",");
         if Has_Auth then
            if R.Allow_Anonymous then
               Append (J, Q & "security" & Q & ":[],");
            else
               Append (J, Q & "security" & Q & ":["
                       & "{" & Q & "bearerAuth" & Q & ":[]}"
                       & "],");
            end if;
         end if;
         Append (J, Q & "parameters" & Q & ":"
                 & To_String (R.Path_Params) & ",");
         if Length (R.Body_Schema) > 0 then
            Append (J, Q & "requestBody" & Q & ":{"
                    & Q & "required" & Q & ":true,"
                    & Q & "content" & Q & ":{"
                    & Q & "application/json" & Q & ":{"
                    & Q & "schema" & Q & ":"
                    & To_String (R.Body_Schema) & "}}},");
         end if;
         Append (J, Q & "responses" & Q & ":{"
                 & Q & "200" & Q & ":{");
         Append (J, Q & "description" & Q & ":"
                 & Q & "Success" & Q & ",");
         Append (J, Q & "content" & Q & ":{"
                 & Q & "application/json" & Q & ":{"
                 & Q & "schema" & Q & ":{");
         Append (J, Q & "type" & Q & ":" & Q & "object" & Q & ","
                 & Q & "properties" & Q & ":{");
         Append (J, Q & "result" & Q & ":"
                 & To_String (R.Result_Schema) & "}}");
         Append (J, "}}}}}}");
      end loop;
      Append (J, "}}");
      return To_String (J);
   end Build_Swagger;

   --------------------
   -- Handle_Swagger --
   --------------------

   function Handle_Swagger
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data
   is
      pragma Unreferenced (Session_Id, URI, Parameters);
   begin
      return AWS.Response.Build
        ("application/json", Build_Swagger);
   end Handle_Swagger;

   --------------------
   -- Register_Route --
   --------------------

   procedure Register_Route
     (Path            : String;
      Method          : String;
      Operation       : String;
      Path_Params     : String;
      Result_Schema   : String;
      Allow_Anonymous : Boolean := True;
      Body_Schema     : String  := "")
   is
   begin
      Route_Vectors.Append
        (Routes,
         Route_Info'
           (Path            => To_Unbounded_String (Path),
            Method          => To_Unbounded_String (Method),
            Operation       => To_Unbounded_String (Operation),
            Path_Params     => To_Unbounded_String (Path_Params),
            Result_Schema   => To_Unbounded_String (Result_Schema),
            Allow_Anonymous => Allow_Anonymous,
            Body_Schema     => To_Unbounded_String (Body_Schema)));
   end Register_Route;

end Mia.Registry;
