
package body Concorde.Api.Responses is

   function To_Json
     (Self   : Faction_Record;
      Prefix : String := "") return String is
      function Quote (S : String) return String is
         R : String (1 .. S'Length * 2 + 2);
         P : Positive := 2;
      begin
         R (1) := '"';
         for C of S loop
            if C = '"' or else C = '\' then
               R (P) := '\'; P := P + 1;
            end if;
            R (P) := C; P := P + 1;
         end loop;
         R (P) := '"';
         return R (1 .. P);
      end Quote;
   begin
      return
        "{" &
        """identifier"":" & Quote (Identifier (Self)) &
        ",""name"":" & Quote (Name (Self)) &
        ",""adjective"":" & Quote (Adjective (Self)) &
        ",""plural"":" & Quote (Plural (Self)) &
        ",""_links"":{" &
        """self"":{""href"":" & Quote (Prefix & "/factions/" & Slug (Self)) & "}" &
        "}}";
   end To_Json;

end Concorde.Api.Responses;
