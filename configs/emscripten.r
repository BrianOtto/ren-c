REBOL [
    File: %emscripten.r
]

; Right now, either #web or #node
;
javascript-environment: default [#web]

; If WebAssembly is not used, then `asm.js` will be produced instead.  It is
; usable in more browsers, but is slower to load.  Given the features that
; are expected to work in %load-r3.js (e.g. `fetch()` and Promises), we tend
; to assume WebAssembly as a lowest common denominator.
;
use-wasm: default [true]

; The inability to communicate synchronously between the worker and GUI in
; JavaScript means that being deep in a C-based interpreter stack on the
; worker cannot receive data from the GUI.  The "Emterpreter" works around
; this limitation by running a JavaScript bytecode simulator...so even if
; a JavaScript stack can't be paused, the bytecode interpreter can, long
; enough to release the GUI thread it was running on to do let it do work.
;
; https://github.com/emscripten-core/emscripten/wiki/Emterpreter
;
; That's a slow and stopgap measure, which makes the build products twice as
; large and much more than twice as slow.  It is supplanted entirely with a
; superior approach based on WASM threads.  In this model, the GUI thread is
; left free, while the code that's going to make demands runs on its own
; thread...which can suspend and wait, using conventional atomics (mutexes,
; wait conditions).
;
; There was some issue with WASM threading being disabled in 2018 due to
; Spectre vulnerabilities in SharedArrayBuffer.  This seems to be mitigated,
; and approaches are now focusing on assuming that the thread-based solution
; will be available.
;
if javascript-environment = #node [
    use-emterpreter: default [true]  ; no PTHREAD in Emscripten Node.js yet
] else [
    use-emterpreter: default [false]
]

; Making an actual debug build of the interpreter core is prohibitive for
; emscripten in general usage--even on a developer machine.  This enables a
; smaller set of options for getting better feedback about errors in an
; emscripten build.
;
debug-javascript-extension: true


; Want to make libr3.js, not an executable.  This is so that plain `make`
; knows we want that (vs needing to say `make libr3.js`)
;
top: 'library

os-id: default [0.16.2]

toolset: [
    gcc %emcc
    ld %emcc
]

; Using the -Os or -Oz size optimizations will drastically improve the size
; of the download...cutting it in as much as half compared to -O2.  But it
; comes at a cost of not inlining, which winds up meaning more than just
; slower in the browser: the intrinsic limit of how many JS/WASM functions it
; lets be on the stack is hit sooner.  We can do per-file optimization choices
; so the #prefer-O2-optimization flag is set on the %c-eval.c file, which
; overrides this "s" optimization.  (It won't override `-Oz` which is supposed
; to be a more extreme size optimization, but seems about the same.)
;
optimize: "s"

extensions: make map! [
    BMP -
    Clipboard -
    Crypt -
    Console +
    Debugger +
    DNS -
    Event -
    Filesystem -
    FFI -
    GIF -
    Gob -
    Image -
    JavaScript +
    JPG -
    Library -
    Locale -
    Network -
    ODBC -
    PNG -
    Process -
    Secure -
    Serial -
    Signal -
    Stdio -
    TCC -
    Time -
    UUID -
    UTF -
    Vector -
    View -
    ZeroMQ -
]


; emcc command-line options:
; https://kripken.github.io/emscripten-site/docs/tools_reference/emcc.html
; https://github.com/kripken/emscripten/blob/incoming/src/settings.js
;
; Note environment variable EMCC_DEBUG for diagnostic output

cflags: compose [
    ((if debug-javascript-extension [[
        {-DDEBUG_JAVASCRIPT_EXTENSION}

        {-DDEBUG_STDIO_OK}
        {-DDEBUG_HAS_PROBE}
        {-DDEBUG_COUNT_TICKS}
        {-DDEBUG_PRINTF_FAIL_LOCATIONS}
    ]]))

    ((if use-emterpreter [[
        {-DUSE_EMTERPRETER}  ; affects rebPromise() methodology
    ]] else [[
        ; Instruction to emcc (via -s) to include pthread functionalitys
        {-s USE_PTHREADS=1}  ; must be in both cflags and ldflags if used

        ; Instruction to compiler front end (via -D) to do a #define
        {-DUSE_PTHREADS=1}  ; clearer than `#if !defined(USE_EMTERPRETER)`
    ]]))
]

