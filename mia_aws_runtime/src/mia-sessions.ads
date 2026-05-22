package Mia.Sessions is

   type Session_Interface is interface;

   function Get
     (Session_Id : String)
      return access Session_Interface'Class;

   function Create
     (Session : not null access Session_Interface'Class)
      return String;

   procedure Destroy (Session_Id : String);

end Mia.Sessions;
