with AWS.Response;
with Mia.Server;

package Mia.Registry is

   procedure Register_Route
     (Path          : String;
      Method        : String;
      Operation     : String;
      Path_Params   : String;
      Result_Schema : String;
      Body_Schema   : String := "");

   function Handle_Swagger
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

end Mia.Registry;
