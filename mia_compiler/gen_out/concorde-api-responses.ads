with Ada.Strings.Unbounded;

package Concorde.Api.Responses is

   type Faction_Record is tagged private;

   function Create
     (Identifier : String;
      Name : String;
      Adjective : String;
      Plural : String)
      return Faction_Record;

   function Identifier (Self : Faction_Record) return String;
   function Name (Self : Faction_Record) return String;
   function Adjective (Self : Faction_Record) return String;
   function Plural (Self : Faction_Record) return String;

   function To_Json
     (Self   : Faction_Record;
      Prefix : String := "") return String;

private

   type Faction_Record is tagged record
      Identifier : Ada.Strings.Unbounded.Unbounded_String;
      Name : Ada.Strings.Unbounded.Unbounded_String;
      Adjective : Ada.Strings.Unbounded.Unbounded_String;
      Plural : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Create
     (Identifier : String;
      Name : String;
      Adjective : String;
      Plural : String)
      return Faction_Record
   is (Faction_Record'
         (Identifier => Ada.Strings.Unbounded.To_Unbounded_String (Identifier),
          Name => Ada.Strings.Unbounded.To_Unbounded_String (Name),
          Adjective => Ada.Strings.Unbounded.To_Unbounded_String (Adjective),
          Plural => Ada.Strings.Unbounded.To_Unbounded_String (Plural)));

   function Identifier (Self : Faction_Record) return String
   is (Ada.Strings.Unbounded.To_String (Self.Identifier));
   function Name (Self : Faction_Record) return String
   is (Ada.Strings.Unbounded.To_String (Self.Name));
   function Adjective (Self : Faction_Record) return String
   is (Ada.Strings.Unbounded.To_String (Self.Adjective));
   function Plural (Self : Faction_Record) return String
   is (Ada.Strings.Unbounded.To_String (Self.Plural));

end Concorde.Api.Responses;
