with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with GNATCOLL.JSON;
with Mia.Sessions;
with Notes;

package body Notes_Impl is

   use Ada.Strings.Unbounded;

   type Note_Record is record
      Owner_Id   : Positive;
      Title      : Unbounded_String;
      Properties : Notes.Note_Properties;
      Active     : Boolean := True;
   end record;

   package Note_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Note_Record);

   protected Store is
      function  Count    (User_Id : Positive) return Integer;
      function  Title_Of (Note_Id : Positive) return String;
      procedure Add
        (Owner_Id : Positive;
         Title    : String;
         Id       : out Positive);
      procedure Rename
        (Note_Id : Positive;
         Title   : String;
         Success : out Boolean);
      procedure Remove
        (Note_Id : Positive;
         Success : out Boolean);
      function  Get_Props
        (Note_Id : Positive)
         return Notes.Note_Properties;
      procedure Set_Props
        (Note_Id : Positive;
         Props   : Notes.Note_Properties;
         Success : out Boolean);
   private
      Notes   : Note_Vectors.Vector;
      Next_Id : Positive := 1;
   end Store;

   protected body Store is

      -----------
      -- Count --
      -----------

      function Count (User_Id : Positive) return Integer is
         N : Integer := 0;
      begin
         for Note of Notes loop
            if Note.Active and then Note.Owner_Id = User_Id then
               N := N + 1;
            end if;
         end loop;
         return N;
      end Count;

      --------------
      -- Title_Of --
      --------------

      function Title_Of (Note_Id : Positive) return String is
      begin
         if Note_Id <= Notes.Last_Index
           and then Notes (Note_Id).Active
         then
            return To_String (Notes (Note_Id).Title);
         end if;
         return "";
      end Title_Of;

      ---------
      -- Add --
      ---------

      procedure Add
        (Owner_Id : Positive;
         Title    : String;
         Id       : out Positive)
      is
      begin
         Id := Next_Id;
         Notes.Append
           (Note_Record'
              (Owner_Id => Owner_Id,
               Title    => To_Unbounded_String (Title),
               Active   => True));
         Next_Id := Next_Id + 1;
      end Add;

      ------------
      -- Rename --
      ------------

      procedure Rename
        (Note_Id : Positive;
         Title   : String;
         Success : out Boolean)
      is
      begin
         if Note_Id <= Notes.Last_Index
           and then Notes (Note_Id).Active
         then
            Notes (Note_Id).Title := To_Unbounded_String (Title);
            Success := True;
         else
            Success := False;
         end if;
      end Rename;

      ------------
      -- Remove --
      ------------

      procedure Remove
        (Note_Id : Positive;
         Success : out Boolean)
      is
      begin
         if Note_Id <= Notes.Last_Index
           and then Notes (Note_Id).Active
         then
            Notes (Note_Id).Active := False;
            Success := True;
         else
            Success := False;
         end if;
      end Remove;

      ---------------
      -- Get_Props --
      ---------------

      function Get_Props
        (Note_Id : Positive)
         return Notes.Note_Properties
      is
      begin
         if Note_Id <= Notes.Last_Index
           and then Notes (Note_Id).Active
         then
            return Notes (Note_Id).Properties;
         end if;
         return Notes.Note_Properties'
           (Author     => Null_Unbounded_String,
            Importance => Notes.Normal,
            Category   => Null_Unbounded_String);
      end Get_Props;

      ---------------
      -- Set_Props --
      ---------------

      procedure Set_Props
        (Note_Id : Positive;
         Props   : Notes.Note_Properties;
         Success : out Boolean)
      is
      begin
         if Note_Id <= Notes.Last_Index
           and then Notes (Note_Id).Active
         then
            Notes (Note_Id).Properties := Props;
            Success := True;
         else
            Success := False;
         end if;
      end Set_Props;

   end Store;

   -----------
   -- Login --
   -----------

   function Login
     (Username : String;
      Password : String)
      return String
   is
      pragma Unreferenced (Password);
      S : constant not null access Session :=
            new Session'
              (Mia.Sessions.Session_Interface with
               User_Id => Username'Length mod 1000 + 1);
   begin
      return Mia.Sessions.Create (S);
   end Login;

   ----------------
   -- Note_Count --
   ----------------

   function Note_Count
     (S : not null access Session)
      return Integer
   is
   begin
      return Store.Count (S.User_Id);
   end Note_Count;

   ---------------
   -- Get_Title --
   ---------------

   function Get_Title
     (S       : not null access Session;
      Note_Id : Positive)
      return String
   is
      pragma Unreferenced (S);
   begin
      return Store.Title_Of (Note_Id);
   end Get_Title;

   -----------------
   -- Create_Note --
   -----------------

   function Create_Note
     (S     : not null access Session;
      Title : String)
      return Positive
   is
      Id : Positive;
   begin
      Store.Add (S.User_Id, Title, Id);
      return Id;
   end Create_Note;

   -----------------
   -- Rename_Note --
   -----------------

   function Rename_Note
     (S       : not null access Session;
      Note_Id : Positive;
      Title   : String)
      return Boolean
   is
      pragma Unreferenced (S);
      Result : Boolean;
   begin
      Store.Rename (Note_Id, Title, Result);
      return Result;
   end Rename_Note;

   -----------------
   -- Delete_Note --
   -----------------

   function Delete_Note
     (S       : not null access Session;
      Note_Id : Positive)
      return Boolean
   is
      pragma Unreferenced (S);
      Result : Boolean;
   begin
      Store.Remove (Note_Id, Result);
      return Result;
   end Delete_Note;

   --------------------
   -- Get_Properties --
   --------------------

   function Get_Properties
     (S       : not null access Session;
      Note_Id : Positive)
      return Notes.Note_Properties
   is
      pragma Unreferenced (S);
   begin
      return Store.Get_Props (Note_Id);
   end Get_Properties;

   --------------------
   -- Set_Properties --
   --------------------

   function Set_Properties
     (S       : not null access Session;
      Note_Id : Positive;
      Props   : Notes.Note_Properties)
      return Boolean
   is
      pragma Unreferenced (S);
      Result : Boolean;
   begin
      Store.Set_Props (Note_Id, Props, Result);
      return Result;
   end Set_Properties;

   ------------------------
   -- Properties_To_Json --
   ------------------------

   function Properties_To_Json
     (Props : Notes.Note_Properties)
      return String
   is
      use GNATCOLL.JSON;
      Obj : constant JSON_Value := Create_Object;
   begin
      Set_Field (Obj, "author",
                 To_String (Props.Author));
      Set_Field (Obj, "importance",
                 Notes.Note_Importance'Image (Props.Importance));
      Set_Field (Obj, "category",
                 To_String (Props.Category));
      return Write (Obj);
   end Properties_To_Json;

   --------------------------
   -- Properties_From_Json --
   --------------------------

   function Properties_From_Json
     (S : String)
      return Notes.Note_Properties
   is
      use GNATCOLL.JSON;
      Obj    : constant JSON_Value := Read (S);
      Result : Notes.Note_Properties;
   begin
      Result.Author :=
        To_Unbounded_String (Get (Obj, "author"));
      Result.Importance :=
        Notes.Note_Importance'Value (String'(Get (Obj, "importance")));
      Result.Category :=
        To_Unbounded_String (Get (Obj, "category"));
      return Result;
   end Properties_From_Json;

end Notes_Impl;