ldflags: compose [
    (unspaced ["-O" optimize])

    ; Emscripten tries to do a lot of automatic linking "magic" for you, and
    ; seeing what it's doing might be helpful...if you can understand it.
    ; https://groups.google.com/forum/#!msg/emscripten-discuss/FqrgANu7ZLs/EFfNoYvMEQAJ
    ;
    (comment {-s VERBOSE=1})

    (switch javascript-environment [
        #web [
            ; https://github.com/emscripten-core/emscripten/issues/8102
            {-s ENVIRONMENT='web,worker'}
        ]
        #node [
            if not use-emterpreter [
                fail [
                    "Emscripten in Node.js does not (yet) support PTHREAD" LF
                    "USE-EMTERPRETER must be set to true in %emscripten.r" LF
                    https://groups.google.com/forum/#!msg/emscripten-discuss/NxpEjP0XYiA/xLPiXEaTBQAJ
                ]
            ]
            {-s ENVIRONMENT='node'}
        ]
        fail "JAVASCRIPT-ENVIRONMENT must be #web or #node in %emscripten.r"
    ])

    (if javascript-environment = #node [
        ;
        ; !!! Complains about missing $SOCKFS symbol otherwise
        ;
        {-s ERROR_ON_UNDEFINED_SYMBOLS=0}
    ])

    ; Generated by %make-reb-lib.r, see notes there.  Pertains to this:
    ; https://github.com/emscripten-core/emscripten/issues/4240
    ;
    (if (javascript-environment = #node) and [use-emterpreter] [
        {--pre-js prep/include/node-preload.js}
    ])

    (if debug-javascript-extension [
        {-s ASSERTIONS=1}
    ] else [
        {-s ASSERTIONS=0}
    ])

    ((if false [[
        ; In theory, using the closure compiler will reduce the amount of
        ; unused support code in %libr3.js, at the cost of slower compilation. 
        ; Level 2 is also available, but is not recommended as it impedes
        ; various optimizations.  See the published limitations:
        ;
        ; https://developers.google.com/closure/compiler/docs/limitations
        ;
        ; !!! A closure compile has not been successful yet.  See notes here:
        ; https://github.com/kripken/emscripten/issues/7288
        ; If you get past that issue, the problem looks a lot like:
        ; https://github.com/kripken/emscripten/issues/6828
        ; The suggested workaround for adding --externals involves using
        ; EMCC_CLOSURE_ARGS, which is an environment variable...not a param
        ; to emcc, e.g.
        ;     export EMCC_CLOSURE_ARGS="--externs closure-externs.json"
        ;
        ;{-s IGNORE_CLOSURE_COMPILER_ERRORS=1}  ; maybe useful?
        {-g1}  ; Note: debug level 1 can be used with closure compiler
        {--closure 1}
    ]] else [[
        {--closure 0}
    ]]))

    ; Minification usually tied to optimization, but can be set separately.
    ;
    (if debug-javascript-extension [{--minify 0}])

    ; %reb-lib.js is produced by %make-reb-lib.js - It contains the wrapper
    ; code that proxies JavaScript calls to `rebElide(...)` etc. into calls
    ; to the functions that take a `va_list` pointer, e.g. `_RL_rebElide()`.
    ;
    {--post-js prep/include/reb-lib.js}

    ; While over the long term it may be the case that C++ builds support the
    ; exception mechanism, the JavaScript build is going to be based on
    ; embracing the JS exception model.  So disable C++ exceptions.
    ; https://forum.rebol.info/t//555
    ;
    {-s DISABLE_EXCEPTION_CATCHING=1}
    {-s DEMANGLE_SUPPORT=0}  ; C++ build does all exports as C, not needed

    ; API exports can appear unused to the compiler.  It's possible to mark a
    ; C function as an export with EMTERPRETER_KEEP_ALIVE, but we prefer to
    ; generate the list so that `rebol.h` doesn't depend on `emscripten.h`
    ;
    {-s EXPORTED_FUNCTIONS=@prep/include/libr3.exports.json}

    ; The EXPORTED_"RUNTIME"_METHODS are referring to JavaScript helper
    ; functions that Emscripten provides that make it easier to call C code.
    ; You don't need them to call C functions with integer arguments.  But
    ; you'll proably want them if you're going to do things like transform
    ; from JavaScript strings into an allocated UTF-8 string on the heap
    ; that is visible to C (allocateUTF8).  See:
    ;
    ; https://emscripten.org/docs/porting/connecting_cpp_and_javascript/Interacting-with-code.html
    ;
    ; The documentation claims a `--pre-js` or `--post-js` script that uses
    ; internal methods will auto-export them since the linker "sees" it.  But
    ; that doesn't seem to be the case (and wouldn't be the case for anything
    ; called from EM_ASM() in the C anyway).  So list them explicitly here.
    ;
    ; !!! For the moment (and possible future) we do not use ccall and cwrap
    ; because they do not heed EMTERPRETER_BLACKLIST to know when it would
    ; be safe to call a wrapped function during emterpreter_sleep_with_yield()
    ; It may be that the API doesn't need such a heavy wrapping mechanism
    ; anyway, and there are few enough APIs that the non-variadics can just
    ; be factored and wrapped by hand.
    ;
    {-s "EXTRA_EXPORTED_RUNTIME_METHODS=['allocateUTF8']"}
    ; {-s "EXTRA_EXPORTED_RUNTIME_METHODS=['ccall', 'cwrap', 'allocateUTF8']"}

    ; WASM does not have source maps, so disabling it can aid in debugging
    ; But emcc WASM=0 does not work in VirtualBox shared folders by default
    ; https://github.com/kripken/emscripten/issues/6813
    ;
    ; SAFE_HEAP=1 does not work with WASM
    ; https://github.com/kripken/emscripten/issues/4474
    ;
    (if use-wasm [
        {-s WASM=1 -s SAFE_HEAP=0}
    ] else [
        {-s WASM=0 -s SAFE_HEAP=1}
    ])

    ; This allows memory growth but disables asm.js optimizations (little to
    ; no effect on WASM).  Disable until it becomes an issue.
    ;
    ;{-s ALLOW_MEMORY_GROWTH=0}

    ((if use-emterpreter [[
        {-s EMTERPRETIFY=1}
        {-s EMTERPRETIFY_ASYNC=1}
        {-s EMTERPRETIFY_FILE="libr3.bytecode"}

        ; Memory initialization file,
        ; used both in asm.js and wasm+pthread
        ; unused in 'pure' wasm':
        ; https://groups.google.com/forum/m/#!topic/emscripten-discuss/_czKmHCbeSY
        ;
        {--memory-init-file 1}

        ; "There's always a blacklist.  The whitelist starts empty.  If there
        ; is a non-empty whitelist then everything not in it gets added to the
        ; blacklist.  Everything not in the blacklist gets emterpreted."
        ; https://github.com/kripken/emscripten/issues/7239
        ;
        ; Blacklisting functions from being emterpreted means they will run
        ; faster, as raw WASM.  But it also means blacklisted APIs can be
        ; called from within a JS-AWAITER, since they don't require use of
        ; the suspended bytecode interpreter.  See additional notes in the
        ; blacklist and whitelist generation code in %prep-libr3-js.reb

        {-s EMTERPRETIFY_WHITELIST=@prep/include/emterpreter.whitelist.json}

	; whitelist needs true function names

	{--profiling-funcs}
    ]]
    else [[
        {-s USE_PTHREADS=1}  ; must be in both cflags and ldflags if used

        ; If you don't specify a thread pool size as a linker flag, the first
        ; call to `pthread_create()` won't start running the thread, it will
        ; have to yield first.  See "Special Considerations":
        ; https://emscripten.org/docs/porting/pthreads.html
        ;
        {-s PTHREAD_POOL_SIZE=1}
    ]]))

    ; When debugging in the emterpreter, stack frames all appear to have the
    ; function name `emterpret`.  Asking to turn on profiling will inject an
    ; extra stack frame with the name of the function being called.  It runs
    ; slower, but makes the build process *A LOT* slower.
    ;
    ;{--profiling-funcs}  ; more minimal than `--profiling`, just the names
]
