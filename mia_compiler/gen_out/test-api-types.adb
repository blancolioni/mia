with Ada.Text_IO;
with Ada.Strings.Fixed;

package body Test.Api.Types is

   overriding function To_Json
     (Self   : Star;
      Prefix : String := "") return String is
      function Fmt_Float (V : Long_Float) return String is
         package LF_IO is new Ada.Text_IO.Float_IO (Long_Float);
         S : String (1 .. 50) := [others => ' '];
      begin
         LF_IO.Put (To => S, Item => V, Aft => 15, Exp => 0);
         return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
      end Fmt_Float;
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
        """kind"":" & """star""" &
        ",""slug"":" & Quote (Slug (Self)) &
        ",""name"":" & Quote (Name (Self)) &
        ",""mass"":" & Fmt_Float (Long_Float (Mass (Self))) &
        ",""radius"":" & Fmt_Float (Long_Float (Radius (Self))) &
        ",""spectral_class"":" & Quote (Spectral_Class (Self)) &
        ",""luminosity"":" & Fmt_Float (Long_Float (Luminosity (Self))) &
        "}";
   end To_Json;

   overriding function To_Json
     (Self   : World;
      Prefix : String := "") return String is
      function Fmt_Float (V : Long_Float) return String is
         package LF_IO is new Ada.Text_IO.Float_IO (Long_Float);
         S : String (1 .. 50) := [others => ' '];
      begin
         LF_IO.Put (To => S, Item => V, Aft => 15, Exp => 0);
         return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
      end Fmt_Float;
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
        """kind"":" & """world""" &
        ",""slug"":" & Quote (Slug (Self)) &
        ",""name"":" & Quote (Name (Self)) &
        ",""mass"":" & Fmt_Float (Long_Float (Mass (Self))) &
        ",""radius"":" & Fmt_Float (Long_Float (Radius (Self))) &
        ",""orbit_zone"":" & Quote (Orbit_Zone (Self)) &
        ",""climate"":" & Quote (Climate (Self)) &
        "}";
   end To_Json;

end Test.Api.Types;
