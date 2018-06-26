REBOL [
    Title: "Shim to bring old executables up to date to use for bootstrapping"
    Rights: {
        Rebol 3 Language Interpreter and Run-time Environment
        "Ren-C" branch @ https://github.com/metaeducation/ren-c

        Copyright 2012-2018 Rebol Open Source Contributors
        REBOL is a trademark of REBOL Technologies
    }
    License: {
        Licensed under the Apache License, Version 2.0
        See: http://www.apache.org/licenses/LICENSE-2.0
    }
    Purpose: {
        This file was originally used to make an R3-Alpha "act like" a Ren-C.
        That way, bootstrapping code could be written under various revised
        language conventions--while still using older executables to build.

        Changes in the language have become drastic enough that an R3-Alpha
        lacks the compositional tools (such as ADAPT, SPECIALIZE, CHAIN) to
        feasibly keep up.  Hence, the shim is only used with older Ren-C
        executables...which are both more in sync with modern definitions,
        and have those composition tools available:

        https://github.com/metaeducation/ren-c/issues/815

        It also must remain possible to run it from a state-of-the-art build
        without disrupting the environment.  This is because the script does
        not know whether the R3-MAKE you are using is old or new.  No good
        versioning strategy has been yet chosen, so words are "sniffed" for
        existing definitions to upgrade in a somewhat ad-hoc way.
    }
]

for-each w [ELSE THEN ALSO OR AND UNLESS !! !? ?!] [
    set w func [dummy:] compose [
        fail/where [
            "Do not use" w "in bootstrap.  It is based on normal enfix"
            "mechanics that worked differently in the stable snapshot version"
            "committed in 0da70da4c12677bf71ce4cf3fad1923c185db0b8, so"
            "until a new stable snapshot is picked" w "must be avoided."
        ] 'dummy
    ]
]

; The snapshotted Ren-C existed when VOID? was the name for NULL?.  What we
; will (falsely) assume is that any Ren-C that knows NULL? is "modern" and
; does not need patching forward.  What this really means is that we are
; only catering the shim code to the snapshot.
;
; (It would be possible to rig up shim code for pretty much any specific other
; version if push came to shove, but it would be work for no obvious reward.)
;
if true = attempt [null? :some-undefined-thing] [
    ;
    ; COPY AS TEXT! can't be made to work in the old Ren-C, so it just
    ; aliases its SPELLING-OF to COPY-AS-TEXT.  Define that for compatibilty.
    ;
    copy-as-text: chain [
        specialize 'as [type: text!]
            |
        :copy
    ]

    QUIT
]

print "== SHIMMING OLDER R3 TO MODERN LANGUAGE DEFINITIONS =="

; NOTE: The slower these routines are, the slower the overall build will be.
; It's worth optimizing it as much as is reasonable.


; https://forum.rebol.info/t/behavior-of-to-string-as-string-mold/630
;
copy-as-text: :spelling-of


; https://forum.rebol.info/t/null-in-the-librebol-api-and-void-null/597
;
null: :void
null?: :void?
unset 'void
unset 'void?
set*: :set ;-- used to allow nulls by default

; http://blog.hostilefork.com/did-programming-opposite-of-not/
;
; Note that ADAPT can't be used here, because TRUE?/FALSE? did not take <opt>
;
did: func [optional [<opt> any-value!]] compose/deep [
    (:lib/true?) (:lib/to-value) :optional
]
not: func [optional [<opt> any-value!]] compose/deep [
    (:lib/false?) (:lib/to-value) :optional
]

; https://forum.rebol.info/t/if-at-first-you-dont-select-try-try-again/589
;
try: :to-value


; https://forum.rebol.info/t/squaring-the-circle-of-length-and-length-of/385
;
type-of: chain [:lib/type-of | :opt] ;-- type of null is now null
of: enfix function [
    return: [<opt> any-value!]
    'property [word!]
    value [<opt> any-value!]
][
    lib/switch*/default property [ ;-- non-evaluative, pass through null
        index [index-of :value]
        offset [offset-of :value]
        length [length-of :value]
        type [type-of :value] ;-- type of null is null
        words [words-of :value]
        head [head-of :value]
        tail [tail-of :value]
    ][
        fail/where ["Unknown reflector:" property] 'property
    ]
]


