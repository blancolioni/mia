with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Equal_Case_Insensitive;
with Ada.Strings.Hash_Case_Insensitive;
with AWS.Response;
with AWS.Status;

package Mia.Server is

   type Service_Parameters is tagged private;

   function Value (Parameters : Service_Parameters;
                   Key        : String)
                   return String;

   type Service_Handler is access
     function (Session_Id : String;
               URI        : String;
               Parameters : Service_Parameters)
               return AWS.Response.Data;

   procedure Register
     (Route           : String;
      Handler         : Service_Handler;
      Method          : AWS.Status.Request_Method := AWS.Status.GET;
      Allow_Anonymous : Boolean := True);

   function Session_Id_Of (Request : AWS.Status.Data) return String;
   --  Extract the session id from a request: the bearer token of the
   --  Authorization header, or the "token" query parameter (browsers
   --  cannot set headers on a WebSocket handshake).

   --  Serve on Port, at the address Host: every address if Host is
   --  empty, or only, say, "127.0.0.1", for a server reached through a
   --  proxy on the same machine and from nowhere else.
   procedure Start
     (Port         : Positive := 8080;
      Service_Name : String   := "mia-server";
      Host         : String   := "");
   procedure Stop (Message : String);

private

   package Parameter_Maps is
     new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => String,
      Hash            => Ada.Strings.Hash_Case_Insensitive,
      Equivalent_Keys => Ada.Strings.Equal_Case_Insensitive);

   type Service_Parameters is tagged
      record
         Map : Parameter_Maps.Map;
      end record;

end Mia.Server;
