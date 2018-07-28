REBOL [
    System: "REBOL [R3] Language Interpreter and Run-time Environment"
    Title: "Make libRebol related files (for %rebol.h)"
    File: %make-reb-lib.r
    Rights: {
        Copyright 2012 REBOL Technologies
        Copyright 2012-2017 Rebol Open Source Contributors
        REBOL is a trademark of REBOL Technologies
    }
    License: {
        Licensed under the Apache License, Version 2.0
        See: http://www.apache.org/licenses/LICENSE-2.0
    }
    Needs: 2.100.100
]

do %r2r3-future.r
do %common.r
do %common-parsers.r
do %common-emitter.r

print "--- Make Reb-Lib Headers ---"

lib-ver: 2

preface: "RL_"

args: parse-args system/options/args
output-dir: system/options/path/prep
output-dir: output-dir/include
mkdir/deep output-dir

ver: load %../../src/boot/version.r

;-----------------------------------------------------------------------------

; These are the blocks of strings that are gathered in the EMIT-PROTO scan of
; %a-lib.c.  They are later composed along with some boilerplate to produce
; the %rebol.h file.
;
lib-struct-fields: make block! 50
struct-call-macros: make block! 50
undecorated-prototypes: make block! 50
direct-call-macros: make block! 50
table-init-items: make block! 50
cwrap-items: make block! 50

emit-proto: func [return: <void> proto] [
    header: proto-parser/data

    all [
        block? header
        2 <= length of header
        set-word? header/1
    ] or [
        print mold header
        fail [
            proto
            newline
            "Prototype has bad Rebol function header block in comment"
        ]
    ]

    if header/2 != 'RL_API [return]

    ; Currently the only part of the comment header for the exports in
    ; the %a-lib.c file that is paid attention to is the SET-WORD! that
    ; mirrors the name of the function, and the RL_API word that comes
    ; after it.  Anything else should just be comments.  But some day,
    ; it could be a means of exposing documentation for the parameters.
    ;
    ; (This was an original intent of the comments in the %a-lib.c file,
    ; though they parsed a specialized documentation format that did not
    ; use Rebol syntax...the new idea is to always use Rebol syntax.)

    api-name: copy-as-text header/1
    if proto-parser/proto.id != unspaced ["RL_" api-name] [
        fail [
            "Name in comment header (" api-name ") isn't function name"
            "minus RL_ prefix for" proto-parser/proto.id
        ]
    ]

    pos.id: find proto "RL_"
    fn.declarations: copy/part proto pos.id
    pos.lparen: find pos.id "("
    fn.name: copy/part pos.id pos.lparen
    fn.name.upper: uppercase copy fn.name
    fn.name.lower: lowercase copy find/tail fn.name "RL_"
    fn.args: copy/part next pos.lparen back tail proto

    append lib-struct-fields unspaced [
        fn.declarations "(*" fn.name.lower ")" pos.lparen
    ]

    append undecorated-prototypes unspaced [
        "EMSCRIPTEN_KEEPALIVE RL_API" space proto
    ]

    ; It's not possible to make a function pointer in a struct carry the no
    ; return attribute.  So we have to go through an inline function.
    ;
    all [
        block? :header/3
        find header/3 #noreturn
    ] then [
        inline-proto: copy proto
        replace inline-proto "RL_API" {}
        replace inline-proto "RL_" {}

        inline-args: unspaced collect [
            parse inline-proto [
                thru "("
                any [
                    [copy param thru "," | copy param to ")" to end] (
                        ;
                        ; We have the type and pointer decorations, basically
                        ; just step backwards until we find something that's
                        ; not a C identifier letter/digit/underscore
                        ;
                        identifier-chars: charset [
                            #"A" - #"Z" #"a" - #"z" #"0" - #"9" #"_"
                            #"." ;-- for variadics
                        ]
                        pos: back back tail param
                        while [find identifier-chars pos/1] [
                            pos: back pos
                        ]
                        keep next pos
                    )
                ]
            ] or [
                fail ["Couldn't extract args from prototype:" inline-proto]
            ]
        ]

        if find inline-proto "va_list *vaptr" [
            replace inline-proto "va_list *vaptr" "..."
            parse inline-args [
                some [copy next-to-last-arg: to "," skip]
                to end
            ]
            replace inline-args "vaptr" "&va"

            append direct-call-macros cscape {
                ATTRIBUTE_NO_RETURN inline static $<Inline-Proto> {
                    va_list va;
                    va_start(va, ${Next-To-Last-Arg});
                    $<Proto-Parser/Proto.Id>($<Inline-Args>);
                    DEAD_END;
                }
            }

            append struct-call-macros cscape {
                ATTRIBUTE_NO_RETURN inline static $<Inline-Proto> {
                    va_list va;
                    va_start(va, ${Next-To-Last-Arg});
                    RL->${fn.name.lower}($<Inline-Args>);
                    DEAD_END;
                }
            }
        ] else [
            append direct-call-macros cscape {
                ATTRIBUTE_NO_RETURN inline static $<Inline-Proto> {
                    $<Proto-Parser/Proto.Id>($<Inline-Args>);
                    DEAD_END;
                }
            }

            append struct-call-macros cscape {
                ATTRIBUTE_NO_RETURN inline static $<Inline-Proto> {
                    RL->${fn.name.lower}($<Inline-Args>);
                    DEAD_END;
                }
            }
        ]
    ] else [
        ;-- alias version without the RL_ on it to just call the RL_ version
        append direct-call-macros cscape {
            #define $<Api-Name> $<Proto-Parser/Proto.Id>
        }

        append struct-call-macros cscape {
            #define $<Api-Name> RL->${fn.name.lower}
        }
    ]

    append table-init-items fn.name

    append cwrap-items reduce [
        fn.declarations
        fn.name
        fn.args
    ]
]

