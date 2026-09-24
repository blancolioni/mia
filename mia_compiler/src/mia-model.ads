with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package Mia.Model is

   type Http_Method is (Get, Post, Put, Delete, Patch);

   --  Type declarations from the .mia spec

   --  Omit_Empty ('with Omit_Empty' on a String field) leaves the key
   --  out of the generated JSON altogether when the value is "".
   type Type_Field is record
      Name       : Ada.Strings.Unbounded.Unbounded_String;
      Type_Name  : Ada.Strings.Unbounded.Unbounded_String;
      Omit_Empty : Boolean := False;
   end record;

   package Type_Field_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Field);

   type Link_Binding is record
      Param_Name : Ada.Strings.Unbounded.Unbounded_String;
      Field_Name : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Binding_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Link_Binding);

   type Link_Spec is record
      Name          : Ada.Strings.Unbounded.Unbounded_String;
      Function_Name : Ada.Strings.Unbounded.Unbounded_String;
      Bindings      : Binding_Vectors.Vector;
   end record;

   package Link_Spec_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Link_Spec);

   type Type_Kind is (Enum_Type, Record_Type);

   type Type_Spec (Kind : Type_Kind := Enum_Type) is record
      Name        : Ada.Strings.Unbounded.Unbounded_String;
      To_Json     : Ada.Strings.Unbounded.Unbounded_String;
      Links       : Link_Spec_Vectors.Vector;
      Parent      : Ada.Strings.Unbounded.Unbounded_String;
      --  Qualified name of parent type; empty for root types
      Variant_Tag : Ada.Strings.Unbounded.Unbounded_String;
      --  Lowercased Kind aspect value; empty means abstract/intermediate
      case Kind is
         when Enum_Type =>
            --  External enum: literals live in the declaring Ada package
            --  and are discovered at runtime via the type's attributes.
            null;
         when Record_Type =>
            Fields : Type_Field_Vectors.Vector;
      end case;
   end record;

   package Type_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Spec);

   type Auth_Kind is (Inherited, Anonymous);

   type Parameter_Type is record
      Name      : Ada.Strings.Unbounded.Unbounded_String;
      Type_Name : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Parameter_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Parameter_Type);

   type Function_Spec is record
      Name        : Ada.Strings.Unbounded.Unbounded_String;
      Parameters  : Parameter_Vectors.Vector;
      Return_Type : Ada.Strings.Unbounded.Unbounded_String;
      Is_Array    : Boolean    := False;
      Method      : Http_Method := Get;
      Path        : Ada.Strings.Unbounded.Unbounded_String;
      Impl        : Ada.Strings.Unbounded.Unbounded_String;
      Scanner     : Ada.Strings.Unbounded.Unbounded_String;
      To_Json     : Ada.Strings.Unbounded.Unbounded_String;
      From_Body   : Ada.Strings.Unbounded.Unbounded_String;
      From_Json   : Ada.Strings.Unbounded.Unbounded_String;
      Body_Schema : Ada.Strings.Unbounded.Unbounded_String;
      Auth        : Auth_Kind := Inherited;
   end record;

   package Function_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Function_Spec);

   --  A server -> client push event on a channel. Payload_Type names a
   --  declared response type; its To_Json is reused for the wire form.
   type Emit_Spec is record
      Name         : Ada.Strings.Unbounded.Unbounded_String;
      Payload_Type : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Emit_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Emit_Spec);

   --  A WebSocket channel. Handlers are the client -> server commands,
   --  dispatched by the "action" discriminator; each reuses Function_Spec
   --  (only Name/Parameters/Impl are meaningful for channel handlers).
   type Channel_Spec is record
      Name     : Ada.Strings.Unbounded.Unbounded_String;
      Path     : Ada.Strings.Unbounded.Unbounded_String;
      Auth     : Auth_Kind := Inherited;
      Emits    : Emit_Vectors.Vector;
      Handlers : Function_Vectors.Vector;
      On_Open  : Ada.Strings.Unbounded.Unbounded_String;
      On_Close : Ada.Strings.Unbounded.Unbounded_String;
      On_Error : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Channel_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Channel_Spec);

   type Package_Spec is record
      Name         : Ada.Strings.Unbounded.Unbounded_String;
      Functions    : Function_Vectors.Vector;
      Session_Type : Ada.Strings.Unbounded.Unbounded_String;
      Types        : Type_Vectors.Vector;
      Channels     : Channel_Vectors.Vector;
   end record;

end Mia.Model;
