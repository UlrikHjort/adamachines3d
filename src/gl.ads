--  Adamachines 3D: tiny cars racing round the house, in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The few OpenGL 3.3 calls the game makes.  libepoxy holds a pointer to
--  each GL function, found on its first call, so these are those pointers
--  taken straight from epoxy, and Ada calls through them.

with Interfaces.C;
with System;

package GL is

   use Interfaces;

   subtype GLenum is C.unsigned;
   subtype GLbitfield is C.unsigned;
   subtype GLuint is C.unsigned;
   subtype GLint is C.int;
   subtype GLsizei is C.int;
   subtype GLfloat is C.C_float;
   subtype GLboolean is C.unsigned_char;
   subtype GLsizeiptr is C.ptrdiff_t;
   subtype GLintptr is C.ptrdiff_t;
   type GLuint_Access is access all GLuint with Convention => C;
   type GLint_Access is access all GLint with Convention => C;

   GL_FALSE : constant GLboolean := 0;
   GL_TRUE  : constant GLboolean := 1;

   GL_DEPTH_BUFFER_BIT   : constant := 16#0100#;
   GL_COLOR_BUFFER_BIT   : constant := 16#4000#;
   GL_TRIANGLES          : constant := 16#0004#;
   GL_LEQUAL             : constant := 16#0203#;
   GL_SRC_ALPHA          : constant := 16#0302#;
   GL_ONE_MINUS_SRC_ALPHA : constant := 16#0303#;
   GL_ONE                : constant := 1;
   GL_BACK               : constant := 16#0405#;
   GL_CULL_FACE          : constant := 16#0B44#;
   GL_DEPTH_TEST         : constant := 16#0B71#;
   GL_BLEND              : constant := 16#0BE2#;
   GL_UNPACK_ROW_LENGTH  : constant := 16#0CF2#;
   GL_UNPACK_ALIGNMENT   : constant := 16#0CF5#;
   GL_PACK_ALIGNMENT     : constant := 16#0D05#;
   GL_TEXTURE_2D         : constant := 16#0DE1#;
   GL_UNSIGNED_BYTE      : constant := 16#1401#;
   GL_FLOAT              : constant := 16#1406#;
   GL_RGBA               : constant := 16#1908#;
   GL_RGB8               : constant := 16#8051#;
   GL_RGBA8              : constant := 16#8058#;
   GL_BGRA               : constant := 16#80E1#;
   GL_LINEAR             : constant := 16#2601#;
   GL_LINEAR_MIPMAP_LINEAR : constant := 16#2703#;
   GL_TEXTURE_MAG_FILTER : constant := 16#2800#;
   GL_TEXTURE_MIN_FILTER : constant := 16#2801#;
   GL_TEXTURE_WRAP_S     : constant := 16#2802#;
   GL_TEXTURE_WRAP_T     : constant := 16#2803#;
   GL_CLAMP_TO_EDGE      : constant := 16#812F#;
   GL_TEXTURE_MAX_ANISOTROPY : constant := 16#84FE#;
   GL_TEXTURE0           : constant := 16#84C0#;
   GL_ARRAY_BUFFER       : constant := 16#8892#;
   GL_STATIC_DRAW        : constant := 16#88E4#;
   GL_STREAM_DRAW        : constant := 16#88E0#;
   GL_FRAGMENT_SHADER    : constant := 16#8B30#;
   GL_VERTEX_SHADER      : constant := 16#8B31#;
   GL_COMPILE_STATUS     : constant := 16#8B81#;
   GL_LINK_STATUS        : constant := 16#8B82#;
   GL_MAX_TEXTURE_SIZE   : constant := 16#0D33#;

   type Clear_Color_T is access procedure (R, G, B, A : GLfloat) with Convention => C;
   Clear_Color : Clear_Color_T with Import, Convention => C, External_Name => "epoxy_glClearColor";

   type Clear_T is access procedure (Mask : GLbitfield) with Convention => C;
   Clear : Clear_T with Import, Convention => C, External_Name => "epoxy_glClear";

   type Cap_T is access procedure (Cap : GLenum) with Convention => C;
   Enable : Cap_T with Import, Convention => C, External_Name => "epoxy_glEnable";
   Disable : Cap_T with Import, Convention => C, External_Name => "epoxy_glDisable";
   Depth_Func : Cap_T with Import, Convention => C, External_Name => "epoxy_glDepthFunc";
   Cull_Face : Cap_T with Import, Convention => C, External_Name => "epoxy_glCullFace";
   Active_Texture : Cap_T with Import, Convention => C, External_Name => "epoxy_glActiveTexture";
   Generate_Mipmap : Cap_T with Import, Convention => C, External_Name => "epoxy_glGenerateMipmap";

   type Depth_Mask_T is access procedure (Flag : GLboolean) with Convention => C;
   Depth_Mask : Depth_Mask_T with Import, Convention => C, External_Name => "epoxy_glDepthMask";

   type Viewport_T is access procedure (X, Y : GLint; W, H : GLsizei) with Convention => C;
   Viewport : Viewport_T with Import, Convention => C, External_Name => "epoxy_glViewport";

   Scissor : Viewport_T with Import, Convention => C, External_Name => "epoxy_glScissor";
   GL_SCISSOR_TEST : constant := 16#0C11#;

   type Polygon_Offset_T is access procedure (Factor, Units : GLfloat) with Convention => C;
   Polygon_Offset : Polygon_Offset_T with Import, Convention => C, External_Name => "epoxy_glPolygonOffset";
   GL_POLYGON_OFFSET_FILL : constant := 16#8037#;

   type Blend_Func_T is access procedure (S, D : GLenum) with Convention => C;
   Blend_Func : Blend_Func_T with Import, Convention => C, External_Name => "epoxy_glBlendFunc";

   type Get_Integer_T is access procedure (Name : GLenum; V : access GLint) with Convention => C;
   Get_Integer : Get_Integer_T with Import, Convention => C, External_Name => "epoxy_glGetIntegerv";

   --  Shaders and programs
   type Create_Shader_T is access function (Kind : GLenum) return GLuint with Convention => C;
   Create_Shader : Create_Shader_T with Import, Convention => C, External_Name => "epoxy_glCreateShader";

   type Shader_Source_T is access procedure
     (Shader : GLuint; Count : GLsizei; Text : System.Address; Lengths : System.Address)
     with Convention => C;
   Shader_Source : Shader_Source_T with Import, Convention => C, External_Name => "epoxy_glShaderSource";

   type Object_T is access procedure (Id : GLuint) with Convention => C;
   Compile_Shader : Object_T with Import, Convention => C, External_Name => "epoxy_glCompileShader";
   Link_Program : Object_T with Import, Convention => C, External_Name => "epoxy_glLinkProgram";
   Use_Program : Object_T with Import, Convention => C, External_Name => "epoxy_glUseProgram";
   Bind_Vertex_Array : Object_T with Import, Convention => C, External_Name => "epoxy_glBindVertexArray";
   Enable_Vertex_Attrib_Array : Object_T
     with Import, Convention => C, External_Name => "epoxy_glEnableVertexAttribArray";

   type Get_Iv_T is access procedure (Id : GLuint; Name : GLenum; V : access GLint) with Convention => C;
   Get_Shader_Iv : Get_Iv_T with Import, Convention => C, External_Name => "epoxy_glGetShaderiv";
   Get_Program_Iv : Get_Iv_T with Import, Convention => C, External_Name => "epoxy_glGetProgramiv";

   type Get_Log_T is access procedure
     (Id : GLuint; Max : GLsizei; Length : access GLsizei; Log : System.Address) with Convention => C;
   Get_Shader_Info_Log : Get_Log_T with Import, Convention => C, External_Name => "epoxy_glGetShaderInfoLog";
   Get_Program_Info_Log : Get_Log_T with Import, Convention => C, External_Name => "epoxy_glGetProgramInfoLog";

   type Create_Program_T is access function return GLuint with Convention => C;
   Create_Program : Create_Program_T with Import, Convention => C, External_Name => "epoxy_glCreateProgram";

   type Attach_T is access procedure (Program, Shader : GLuint) with Convention => C;
   Attach_Shader : Attach_T with Import, Convention => C, External_Name => "epoxy_glAttachShader";

   type Uniform_Location_T is access function (Program : GLuint; Name : System.Address) return GLint
     with Convention => C;
   Get_Uniform_Location : Uniform_Location_T
     with Import, Convention => C, External_Name => "epoxy_glGetUniformLocation";

   type Uniform1i_T is access procedure (Loc : GLint; V : GLint) with Convention => C;
   Uniform1i : Uniform1i_T with Import, Convention => C, External_Name => "epoxy_glUniform1i";
   type Uniform1f_T is access procedure (Loc : GLint; V : GLfloat) with Convention => C;
   Uniform1f : Uniform1f_T with Import, Convention => C, External_Name => "epoxy_glUniform1f";
   type Uniform3f_T is access procedure (Loc : GLint; X, Y, Z : GLfloat) with Convention => C;
   Uniform3f : Uniform3f_T with Import, Convention => C, External_Name => "epoxy_glUniform3f";
   type Uniformv_T is access procedure (Loc : GLint; Count : GLsizei; V : System.Address) with Convention => C;
   Uniform3fv : Uniformv_T with Import, Convention => C, External_Name => "epoxy_glUniform3fv";
   type Uniform_Matrix_T is access procedure
     (Loc : GLint; Count : GLsizei; Transpose : GLboolean; V : System.Address) with Convention => C;
   Uniform_Matrix4fv : Uniform_Matrix_T
     with Import, Convention => C, External_Name => "epoxy_glUniformMatrix4fv";

   --  Buffers and vertex arrays
   type Gen_T is access procedure (N : GLsizei; Ids : access GLuint) with Convention => C;
   Gen_Vertex_Arrays : Gen_T with Import, Convention => C, External_Name => "epoxy_glGenVertexArrays";
   Gen_Buffers : Gen_T with Import, Convention => C, External_Name => "epoxy_glGenBuffers";
   Gen_Textures : Gen_T with Import, Convention => C, External_Name => "epoxy_glGenTextures";
   Delete_Textures : Gen_T with Import, Convention => C, External_Name => "epoxy_glDeleteTextures";

   type Bind_T is access procedure (Target : GLenum; Id : GLuint) with Convention => C;
   Bind_Buffer : Bind_T with Import, Convention => C, External_Name => "epoxy_glBindBuffer";
   Bind_Texture : Bind_T with Import, Convention => C, External_Name => "epoxy_glBindTexture";

   type Buffer_Data_T is access procedure
     (Target : GLenum; Size : GLsizeiptr; Data : System.Address; Usage : GLenum) with Convention => C;
   Buffer_Data : Buffer_Data_T with Import, Convention => C, External_Name => "epoxy_glBufferData";

   type Attrib_Pointer_T is access procedure
     (Index : GLuint; Size : GLint; Kind : GLenum; Normalized : GLboolean; Stride : GLsizei;
      Offset : System.Address) with Convention => C;
   Vertex_Attrib_Pointer : Attrib_Pointer_T
     with Import, Convention => C, External_Name => "epoxy_glVertexAttribPointer";

   type Draw_Arrays_T is access procedure (Mode : GLenum; First : GLint; Count : GLsizei) with Convention => C;
   Draw_Arrays : Draw_Arrays_T with Import, Convention => C, External_Name => "epoxy_glDrawArrays";

   --  Textures
   type Tex_Parameteri_T is access procedure (Target, Name : GLenum; V : GLint) with Convention => C;
   Tex_Parameteri : Tex_Parameteri_T with Import, Convention => C, External_Name => "epoxy_glTexParameteri";
   type Tex_Parameterf_T is access procedure (Target, Name : GLenum; V : GLfloat) with Convention => C;
   Tex_Parameterf : Tex_Parameterf_T with Import, Convention => C, External_Name => "epoxy_glTexParameterf";

   type Pixel_Store_T is access procedure (Name : GLenum; V : GLint) with Convention => C;
   Pixel_Storei : Pixel_Store_T with Import, Convention => C, External_Name => "epoxy_glPixelStorei";

   type Tex_Image_T is access procedure
     (Target : GLenum; Level, Internal : GLint; W, H : GLsizei; Border : GLint;
      Format, Kind : GLenum; Data : System.Address) with Convention => C;
   Tex_Image_2D : Tex_Image_T with Import, Convention => C, External_Name => "epoxy_glTexImage2D";

   type Tex_Sub_Image_T is access procedure
     (Target : GLenum; Level, X, Y : GLint; W, H : GLsizei;
      Format, Kind : GLenum; Data : System.Address) with Convention => C;
   Tex_Sub_Image_2D : Tex_Sub_Image_T with Import, Convention => C, External_Name => "epoxy_glTexSubImage2D";

   type Read_Pixels_T is access procedure
     (X, Y : GLint; W, H : GLsizei; Format, Kind : GLenum; Data : System.Address) with Convention => C;
   Read_Pixels : Read_Pixels_T with Import, Convention => C, External_Name => "epoxy_glReadPixels";

   --  Framebuffers, for the shadows
   Gen_Framebuffers : Gen_T with Import, Convention => C, External_Name => "epoxy_glGenFramebuffers";
   Bind_Framebuffer : Bind_T with Import, Convention => C, External_Name => "epoxy_glBindFramebuffer";
   type Framebuffer_Texture_T is access procedure
     (Target, Attachment, Tex_Target : GLenum; Texture : GLuint; Level : GLint) with Convention => C;
   Framebuffer_Texture_2D : Framebuffer_Texture_T
     with Import, Convention => C, External_Name => "epoxy_glFramebufferTexture2D";
   type Check_Status_T is access function (Target : GLenum) return GLenum with Convention => C;
   Check_Framebuffer_Status : Check_Status_T
     with Import, Convention => C, External_Name => "epoxy_glCheckFramebufferStatus";
   Draw_Buffer : Cap_T with Import, Convention => C, External_Name => "epoxy_glDrawBuffer";
   Read_Buffer : Cap_T with Import, Convention => C, External_Name => "epoxy_glReadBuffer";
   type Tex_Parameterfv_T is access procedure (Target, Name : GLenum; V : System.Address) with Convention => C;
   Tex_Parameterfv : Tex_Parameterfv_T with Import, Convention => C, External_Name => "epoxy_glTexParameterfv";

   GL_NONE                 : constant := 0;
   GL_FRAMEBUFFER          : constant := 16#8D40#;
   GL_FRAMEBUFFER_BINDING  : constant := 16#8CA6#;
   GL_DEPTH_ATTACHMENT     : constant := 16#8D00#;
   GL_FRAMEBUFFER_COMPLETE : constant := 16#8CD5#;
   GL_DEPTH_COMPONENT      : constant := 16#1902#;
   GL_DEPTH_COMPONENT24    : constant := 16#81A6#;
   GL_TEXTURE_COMPARE_MODE : constant := 16#884C#;
   GL_TEXTURE_COMPARE_FUNC : constant := 16#884D#;
   GL_COMPARE_REF_TO_TEXTURE : constant := 16#884E#;
   GL_CLAMP_TO_BORDER      : constant := 16#812D#;
   GL_TEXTURE_BORDER_COLOR : constant := 16#1004#;
   GL_TEXTURE1             : constant := 16#84C1#;
   GL_VIEWPORT             : constant := 16#0BA2#;

   --  A program from the source of its two shaders; raises Program_Error with the log if it fails
   function Build_Program (Vertex, Fragment : String) return GLuint;

   function Uniform (Program : GLuint; Name : String) return GLint;

end GL;
