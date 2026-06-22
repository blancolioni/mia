with Ada.Containers.Doubly_Linked_Lists;
with Ada.Containers.Indefinite_Doubly_Linked_Lists;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AWS.Config.Set;
with AWS.Headers;
with AWS.Messages;
with AWS.Parameters;
with AWS.Response.Set;
with AWS.Server;
with Mia.Api_Exceptions;
with Mia.Registry;

package body Mia.Server is

   type Route_Entry is
      record
         URI             : Ada.Strings.Unbounded.Unbounded_String;
         Handler         : Service_Handler;
         Method          : AWS.Status.Request_Method;
         Allow_Anonymous : Boolean;
      end record;

   package Route_Lists is
     new Ada.Containers.Doubly_Linked_Lists (Route_Entry);

   Route_List : Route_Lists.List;

   package String_Lists is
     new Ada.Containers.Indefinite_Doubly_Linked_Lists (String);

   function Split
     (S  : String;
      Ch : Character)
      return String_Lists.List;

   function Match
     (URI        : String;
      Template   : String;
      Parameters : out Service_Parameters)
      return Boolean;

   function Call
     (Handler    : Service_Handler;
      URI        : String;
      Session_Id : String;
      Parameters : Service_Parameters)
      return AWS.Response.Data;

   function Handle_Options
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data;

   WS     : AWS.Server.HTTP;

   ----------
   -- Call --
   ----------

   function Call
     (Handler    : Service_Handler;
      URI        : String;
      Session_Id : String;
      Parameters : Service_Parameters)
      return AWS.Response.Data
   is
   begin
      return Handler
        (Session_Id => Session_Id,
         URI        => URI,
         Parameters => Parameters);
   end Call;

   --------------------
   -- Handle_Options --
   --------------------

   function Handle_Options
     (Session_Id : String;
      URI        : String;
      Parameters : Mia.Server.Service_Parameters)
      return AWS.Response.Data
   is
      pragma Unreferenced (Session_Id, URI, Parameters);
   begin
      return AWS.Response.Build ("text/plain", "OK");
   end Handle_Options;

   -----------
   -- Match --
   -----------

   function Match
     (URI        : String;
      Template   : String;
      Parameters : out Service_Parameters)
      return Boolean
   is
      use String_Lists;
      Left_List  : constant List := Split (URI, '/');
      Right_List : constant List := Split (Template, '/');
      Left_Pos   : Cursor := Left_List.First;
      Right_Pos  : Cursor := Right_List.First;
   begin
      while Has_Element (Left_Pos) and then Has_Element (Right_Pos) loop
         declare
            Left : constant String := Element (Left_Pos);
            Right : constant String := Element (Right_Pos);
            Same : constant Boolean := Left = Right;
         begin
            if Same
              or else (Right'Length > 2
                       and then Right (Right'First) = '{'
                       and then Right (Right'Last) = '}')
            then
               if not Same then
                  Parameters.Map.Insert
                    (Right (Right'First + 1 .. Right'Last - 1),
                     Left);
               end if;
               Next (Left_Pos);
               Next (Right_Pos);
            else
               exit;
            end if;
         end;
      end loop;

      return not Has_Element (Left_Pos)
        and then not Has_Element (Right_Pos);
   end Match;

   --------------
   -- Register --
   --------------

   procedure Register
     (Route           : String;
      Handler         : Service_Handler;
      Method          : AWS.Status.Request_Method := AWS.Status.GET;
      Allow_Anonymous : Boolean := True)
   is
      use type AWS.Status.Request_Method;
   begin
      Route_List.Append
        (Route_Entry'
           (URI             =>
                Ada.Strings.Unbounded.To_Unbounded_String (Route),
            Handler         => Handler,
            Method          => Method,
            Allow_Anonymous => Allow_Anonymous));
      if Method = AWS.Status.POST or else Method = AWS.Status.GET then
         Register (Route, Handle_Options'Access,
                   AWS.Status.OPTIONS, Allow_Anonymous => True);
      end if;
   end Register;

   -------------
   -- Service --
   -------------

   function Service
     (Request : AWS.Status.Data)
      return AWS.Response.Data
   is
      use all type AWS.Status.Request_Method;
      URI : constant String := AWS.Status.URI (Request);
      Method   : constant AWS.Status.Request_Method :=
                   AWS.Status.Method (Request);
      Full_URL : constant String := AWS.Status.URL (Request);
      Q_Mark   : constant Natural :=
                   Ada.Strings.Fixed.Index
                     (Full_URL, "?", Going => Ada.Strings.Backward);
      Slash    : constant Natural :=
                   Ada.Strings.Fixed.Index
                     (Full_URL, "/", Going => Ada.Strings.Backward);
      Last     : constant Natural :=
                   (if Q_Mark = 0
                    then (if Slash = Full_URL'Last
                      then Slash - 1
                      else Full_URL'Last)
                    else Q_Mark - 1);
      URL : constant String :=
                   Full_URL (Full_URL'First .. Last) & "/";
      Query    : constant AWS.Parameters.List :=
                   AWS.Status.Parameters (Request);
      Headers  : constant AWS.Headers.List :=
                   AWS.Status.Header (Request);
      Auth_Header : constant String := Headers.Get_Values ("Authorization");
      Bearer_Prefix : constant String := "Bearer ";
      Session_Id : constant String :=
                     (if Auth_Header'Length > Bearer_Prefix'Length
                        and then Auth_Header
                                   (Auth_Header'First
                                    .. Auth_Header'First
                                       + Bearer_Prefix'Length - 1)
                                 = Bearer_Prefix
                      then Auth_Header
                             (Auth_Header'First + Bearer_Prefix'Length
                              .. Auth_Header'Last)
                      else "");
   begin

      for Element of Route_List loop
         declare
            Parameters : Service_Parameters;
            Route_URI  : constant String :=
                           Ada.Strings.Unbounded.To_String
                             (Element.URI);
         begin
            if Element.Method = Method
              and then Match (URI, Route_URI, Parameters)
            then

               if Session_Id = "" and then not Element.Allow_Anonymous then
                  return AWS.Response.Build
                    (Status_Code  => AWS.Messages.S401,
                     Content_Type => "text/plain",
                     Message_Body => "Unauthorized");
               end if;

               for I in 1 .. Query.Count loop
                  Parameters.Map.Insert (Query.Get_Name (I),
                                         Query.Get_Value (I));
               end loop;

               declare
                  Body_Str : constant String :=
                               Ada.Strings.Unbounded.To_String
                                 (AWS.Status.Binary_Data (Request));
               begin
                  if Body_Str /= "" then
                     Parameters.Map.Insert ("__body__", Body_Str);
                  end if;
               end;

               declare
                  Handler : constant Service_Handler := Element.Handler;
                  Response : AWS.Response.Data :=
                               Call
                                 (Handler    => Handler,
                                  URI        => URL,
                                  Session_Id => Session_Id,
                                  Parameters => Parameters);
               begin
                  AWS.Response.Set.Add_Header
                    (Response,
                     "Access-Control-Allow-Origin",
                     "http://localhost:5173");

                  AWS.Response.Set.Add_Header
                    (Response, "Access-Control-Allow-Methods",
                     "GET, POST, OPTIONS");

                  AWS.Response.Set.Add_Header
                    (Response, "Access-Control-Allow-Headers",
                     "Content-Type, Authorization");
                  return Response;
               end;
            end if;
         end;
      end loop;
      return AWS.Response.Build
        (Content_Type => "text/html",
         Message_Body => "<p>not found: " & URI,
         Status_Code  => AWS.Messages.S404);
   exception
      when Mia.Api_Exceptions.Not_Found =>
         return AWS.Response.Build
           (Status_Code  => AWS.Messages.S404,
            Content_Type => "application/json",
            Message_Body => "{""error"":""not found""}");
      when Mia.Api_Exceptions.Unauthorized =>
         return AWS.Response.Build
           (Status_Code  => AWS.Messages.S401,
            Content_Type => "application/json",
            Message_Body => "{""error"":""unauthorized""}");
      when Mia.Api_Exceptions.Bad_Request =>
         return AWS.Response.Build
           (Status_Code  => AWS.Messages.S400,
            Content_Type => "application/json",
            Message_Body => "{""error"":""bad request""}");
   end Service;

   -----------
   -- Split --
   -----------

   function Split
     (S  : String;
      Ch : Character)
      return String_Lists.List
   is
      use Ada.Strings.Fixed;
      First : Positive := S'First;
      Last  : Natural := S'Last;
   begin
      while First <= S'Length
        and then S (First) = Ch
      loop
         First := First + 1;
      end loop;

      return List : String_Lists.List do
         while First <= S'Last loop
            Last := Index (S, [Ch], First);
            if Last > 0 then
               List.Append (S (First .. Last - 1));
               First := Last + 1;
            else
               List.Append (S (First .. S'Last));
               First := S'Last + 1;
            end if;
         end loop;
      end return;
   end Split;

   -----------
   -- Start --
   -----------

   procedure Start is
      Config : AWS.Config.Object := AWS.Config.Get_Current;
   begin
      Register ("/swagger", Mia.Registry.Handle_Swagger'Access);

      AWS.Config.Set.Server_Name (Config, "mia-server");
      AWS.Config.Set.Server_Port (Config, 8080);

      AWS.Server.Start (WS, Service'Access, Config);
      AWS.Server.Wait (Mode => AWS.Server.No_Server);
   end Start;

   ----------
   -- Stop --
   ----------

   procedure Stop (Message : String) is
      pragma Unreferenced (Message);
   begin
      AWS.Server.Shutdown (WS);
   end Stop;

   -----------
   -- Value --
   -----------

   function Value (Parameters : Service_Parameters;
                   Key        : String)
                   return String
   is
      Position : constant Parameter_Maps.Cursor := Parameters.Map.Find (Key);
   begin
      if Parameter_Maps.Has_Element (Position) then
         return Parameter_Maps.Element (Position);
      else
         return "";
      end if;
   end Value;

end Mia.Server;
