with AWS.Response;
with AWS.Status;
with GNATCOLL.JSON;
with AWS.Messages;
with Mia.Sessions;
with Ada.Strings.Unbounded;
with Test.Api.Impl;
with Test.Api.Types;
with Test.Sessions;
with Mia.Registry;
with Mia.Server;

package body Test_Api.Server is

   type Session_Reference is
     not null access all Test.Sessions.Session_Interface'Class;

   Registered_Prefix : Ada.Strings.Unbounded.Unbounded_String;

   function Handle_Get_Satellites
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

   function Handle_Get_Star
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

   ---------------------------
   -- Handle_Get_Satellites --
   ---------------------------

   function Handle_Get_Satellites
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
         Star_Slug : constant String :=
                     Parameters.Value ("star_slug");
         Items : GNATCOLL.JSON.JSON_Array;

         procedure Cb (Element : Test.Api.Types.Celestial_Object'Class) is
         begin
            GNATCOLL.JSON.Append
              (Items,
               GNATCOLL.JSON.Read
                 (Test.Api.Types.To_Json (Element,
                  Ada.Strings.Unbounded.To_String (Registered_Prefix))));
         end Cb;
      begin
         Test.Api.Impl.Scan_Satellites (Session, Star_Slug, Cb'Access);
         declare
            S : constant String :=
                  GNATCOLL.JSON.Write
                    (GNATCOLL.JSON.Create (Items));
         begin
            return AWS.Response.Build
              ("application/json", S);
         end;
      end;
   end Handle_Get_Satellites;

   ---------------------
   -- Handle_Get_Star --
   ---------------------

   function Handle_Get_Star
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
         Star_Slug : constant String :=
                     Parameters.Value ("star_slug");
         Result : constant Test.Api.Types.Star :=
                   Test.Api.Impl.Get_Star (Session, Star_Slug);
      begin
         declare
            S : constant String :=
                     Test.Api.Types.To_Json (Result);
         begin
            return AWS.Response.Build
              ("application/json", S);
         end;
      end;
   end Handle_Get_Star;

   --------------
   -- Register --
   --------------

   procedure Register (Prefix : String := "") is
   begin
      Registered_Prefix :=
        Ada.Strings.Unbounded.To_Unbounded_String (Prefix);
      Mia.Registry.Register_Schema
        ("Named_Object",
         "{""type"":""object"",""properties"":{""slug"":{""type"":""string""},""name"":{""type"":""string""}}}");
      Mia.Registry.Register_Schema
        ("Celestial_Object",
         "{""allOf"":[{""$ref"":""#/components/schemas/Named_Object""},{""type"":""object"",""properties"":{""mass"":{""type"":""number""},""radius"":{""type"":""number""}}}]}");
      Mia.Registry.Register_Schema
        ("Star",
         "{""allOf"":[{""$ref"":""#/components/schemas/Celestial_Object""},{""type"":""object"",""properties"":{""kind"":{""type"":""string"",""enum"":[""star""]},""spectral_class"":{""type"":""string""},""luminosity"":{""type"":""number""}}}]}");
      Mia.Registry.Register_Schema
        ("World",
         "{""allOf"":[{""$ref"":""#/components/schemas/Celestial_Object""},{""type"":""object"",""properties"":{""kind"":{""type"":""string"",""enum"":[""world""]},""orbit_zone"":{""type"":""string""},""climate"":{""type"":""string""}}}]}");
      Mia.Server.Register
        (Route           => Prefix & "/stars/{star_slug}/satellites",
         Handler         => Handle_Get_Satellites'Access,
         Method          => AWS.Status.GET,
         Allow_Anonymous => False);
      Mia.Registry.Register_Route
        (Path        => Prefix & "/stars/{star_slug}/satellites",
         Method      => "get",
         Operation   => "Get_Satellites",
         Path_Params     => "[{""name"":""star_slug"",""in"":""path"",""required"":true,""schema"":{""type"":""string""}}]",
         Result_Schema   => "{""type"":""array"",""items"":{""oneOf"":[{""$ref"":""#/components/schemas/Star""},{""$ref"":""#/components/schemas/World""}],""discriminator"":{""propertyName"":""kind""}}}",
         Allow_Anonymous => False);
      Mia.Server.Register
        (Route           => Prefix & "/stars/{star_slug}",
         Handler         => Handle_Get_Star'Access,
         Method          => AWS.Status.GET,
         Allow_Anonymous => False);
      Mia.Registry.Register_Route
        (Path        => Prefix & "/stars/{star_slug}",
         Method      => "get",
         Operation   => "Get_Star",
         Path_Params     => "[{""name"":""star_slug"",""in"":""path"",""required"":true,""schema"":{""type"":""string""}}]",
         Result_Schema   => "{""$ref"":""#/components/schemas/Star""}",
         Allow_Anonymous => False);
   end Register;

end Test_Api.Server;
