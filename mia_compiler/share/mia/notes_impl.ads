with Mia.Sessions;
with Notes;

package Notes_Impl is

   type Session is new Mia.Sessions.Session_Interface with record
      User_Id : Positive;
   end record;

   --  Anonymous: validate credentials and return a bearer token.
   --  Calls Mia.Sessions.Create internally.
   function Login
     (Username : String;
      Password : String)
      return String;

   function Note_Count
     (S : not null access Session)
      return Integer;

   function Get_Title
     (S       : not null access Session;
      Note_Id : Positive)
      return String;

   function Create_Note
     (S     : not null access Session;
      Title : String)
      return Positive;

   function Rename_Note
     (S       : not null access Session;
      Note_Id : Positive;
      Title   : String)
      return Boolean;

   function Delete_Note
     (S       : not null access Session;
      Note_Id : Positive)
      return Boolean;

   function Get_Properties
     (S       : not null access Session;
      Note_Id : Positive)
      return Notes.Note_Properties;

   function Set_Properties
     (S       : not null access Session;
      Note_Id : Positive;
      Props   : Notes.Note_Properties)
      return Boolean;

   function Properties_To_Json
     (Props : Notes.Note_Properties)
      return String;

   function Properties_From_Json
     (S : String)
      return Notes.Note_Properties;

end Notes_Impl;
