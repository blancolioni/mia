package Mia.Sessions is

   type Session_Interface is interface;
   type Session_Access is access all Session_Interface'Class;

   function Get
     (Session_Id : String)
      return Session_Access;

   function Create
     (Session : not null access Session_Interface'Class)
      return String;

   procedure Destroy (Session_Id : String);

end Mia.Sessions;
