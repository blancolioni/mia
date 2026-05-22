with Ada.Strings.Unbounded;

package Notes is

   type Note_Importance is (High, Normal, Low);

   type Note_Properties is record
      Author     : Ada.Strings.Unbounded.Unbounded_String;
      Importance : Note_Importance;
      Category   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

end Notes;
