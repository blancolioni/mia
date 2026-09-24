with Ada.Strings.Unbounded;
with GNATCOLL.JSON;

package body Concorde.Api.Responses is

   function To_Json (Self : Faction_Record) return String is
      Obj : constant GNATCOLL.JSON.JSON_Value :=
              GNATCOLL.JSON.Create_Object;
   begin
      GNATCOLL.JSON.Set_Field
        (Obj, "identifier", Ada.Strings.Unbounded.To_String (Self.Identifier));
      GNATCOLL.JSON.Set_Field
        (Obj, "name", Ada.Strings.Unbounded.To_String (Self.Name));
      GNATCOLL.JSON.Set_Field
        (Obj, "adjective", Ada.Strings.Unbounded.To_String (Self.Adjective));
      GNATCOLL.JSON.Set_Field
        (Obj, "plural", Ada.Strings.Unbounded.To_String (Self.Plural));
      return GNATCOLL.JSON.Write (Obj);
   end To_Json;

end Concorde.Api.Responses;
