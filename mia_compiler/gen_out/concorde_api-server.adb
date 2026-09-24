with AWS.Response;
with AWS.Status;
with GNATCOLL.JSON;
with AWS.Messages;
with Mia.Sessions;
with Ada.Strings.Unbounded;
with Concorde.Api.Factions;
with Concorde.Api.Home;
with Concorde.Api.Responses;
with Concorde.Sessions;
with Mia.Registry;
with Mia.Server;

package body Concorde_Api.Server is

   type Session_Reference is
     not null access all Concorde.Sessions.Session_Interface'Class;

   Registered_Prefix : Ada.Strings.Unbounded.Unbounded_String;

   function Handle_Login
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

   function Handle_Execute_Command
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

   function Handle_Get_Faction
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

   function Handle_Get_All_Factions
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

   ------------------
   -- Handle_Login --
   ------------------

   function Handle_Login
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data
   is
      pragma Unreferenced (Session_Id, URI);
      use GNATCOLL.JSON;

      Faction : constant String :=
                  Parameters.Value ("faction");
      Result : constant String :=
                 Concorde.Api.Home.Login (Faction);
      Obj    : constant JSON_Value := Create_Object;
   begin
      Set_Field (Obj, "result", Result);

      declare
         S : constant String := Write (Obj);
      begin
         return AWS.Response.Build
           ("application/json", S);
      end;
   end Handle_Login;

   ----------------------------
   -- Handle_Execute_Command --
   ----------------------------

   function Handle_Execute_Command
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data
   is
      pragma Unreferenced (URI);

      Raw : constant access Mia.Sessions.Session_Interface'Class :=
              Mia.Sessions.Get (Session_Id);
   begin
      if Raw = null then
         return AWS.Response.Build
           ("application/json",
            "{""error"":""unauthorized""}",
            AWS.Messages.S401);
      end if;
      declare
         use GNATCOLL.JSON;

         Session : constant Session_Reference :=
                     Session_Reference (Raw);
         Command : constant String :=
                     Parameters.Value ("command");
         Result : constant String :=
                   Concorde.Api.Home.Execute_Command (Session, Command);
         Obj : constant JSON_Value := Create_Object;
      begin
         Set_Field (Obj, "result", Result);

         declare
            S : constant String := Write (Obj);
         begin
            return AWS.Response.Build
              ("application/json", S);
         end;
      end;
   end Handle_Execute_Command;

   ------------------------
   -- Handle_Get_Faction --
   ------------------------

   function Handle_Get_Faction
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data
   is
      pragma Unreferenced (URI);

      Raw : constant access Mia.Sessions.Session_Interface'Class :=
              Mia.Sessions.Get (Session_Id);
   begin
      if Raw = null then
         return AWS.Response.Build
           ("application/json",
            "{""error"":""unauthorized""}",
            AWS.Messages.S401);
      end if;
      declare
         Session : constant Session_Reference :=
                     Session_Reference (Raw);
         Faction_Name : constant String :=
                     Parameters.Value ("faction_name");
         Result : constant Concorde.Api.Responses.Faction_Record :=
                   Concorde.Api.Factions.Get_Faction (Session, Faction_Name);
      begin
         declare
            S : constant String :=
                     Concorde.Api.Responses.To_Json (Result,
                       Ada.Strings.Unbounded.To_String (Registered_Prefix));
         begin
            return AWS.Response.Build
              ("application/json", S);
         end;
      end;
   end Handle_Get_Faction;

   -----------------------------
   -- Handle_Get_All_Factions --
   -----------------------------

   function Handle_Get_All_Factions
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data
   is
      pragma Unreferenced (URI, Parameters);

      Raw : constant access Mia.Sessions.Session_Interface'Class :=
              Mia.Sessions.Get (Session_Id);
   begin
      if Raw = null then
         return AWS.Response.Build
           ("application/json",
            "{""error"":""unauthorized""}",
            AWS.Messages.S401);
      end if;
      declare
         Session : constant Session_Reference :=
                     Session_Reference (Raw);
         Items : GNATCOLL.JSON.JSON_Array;

         procedure Cb (Element : Concorde.Api.Responses.Faction_Record) is
         begin
            GNATCOLL.JSON.Append
              (Items,
               GNATCOLL.JSON.Read
                 (Concorde.Api.Responses.To_Json (Element,
                  Ada.Strings.Unbounded.To_String (Registered_Prefix))));
         end Cb;
      begin
         Concorde.Api.Factions.Scan_All_Factions (Session, Cb'Access);
         declare
            S : constant String :=
                  GNATCOLL.JSON.Write
                    (GNATCOLL.JSON.Create (Items));
         begin
            return AWS.Response.Build
              ("application/json", S);
         end;
      end;
   end Handle_Get_All_Factions;

   --------------
   -- Register --
   --------------

   procedure Register (Prefix : String := "") is
   begin
      Registered_Prefix :=
        Ada.Strings.Unbounded.To_Unbounded_String (Prefix);
      Mia.Registry.Register_Schema
        ("Faction_Record",
         "{""type"":""object"",""properties"":{""identifier"":{""type"":""string""},""name"":{""type"":""string""},""adjective"":{""type"":""string""},""plural"":{""type"":""string""},""_links"":{""type"":""object"",""properties"":{""self"":{""type"":""object"",""properties"":{""href"":{""type"":""string""}}}}}}}");
      Mia.Server.Register
        (Route           => Prefix & "/login",
         Handler         => Handle_Login'Access,
         Method          => AWS.Status.POST,
         Allow_Anonymous => True);
      Mia.Registry.Register_Route
        (Path        => Prefix & "/login",
         Method      => "post",
         Operation   => "Login",
         Path_Params     => "[{""name"":""faction"",""in"":""query"",""required"":true,""schema"":{""type"":""string""}}]",
         Result_Schema   => "{""type"":""object"",""properties"":{""result"":{""type"":""string""}}}",
         Allow_Anonymous => True);
      Mia.Server.Register
        (Route           => Prefix & "/execute",
         Handler         => Handle_Execute_Command'Access,
         Method          => AWS.Status.POST,
         Allow_Anonymous => False);
      Mia.Registry.Register_Route
        (Path        => Prefix & "/execute",
         Method      => "post",
         Operation   => "Execute_Command",
         Path_Params     => "[{""name"":""command"",""in"":""query"",""required"":true,""schema"":{""type"":""string""}}]",
         Result_Schema   => "{""type"":""object"",""properties"":{""result"":{""type"":""string""}}}",
         Allow_Anonymous => False);
      Mia.Server.Register
        (Route           => Prefix & "/factions/{faction_name}",
         Handler         => Handle_Get_Faction'Access,
         Method          => AWS.Status.GET,
         Allow_Anonymous => False);
      Mia.Registry.Register_Route
        (Path        => Prefix & "/factions/{faction_name}",
         Method      => "get",
         Operation   => "Get_Faction",
         Path_Params     => "[{""name"":""faction_name"",""in"":""path"",""required"":true,""schema"":{""type"":""string""}}]",
         Result_Schema   => "{""$ref"":""#/components/schemas/Faction_Record""}",
         Allow_Anonymous => False);
      Mia.Server.Register
        (Route           => Prefix & "/factions",
         Handler         => Handle_Get_All_Factions'Access,
         Method          => AWS.Status.GET,
         Allow_Anonymous => False);
      Mia.Registry.Register_Route
        (Path        => Prefix & "/factions",
         Method      => "get",
         Operation   => "Get_All_Factions",
         Path_Params     => "[]",
         Result_Schema   => "{""type"":""array"",""items"":{""$ref"":""#/components/schemas/Faction_Record""}}",
         Allow_Anonymous => False);
   end Register;

end Concorde_Api.Server;
