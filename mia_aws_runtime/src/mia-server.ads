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

   procedure Start;
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
