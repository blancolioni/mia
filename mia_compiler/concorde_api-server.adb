with AWS.Response;
with AWS.Status;
with GNATCOLL.JSON;
with Concorde.Api.Home;
with Mia.Registry;
with Mia.Server;

package body Concorde_Api.Server is

   function Handle_Plus
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

   -----------------
   -- Handle_Plus --
   -----------------

   function Handle_Plus
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data
   is
      pragma Unreferenced (Session_Id, URI);
      use GNATCOLL.JSON;

      X : constant Integer := Integer'Value (Parameters.Value ("x"));
      Y : constant Integer := Integer'Value (Parameters.Value ("y"));
      Result : constant Integer :=
                 Concorde.Api.Home.Plus (X, Y);
      Obj    : constant JSON_Value        := Create_Object;
   begin
      Set_Field (Obj, "result", Result);

      declare
         S : constant String := Write (Obj);
      begin
         return AWS.Response.Build
           ("application/json", S);
      end;
   end Handle_Plus;

   --------------
   -- Register --
   --------------

   procedure Register
     (Prefix :        String := "")
   is
   begin
      Mia.Server.Register
        (Route           => Prefix & "/plus/{x}/{y}",
         Handler         => Handle_Plus'Access,
         Method          => AWS.Status.GET,
         Allow_Anonymous => True);
      Mia.Registry.Register_Route
        (Path        => Prefix & "/plus/{x}/{y}",
         Method      => "get",
         Operation   => "Plus",
         Path_Params => "[{""name"":""X"",""in"":""path"",""required"":true,""schema"":{""type"":""integer""}},{""name"":""Y"",""in"":""path"",""required"":true,""schema"":{""type"":""integer""}}]",
         Result_Type => "integer");
   end Register;

end Concorde_Api.Server;
