--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT

package body GL is

   use type C.int;

   function Compile (Kind : GLenum; Source : String) return GLuint is
      Text : aliased C.char_array := C.To_C (Source);
      Ptr  : aliased System.Address := Text'Address;
      S    : constant GLuint := Create_Shader (Kind);
      Ok   : aliased GLint := 0;
   begin
      Shader_Source (S, 1, Ptr'Address, System.Null_Address);
      Compile_Shader (S);
      Get_Shader_Iv (S, GL_COMPILE_STATUS, Ok'Access);
      if Ok = 0 then
         declare
            Log : aliased C.char_array (1 .. 4096) := (others => C.nul);
            Len : aliased GLsizei := 0;
         begin
            Get_Shader_Info_Log (S, Log'Length, Len'Access, Log'Address);
            raise Program_Error with "shader: " & C.To_Ada (Log);
         end;
      end if;
      return S;
   end Compile;

   function Build_Program (Vertex, Fragment : String) return GLuint is
      P  : constant GLuint := Create_Program.all;
      Ok : aliased GLint := 0;
   begin
      Attach_Shader (P, Compile (GL_VERTEX_SHADER, Vertex));
      Attach_Shader (P, Compile (GL_FRAGMENT_SHADER, Fragment));
      Link_Program (P);
      Get_Program_Iv (P, GL_LINK_STATUS, Ok'Access);
      if Ok = 0 then
         declare
            Log : aliased C.char_array (1 .. 4096) := (others => C.nul);
            Len : aliased GLsizei := 0;
         begin
            Get_Program_Info_Log (P, Log'Length, Len'Access, Log'Address);
            raise Program_Error with "program: " & C.To_Ada (Log);
         end;
      end if;
      return P;
   end Build_Program;

   function Uniform (Program : GLuint; Name : String) return GLint is
      N : aliased constant C.char_array := C.To_C (Name);
   begin
      return Get_Uniform_Location (Program, N'Address);
   end Uniform;

end GL;
