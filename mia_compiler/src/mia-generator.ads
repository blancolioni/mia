with Mia.Model;

package Mia.Generator is

   Generator_Error : exception;

   procedure Generate
     (Spec       : Mia.Model.Package_Spec;
      Output_Dir : String);

end Mia.Generator;
