generic
   type Real is digits <>;
package Voronoi_Diagrams is

   type Point is record
      X : Real;
      Y : Real;
   end record;

   type Point_Array is
     array (Positive range <>) of Point;

   type Instance is tagged private;

   procedure Clear (This : in out Instance);

   procedure Add_Site (This : in out Instance; X, Y : Real);
   procedure Add_Site (This : in out Instance; Site : Point);

   procedure Generate
      (This : in out Instance);

   function Get_Cell_Count (This : Instance) return Natural;

   function Get_Cell_Site
      (This       : Instance;
       Cell_Index : Natural)
       return Point;

   function Get_Cell_Vertices
      (This       : Instance;
       Cell_Index : Natural)
       return Point_Array;

private

   package Point_Vectors is
     new Ada.Containers.Vectors
      (Index_Type => Positive, Element_Type => Point);

   package Vertex_Array is array (Positive range <>) of Positive;

   type Polygon (Count : Natural) is 
      record
         Vertices : Vertex_Array (1 .. Count);
      end record;

   type Polygon_Vectors is
      new Ada.Containers.Indefinite_Vectors
        (Index_Type => Positive, Element_Type => Polygon);

   type Instance is tagged 
      record
         Sites : Point_Vectors.Vector;
         Cells : Polygon_Vectors.Vector;
      end record;

end Voronoi_Diagrams;

