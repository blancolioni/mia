with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Mia.Generator;
with Mia.Model;
with Mia.Parser;

procedure Mia.Main is

   use Ada.Text_IO;

   function Read_File (Path : String) return String is
      use Ada.Strings.Unbounded;
      File   : File_Type;
      Buffer : Unbounded_String;
   begin
      Open (File, In_File, Path);
      while not End_Of_File (File) loop
         Append (Buffer, Get_Line (File));
         Append (Buffer, ASCII.LF);
      end loop;
      Close (File);
      return To_String (Buffer);
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         raise;
   end Read_File;

begin
   if Ada.Command_Line.Argument_Count < 1 then
      Put_Line (Standard_Error, "usage: mia <input.mia> [output-dir]");
      Ada.Command_Line.Set_Exit_Status (1);
      return;
   end if;

   declare
      Input_Path : constant String :=
                     Ada.Command_Line.Argument (1);
      Output_Dir : constant String :=
                     (if Ada.Command_Line.Argument_Count >= 2
                      then Ada.Command_Line.Argument (2)
                      else ".");
      Source : constant String  := Read_File (Input_Path);
      Spec   : Mia.Model.Package_Spec;
   begin
      Spec := Mia.Parser.Parse (Source);
      Mia.Generator.Generate (Spec, Output_Dir);
   end;
exception
   when E : Mia.Parser.Parse_Error | Mia.Generator.Generator_Error =>
      Put_Line
        (Standard_Error, Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (1);
   when E : Ada.Text_IO.Name_Error =>
      Put_Line
        (Standard_Error, Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (1);
end Mia.Main;
