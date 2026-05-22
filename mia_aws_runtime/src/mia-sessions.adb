with Ada.Containers.Hashed_Maps;
with Ada.Numerics.Discrete_Random;
with Ada.Strings.Unbounded;

package body Mia.Sessions is

   use Ada.Strings.Unbounded;

   type Session_Access is access all Session_Interface'Class;

   package Session_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => Unbounded_String,
      Element_Type    => Session_Access,
      Hash            => Ada.Strings.Unbounded.Hash,
      Equivalent_Keys => Ada.Strings.Unbounded."=");

   subtype Hex_Index is Natural range 0 .. 15;
   package Random_Hex is new Ada.Numerics.Discrete_Random (Hex_Index);

   Gen : Random_Hex.Generator;
   Hex : constant String := "0123456789abcdef";

   function Make_Token return String is
      Result : String (1 .. 32);
   begin
      for I in Result'Range loop
         Result (I) := Hex (Hex'First + Random_Hex.Random (Gen));
      end loop;
      return Result;
   end Make_Token;

   protected Store is
      function  Fetch  (Session_Id : String) return Session_Access;
      procedure Insert (Session_Id : String; Session : Session_Access);
      procedure Remove (Session_Id : String);
   private
      Map : Session_Maps.Map;
   end Store;

   protected body Store is

      -----------
      -- Fetch --
      -----------

      function Fetch (Session_Id : String) return Session_Access is
         Position : constant Session_Maps.Cursor :=
                      Map.Find (To_Unbounded_String (Session_Id));
      begin
         if Session_Maps.Has_Element (Position) then
            return Session_Maps.Element (Position);
         else
            return null;
         end if;
      end Fetch;

      ------------
      -- Insert --
      ------------

      procedure Insert
        (Session_Id : String;
         Session    : Session_Access)
      is
      begin
         Map.Insert (To_Unbounded_String (Session_Id), Session);
      end Insert;

      ------------
      -- Remove --
      ------------

      procedure Remove (Session_Id : String) is
      begin
         Map.Exclude (To_Unbounded_String (Session_Id));
      end Remove;

   end Store;

   ------------
   -- Create --
   ------------

   function Create
     (Session : not null access Session_Interface'Class)
      return String
   is
      Token : constant String := Make_Token;
   begin
      Store.Insert (Token, Session_Access (Session));
      return Token;
   end Create;

   -------------
   -- Destroy --
   -------------

   procedure Destroy (Session_Id : String) is
   begin
      Store.Remove (Session_Id);
   end Destroy;

   ---------
   -- Get --
   ---------

   function Get
     (Session_Id : String)
      return access Session_Interface'Class
   is
   begin
      return Store.Fetch (Session_Id);
   end Get;

begin
   Random_Hex.Reset (Gen);
end Mia.Sessions;