process: func [file] [
    data: read the-file: file
    data: to-text data

    proto-parser/emit-proto: :emit-proto
    proto-parser/process data
]

;-----------------------------------------------------------------------------
;
; Currently only two files are searched for RL_API entries.  This makes it
; easier to track the order of the API routines and change them sparingly
; (such as by adding new routines to the end of the list, so as not to break
; binary compatibility with code built to the old ordered interface).

src-dir: %../../src/core/

process src-dir/a-lib.c
process src-dir/f-extension.c ; !!! is there a reason to process this file?

;-----------------------------------------------------------------------------

e-lib: (make-emitter
    "Rebol External Library Interface" output-dir/rebol.h)

e-lib/emit {
    #include <stdarg.h> /* needed for va_start() in inline functions */

    #ifdef TO_EMSCRIPTEN
        /*
         * EMSCRIPTEN_KEEPALIVE is a macro in emscripten.h used to export
         * a function.  We can't include emscripten.h here (it is incompatible
         * with DONT_INCLUDE_STDIO_H)
         */
        #define EMSCRIPTEN_KEEPALIVE __attribute__((used))
    #else
        #define EMSCRIPTEN_KEEPALIVE
    #endif

    #ifdef __cplusplus
    extern "C" ^{
    #endif

    /*
     * !!! These constants are part of an old R3-Alpha versioning system
     * that hasn't been paid much attention to.  Keeping as a placeholder.
     */
    #define RL_VER $<ver/1>
    #define RL_REV $<ver/2>
    #define RL_UPD $<ver/3>

    /*
     * As far as most libRebol clients are concerned, a REBVAL is a black box.
     * However, the internal code also includes %rebol.h, so the definition
     * has to line up with what is actually used when building as C++ vs. not.
     */
    #if !defined(CPLUSPLUS_11)
        struct Reb_Cell;
        #define REBVAL struct Reb_Cell
    #else
        struct Reb_Specific_Value;
        #define REBVAL struct Reb_Specific_Value
    #endif

    /*
     * `wchar_t` is a pre-Unicode abstraction, whose size varies per-platform
     * and should be avoided where possible.  But Win32 standardizes it to
     * 2 bytes in size for UTF-16, and uses it pervasively.  So libRebol
     * currently offers APIs (e.g. rebTextW() instead of rebText()) which
     * support this 2-byte notion of wide characters.
     *
     * In order for C++ to be type-compatible with Windows's WCHAR definition,
     * a #define on Windows to wchar_t is needed.  But on non-Windows, it
     * must use `uint16_t` since there's no size guarantee for wchar_t.  This
     * is useful for compatibility with unixodbc's SQLWCHAR.
     *
     * !!! REBWCHAR is just for the API definitions--don't mention it in
     * client code.  If the client code is on Windows, use WCHAR.  If it's in
     * a unixodbc client use SQLWCHAR.  But use UTF-8 if you possibly can.
     */
    #ifdef TO_WINDOWS
        #define REBWCHAR wchar_t
    #else
        #define REBWCHAR uint16_t
    #endif

    /*
     * "Dangerous Function" which is called by rebRescue().  Argument can be a
     * REBVAL* but does not have to be.  Result must be a REBVAL* or NULL.
     *
     * !!! If the dangerous function returns an ERROR!, it will currently be
     * converted to null, which parallels TRAP without a handler.  nulls will
     * be converted to voids.
     */
    typedef REBVAL* (REBDNG)(void *opaque);

    /*
     * "Rescue Function" called as the handler in rebRescueWith().  Receives
     * the REBVAL* of the error that occurred, and the opaque pointer.
     *
     * !!! If either the dangerous function or the rescuing function return an
     * ERROR! value, that is not interfered with the way rebRescue() does.
     */
    typedef REBVAL* (REBRSC)(REBVAL *error, void *opaque);

    /*
     * For some HANDLE!s GC callback
     */
    typedef void (CLEANUP_CFUNC)(const REBVAL*);

    /*
     * The API maps Rebol's `null` to C's 0 pointer, **but don't use NULL**.
     * Some C compilers define NULL as simply the constant 0, which breaks
     * use with variadic APIs...since they will interpret it as an integer
     * and not a pointer.
     *
     * **It's best to use C++'s `nullptr`**, or a suitable C shim for it,
     * e.g. `#define nullptr ((void*)0)`.  That helps avoid obscuring the
     * fact that the Rebol API's null really is C's null, and is conditionally
     * false.  Seeing `rebNull` in source doesn't as clearly suggest this.
     *
     * However, **using NULL is broken, so don't use it**.  This macro is
     * provided in case defining `nullptr` is not an option--for some reason.
     */
    #define rebNull \
        cast(REBVAL*, 0)

    /*
     * Since a C nullptr (pointer cast of 0) is used to represent the Rebol
     * `null` in the API, something different must be used to indicate the
     * end of variadic input.  So a pointer to data is used where the first
     * byte is illegal for starting UTF-8 (a continuation byte, first bit 1,
     * second bit 0) and the second byte is 0.
     *
     * To Rebol, the first bit being 1 means it's a Rebol node, the second
     * that it is not in the "free" state.  The lowest bit in the first byte
     * clear indicates it doesn't point to a "cell".  With the second byte as
     * a 0, this means the NOT_END bit (highest in second byte) is clear.  So
     * this simple 2 byte string does the trick!
     */
    #define rebEND \
        "\x80"

    /*
     * Function entry points for reb-lib (used for MACROS below):
     */
    typedef struct rebol_ext_api {
        $[Lib-Struct-Fields];
    } RL_LIB;

    #ifdef REB_EXT /* can't direct call into EXE, must go through interface */
        /*
         * The macros below will require this base pointer:
         */
        extern RL_LIB *RL;  // is passed to the RX_Init() function

        /*
         * Macros to access reb-lib functions (from non-linked extensions):
         */

        $[Struct-Call-Macros]

    #else /* ...calling Rebol as DLL, or code built into the EXE itself */
        /*
         * Undecorated prototypes, don't call with this name directly
         */

        $[Undecorated-Prototypes];

        /*
         * Use these macros for consistency with extension code naming
         */

        $[Direct-Call-Macros]

    #endif // REB_EXT

    /***********************************************************************
     *
     *  TYPE-SAFE rebMalloc() MACRO VARIANTS FOR C++ COMPATIBILITY
     *
     * Originally R3-Alpha's hostkit had special OS_ALLOC and OS_FREE hooks,
     * to facilitate the core to free memory blocks allocated by the host
     * (or vice-versa).  So they agreed on an allocator.  In Ren-C, all
     * layers use REBVAL* for the purpose of exchanging such information--so
     * this purpose is obsolete.
     *
     * Yet a new API construct called rebMalloc() offers some advantages over
     * hosts just using malloc():
     *
     *     Memory can be retaken to act as a BINARY! series without another
     *     allocation, via rebRepossess().
     *
     *     Memory is freed automatically in the case of a failure in the
     *     frame where the rebMalloc() occured.  This is especially useful
     *     when mixing C code involving allocations with rebRun(), etc.
     *
     *     Memory gets counted in Rebol's knowledge of how much memory the
     *     system is using, for the purposes of triggering GC.
     *
     *     Out-of-memory errors on allocation automatically trigger
     *     failure vs. needing special handling by returning NULL (which may
     *     or may not be desirable, depending on what you're doing)
     *
     * Additionally, the rebAlloc(type) and rebAllocN(type, num) macros
     * automatically cast to the correct type for C++ compatibility.
     *
     * Note: There currently is no rebUnmanage() equivalent for rebMalloc()
     * data, so it must either be rebRepossess()'d or rebFree()'d before its
     * frame ends.  This limitation will be addressed in the future.
     *
     **********************************************************************/

    #define rebAlloc(t) \
        cast(t *, rebMalloc(sizeof(t)))
    #define rebAllocN(t,n) \
        cast(t *, rebMalloc(sizeof(t) * (n)))

    #ifdef __cplusplus
    ^}
    #endif
}

