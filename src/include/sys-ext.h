//
//  File: %sys-ext.h
//  Summary: "Extension Hook Point Definitions"
//  Project: "Rebol 3 Interpreter and Run-time (Ren-C branch)"
//  Homepage: https://github.com/metaeducation/ren-c/
//
//=////////////////////////////////////////////////////////////////////////=//
//
// Copyright 2016-2018 Rebol Open Source Contributors
// REBOL is a trademark of REBOL Technologies
//
// See README.md and CREDITS.md for more information.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//=////////////////////////////////////////////////////////////////////////=//
//

#if defined(EXT_DLL)
    //
    // EXT_DLL being defined indicates an "external extension".  Its entry
    // point has a predictable name of RX_Init() exported from the DLL.

  #if defined(REB_EXE)
    #define EXT_API EXTERN_C API_IMPORT // Hosting Rebol is an EXE
  #else
    #define EXT_API EXTERN_C API_EXPORT // Hosting Rebol is a DLL/LIB
  #endif

    // Just ignore the extension name parameter
    //
    #define RX_COLLATE_NAME(ext_name) RX_Collate
#else
    // If EXT_DLL is not defined, this is a "built-in extension".  It is
    // part of the exe or lib, and its loader function must be distinguished
    // by name from other extensions that are built-in.
    //
    // !!! This could also be done with some kind of numbering scheme (UUID?)
    // by the build process, but given that name collisions in Rebol cause
    // other problems the idea of not colliding with extension filenames
    // is par for the course.

    #define EXT_API EXTERN_C

    // *Don't* ignore the extension name parameter
    //
    #define RX_COLLATE_NAME(ext_name) RX_Collate_##ext_name
#endif

// The init function does not actually decompress any of the script or spec
// code, make any natives, or run any startup.  It just returns an aggregate
// of all the information that would be needed to make the extension module.
//
// !!! This aggregate may become an ACTION! as opposed to an array of handle
// values, but this is a work in progress.
//
#ifdef TO_WINDOWS
    typedef REBVAL *(__cdecl COLLATE_CFUNC)(void);
#else
    typedef REBVAL *(COLLATE_CFUNC)(void);
#endif

//=//// EXTENSION MACROS //////////////////////////////////////////////////=//

#define DECLARE_EXT_COLLATE(ext_name) \
    EXT_API REBVAL *RX_COLLATE_NAME(ext_name)(void)

// !!! Currently used for just a BLOCK!, but may become ACT_DETAILS()
//
#define IDX_COLLATOR_INIT 0
#define IDX_COLLATOR_QUIT 1
#define IDX_COLLATOR_SCRIPT 2
#define IDX_COLLATOR_SPECS 3
#define IDX_COLLATOR_DISPATCHERS 4
#define IDX_COLLATOR_MAX 5


//=//// MODULE MACROS /////////////////////////////////////////////////////=//

#define DECLARE_MODULE_INIT(mod_name) \
    void Module_Init_##mod_name(void)

#define CALL_MODULE_INIT(mod_name) \
    Module_Init_##mod_name()

#define DECLARE_MODULE_QUIT(mod_name) \
    void Module_Quit_##mod_name(void)

#define CALL_MODULE_QUIT(mod_name) \
    Module_Quit_##mod_name()
