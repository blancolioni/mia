with Mia.Model;

package Mia.Parser is

   Parse_Error : exception;

   function Parse (Source : String) return Mia.Model.Package_Spec;

end Mia.Parser;