e-lib/write-emitted

;-----------------------------------------------------------------------------

e-table: (make-emitter
    "REBOL Interface Table Singleton" output-dir/tmp-reb-lib-table.inc)

e-table/emit {
    RL_LIB Ext_Lib = {
        $(Table-Init-Items),
    };
}

e-table/write-emitted

arg-to-js: func [s [text!]][
    return case [
        parse s [thru "char" some space "*" to end] ["'string'"]
        find s "*" ["'number'"]
        find s "[" ["'array'"]
        parse/case s [
            any space opt ["const" some space]
            [ "REBCNT" | "REBOOL" | "REBDEC"
            | "REBI64" | "REBRXT" | "REBUNI"
            | "int" | "long" |"unsigned"
            ]
            to END
        ] ["'number'"]
        parse s ["void" any space] ["null"]
        default [to-tag s]
    ]
]

e-cwrap: (make-emitter
    "C-Wraps" output-dir/reb-lib.js
)

map-names: [
    "rebMoldAlloc" "rebMold"
    "rebSpellingOfAlloc" "rebSpellingOf"
    _ "rebDo" ;skip rebDo
]

for-each [result RL_name args] cwrap-items [
    args: split args ","
    result: arg-to-js result
    parse RL_Name ["RL_" copy rebName to end] or [fail]

    if find/skip (next map-names) rebName 2 [
        print ["Skipping" rebName]
        continue
    ]
    line: unspaced [
        rebName " = Module.cwrap('"
        RL_name "', "
        either result = "'string'" ["'number'"][result] ", ["
        delimit
            map-each x args [arg-to-js x]
            ", "
        "]);"
    ]
    if find line "<" [
        e-cwrap/emit {
            // Unknown type: <...> -- $<Line>
        }
    ] else [
        e-cwrap/emit {
            $<Line>
        }
    ]

    if not (find/skip map-names rebName 2) [continue] 
    ;; emit JS variant
    js-name: map-names/:rebName
    for-next args [args/1: unspaced ["x" index of args]]
    args: delimit args ","
    line: unspaced [
        js-name " = function(" args
        ") {var p = " rebName "(" args
        "); var s = Pointer_stringify(p); rebFree(p); return s};"
    ]
    if find line "<" [
        e-cwrap/emit {
            // Unknown type: <...> -- $<Line>
        }
    ] else [
        e-cwrap/emit {
            $<Line>
        }
    ]
]

e-cwrap/emit {
    rebRun = function() {
        var argc = arguments.length;
        var va = allocate(4 * (argc+1), '', ALLOC_STACK);
        var a, i, l, p;
        for (i=0; i < argc; i++) {
            a = arguments[i];
            switch (typeof a) {
            case 'string':
                l = lengthBytesUTF8(a) + 4;
                l = l&~3
                p = allocate(l, '', ALLOC_STACK);
                stringToUTF8(a, p, l);
                break;
            case 'number':
                p = a;
                break;
            default:
                throw new Error("Invalid type!");
            }
            HEAP32[(va>>2)+i] = p;
        }

        // !!! There's no rebEnd() API now, it's just a 2-byte sequence at an
        // address; how to do this better?  See rebEND definition.
        //
        p = allocate(2, '', ALLOC_STACK);
        setValue(p, 'i8', -127) // 0x80
        setValue(p + 1, 'i8', 0) // 0x00
        HEAP32[(va>>2)+argc] = p;

        return _RL_rebRun(HEAP32[va>>2], va+4);
    }
}

e-cwrap/write-emitted
