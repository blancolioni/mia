with Ada.Strings.Unbounded;

package Test.Api.Types is

   type Named_Object is abstract tagged private;

   function Slug (Self : Named_Object) return String;
   function Name (Self : Named_Object) return String;

   function To_Json
     (Self   : Named_Object;
      Prefix : String := "") return String is abstract;

   type Celestial_Object is abstract new Named_Object with private;

   function Mass (Self : Celestial_Object) return Float;
   function Radius (Self : Celestial_Object) return Float;

   overriding function To_Json
     (Self   : Celestial_Object;
      Prefix : String := "") return String is abstract;

   type Star is new Celestial_Object with private;

   function Create
     (Slug : String;
      Name : String;
      Mass : Float;
      Radius : Float;
      Spectral_Class : String;
      Luminosity : Float)
      return Star;

   function Spectral_Class (Self : Star) return String;
   function Luminosity (Self : Star) return Float;

   overriding function To_Json
     (Self   : Star;
      Prefix : String := "") return String;

   type World is new Celestial_Object with private;

   function Create
     (Slug : String;
      Name : String;
      Mass : Float;
      Radius : Float;
      Orbit_Zone : String;
      Climate : String)
      return World;

   function Orbit_Zone (Self : World) return String;
   function Climate (Self : World) return String;

   overriding function To_Json
     (Self   : World;
      Prefix : String := "") return String;

private

   type Named_Object is abstract tagged record
      Slug : Ada.Strings.Unbounded.Unbounded_String;
      Name : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   function Slug (Self : Named_Object) return String
   is (Ada.Strings.Unbounded.To_String (Self.Slug));
   function Name (Self : Named_Object) return String
   is (Ada.Strings.Unbounded.To_String (Self.Name));

   type Celestial_Object is abstract new Named_Object with record
      Mass : Float;
      Radius : Float;
   end record;
   function Mass (Self : Celestial_Object) return Float
   is (Self.Mass);
   function Radius (Self : Celestial_Object) return Float
   is (Self.Radius);

   type Star is new Celestial_Object with record
      Spectral_Class : Ada.Strings.Unbounded.Unbounded_String;
      Luminosity : Float;
   end record;

   function Create
     (Slug : String;
      Name : String;
      Mass : Float;
      Radius : Float;
      Spectral_Class : String;
      Luminosity : Float)
      return Star
   is (Celestial_Object with
         Slug => Ada.Strings.Unbounded.To_Unbounded_String (Slug),
         Name => Ada.Strings.Unbounded.To_Unbounded_String (Name),
         Mass => Mass,
         Radius => Radius,
         Spectral_Class => Ada.Strings.Unbounded.To_Unbounded_String (Spectral_Class),
         Luminosity => Luminosity);

   function Spectral_Class (Self : Star) return String
   is (Ada.Strings.Unbounded.To_String (Self.Spectral_Class));
   function Luminosity (Self : Star) return Float
   is (Self.Luminosity);

   type World is new Celestial_Object with record
      Orbit_Zone : Ada.Strings.Unbounded.Unbounded_String;
      Climate : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Create
     (Slug : String;
      Name : String;
      Mass : Float;
      Radius : Float;
      Orbit_Zone : String;
      Climate : String)
      return World
   is (Celestial_Object with
         Slug => Ada.Strings.Unbounded.To_Unbounded_String (Slug),
         Name => Ada.Strings.Unbounded.To_Unbounded_String (Name),
         Mass => Mass,
         Radius => Radius,
         Orbit_Zone => Ada.Strings.Unbounded.To_Unbounded_String (Orbit_Zone),
         Climate => Ada.Strings.Unbounded.To_Unbounded_String (Climate));

   function Orbit_Zone (Self : World) return String
   is (Ada.Strings.Unbounded.To_String (Self.Orbit_Zone));
   function Climate (Self : World) return String
   is (Ada.Strings.Unbounded.To_String (Self.Climate));

end Test.Api.Types;