; https://forum.rebol.info/t/the-benefits-of-a-falsey-null-any-major-drawbacks/675
;
; Unfortunately, new functions are needed here vs. just adaptations, because
; the spec of IF and EITHER etc. do not take <opt> :-(
;
if: func [
    return: [<opt> any-value!]
    condition [<opt> any-value!]
    branch [block! action!]
    ;-- /OPT processing would be costly, omit the refinement for now
] compose/deep [
    (:lib/if) (:lib/to-value) :condition :branch
]
either: func [
    return: [<opt> any-value!]
    condition [<opt> any-value!]
    true-branch [block! action!]
    false-branch [block! action!]
    ;-- /OPT processing would be costly, omit the refinement for now
] compose/deep [
    (:lib/either) (:lib/to-value) :condition :true-branch :false-branch
]
while: adapt 'lib/while compose/deep [
    condition: reduce [quote (:lib/to-value) as group! :condition]
]
any: function [
    return: [<opt> any-value!]
    block [block!]
] compose/deep [
    (:lib/loop-until) [
        (:lib/if) value: (:lib/to-value) do/next block 'block [
            return :value
        ]
        (:lib/tail?) block
    ]
    return null
]
all: function [
    return: [<opt> any-value!]
    block [block!]
] compose/deep [
    value: null
    (:lib/loop-until) [
        ;-- NOTE: uses the old-style UNLESS, as its faster than IF NOT
        (:lib/unless) value: (:lib/to-value) do/next block 'block [
            return null
        ]
        (:lib/tail?) block
    ]
    :value
]
find: chain [:lib/find | :opt]
select: :lib/select* ;-- old variation that returned null when not found
case: function [
    return: [<opt> any-value!]
    cases [block!]
    /all
    ;-- /OPT processing would be costly, omit the refinement for now
] compose/deep [
    result: null

    (:lib/loop-until) [
        condition: do/next cases 'cases
        lib/if lib/tail? cases [return :condition] ;-- "fallout"
        (:lib/if) (:lib/to-value) :condition [
            result: (:lib/to-value) do ensure block! cases/1

            ;-- NOTE: uses the old-style UNLESS, as its faster than IF NOT
            (:lib/unless) all [return :result]
        ]
        (:lib/tail?) cases: (:lib/next) cases
    ]
    :result
]


choose: function [
    {Like CASE but doesn't evaluate blocks https://trello.com/c/noVnuHwz}
    choices [block!] /local result
] compose/deep [
    (:lib/loop-until) [
        (:lib/if) (:lib/to-value) do/next choices 'choices [
            return choices/1
        ]
        (:lib/tail?) choices: (:lib/next) choices
    ]
    return null
]

; Renamed, tightened, and extended with new features
;
file-to-local: :to-local-file
local-to-file: :to-rebol-file
unset 'to-local-file
unset 'to-rebol-file


; https://forum.rebol.info/t/text-vs-string/612
;
text!: (string!)
text?: (:string?)
to-text: (:to-string)


; https://forum.rebol.info/t/reverting-until-and-adding-while-not-and-until-not/594
;
; Note: WHILE-NOT can't be written correctly in usermode R3-Alpha (RETURN
; won't work definitionally.)  Assume we'll never bootstrap under R3-Alpha.
;
until: :loop-until
while-not: adapt 'while compose/deep [
    condition: reduce [
        quote (:lib/not) quote (:lib/to-value) as group! :condition
    ]
]
until-not: adapt 'until compose/deep [
    body: reduce [
        quote (:lib/not) quote (:lib/to-value) as group! :body
    ]
]


; https://trello.com/c/XnDsvsM0
;
assert [find words-of :ensure 'test]
really: func [optional [<opt> any-value!]] [
    if null? :optional [
        fail/where [
            "REALLY expects argument to be non-null"
        ] 'optional
    ]
    return :optional
]

; https://trello.com/c/Bl6Znz0T
;
deflate: specialize 'compress [gzip: false | only: true] ;; "raw"
inflate: specialize 'decompress [gzip: false | only: true] ;; "raw"
gzip: specialize 'compress [gzip: true]
gunzip: specialize 'decompress [gzip: true]
compress: decompress: does [
    fail "COMPRESS/DECOMPRESS replaced by gzip/gunzip/inflate/deflate"
]

; https://trello.com/c/9ChhSWC4/
;
switch: adapt 'switch [
    cases: map-each c cases [
        lib/case [
            lit-word? :c [to word! c]
            lit-path? :c [to path! c]

            path? :c [
                fail/where ["Switch now evaluative" c] 'cases
            ]
            word? :c [
                if not datatype? get c [
                    fail/where ["Switch now evaluative" c] 'cases
                ]
                get c
            ]

            true [:c]
        ]
    ]
]

; https://forum.rebol.info/t/method-and-the-argument-against-procedure/710
;
actionmaker: lib/function [
    return: [action!]
    gather-locals [logic!]
    spec [block!]
    body [block!]
][
    generator: either find spec [return: <void>] [
        spec: replace copy spec [<void>] [] ;-- keep RETURN: as local
        body: compose [return: :leave (body)]
        either gather-locals [:lib/procedure] [:lib/proc]
    ][
        either gather-locals [:lib/function] [:lib/func]
    ]
    generator spec body
]

func: specialize 'actionmaker [gather-locals: false]
function: specialize 'actionmaker [gather-locals: true]
unset 'procedure
unset 'proc
