# JavaScript execution

The native adapter in `lib/features/scripting/data/runtime/quickjs_runtime_io.dart`
loads a vendored QuickJS-NG 0.14.0 C bridge through Dart native assets. The package
`packages/getman_quickjs` builds from source with `native_toolchain_c` 0.19.2;
newer 0.19.5 requires a meta version incompatible with Flutter 3.44.4.
`tool/scripting/runtime-manifest.json` records source hashes and the MIT license.
No download, executable lookup, browser host API or external module loader is
available to guest JavaScript.

The vendored 0.14.0 `quickjs.c` includes one local allocation-failure fix:
`JS_NewObjectFromShape` checks failure when adding an array's `length` property
and frees the unfinished object, its current shape and property storage before
returning the exception. Sparse-array heap exhaustion otherwise dereferenced a
null property pointer on Linux. The upstream version remains 0.14.0; the source
manifest records the patched file hash. The native contract asserts a memory
limit result, zero live ownership counters and successful subsequent execution.

Each nonempty execution creates one isolate, runtime and context. At most two
isolates execute concurrently; additional calls queue. Empty scripts bypass the
engine. Cancellation removes queued admission or sets an atomic native flag.
The interrupt handler checks cancellation and a monotonic deadline, including
pending promises; no Dart callback must run on the blocked worker. Close cancels
active execution and drains completion before freeing native controls. Every
context, promise, exception, native string and runtime is released before return.

The bridge uses an aligned allocation header to track exact guest heap charges,
including allocator headers, with 32 MiB default. A failed allocation records a
memory-limit outcome even when QuickJS cannot allocate an error object. Stack is
bounded separately at 512 KiB. Source, actual serialized input and returned string
are bounded at 256 KiB, 8 MiB and 1 MiB respectively. Default execution deadline
is 1 second. Error text also obeys the output bound. Engine interruption is native,
not a Future timeout. The host owns the control until its worker has completed.

The injected bootstrap is an async function
`(input, runUser, reportDiagnostic)` returning a JSON
string. It closes over private envelope state and invokes `runUser(gm, console)`;
user return values do not become envelopes. The platform factory accepts
`bootstrapSource`, `encodeInput` and `decodeOutput` callbacks so shared protocol
validation can remain outside the native engine. Wrapper line counts are
subtracted from source diagnostics.

Native contract verification: `fvm flutter test --no-pub
 test/features/scripting/runtime/native_runtime_test.dart` (on one line).
Tests use the real compiled engine for async execution, source lines, infinite
loop/pending-promise timeout, heap exhaustion, active and queued cancellation,
concurrency admission, recovery, host capability absence and close. macOS native
unit execution is verified; Windows/Linux release builds remain unverified.
Runtime AOT measurements are recorded in the verification document; they do
not establish Flutter cold-boot or HTTP latency regression results. Rebuilds are automatic through the package build
hook during Flutter test/build; no precompiled desktop library is checked in.

The web adapter executes QuickJS WASM in a fresh dedicated Worker per run,
with the same two-slot admission and cancellation contract. `tool/scripting/`
pins quickjs-emscripten 0.31.0 and esbuild 0.25.12; `npm ci --prefix
 tool/scripting --ignore-scripts` followed by `npm run build --prefix
 tool/scripting` rebuilds the checked-in offline Worker, WASM and hash manifest.
The MIT license is bundled alongside them. Only build tooling uses npm.

Workers load WASM relative to their own URL; the adapter resolves the Worker
against document.baseURI, preserving GitHub Pages and other non-root deployments.
Guest source runs through QuickJS evalCode, never browser eval. No browser or
Worker globals are bound into the guest. Memory and stack limits, interrupt
checks and a pending-job pump enforce the engine budget. A host watchdog also
terminates stalled Workers. Cancel and close terminate active Workers; all normal
paths free result handles, context and runtime in finally before termination.
The guest deadline starts after WASM initializes; the host watchdog includes a
five-second startup allowance to handle slow local asset loading.

Chrome contracts run with `fvm flutter test --platform chrome
 test/features/scripting/runtime/web_runtime_test.dart`. Test-only asset symlinks
expose the same bundled files through Flutter's test directory server, including
a non-root base-href fixture. No CDN or internet service is needed at runtime.

Desktop C compilation explicitly selects C11. On Windows, the native-assets
hook also passes `/experimental:c11atomics`, matching upstream QuickJS-NG
CMake; the engine's `quickjs-c-atomics.h` uses `<stdatomic.h>` for MSVC as does
bridge cancellation. This requires a Visual Studio toolset supporting C11
atomics (VS 2022 17.5 or later). MSVC's C headers do not expose `max_align_t`,
so its allocator prefix uses the Windows SDK's `MEMORY_ALLOCATION_ALIGNMENT`
size, preserving malloc's 16-byte Win64 or 8-byte Win32 alignment. Other
compilers retain the standard `max_align_t` prefix.
`.github/workflows/scripting-native.yml`
compiles and runs the real engine contract separately on macOS, Windows and
Linux. Each platform's workflow result establishes verification for that
revision; the workflow definition alone is not evidence of a successful build.

The focused allocator contract runs without Flutter:
`bash packages/getman_quickjs/test/run_allocator_tests.sh` (macOS/Linux, C11
compiler required). It compiles the real bridge and vendored engine, checking
alignment, realloc contents, calloc zeroing, quota rejection and ownership
cleanup. It also compiles the MSVC prefix with `max_align_t` unavailable;
this regression catches the missing-type failure but does not replace the
Windows native contract's actual MSVC build.

Host-only atomic diagnostics count live execution controls and QuickJS runtimes.
The native contract checks zero after ordinary errors, deadline interruption,
heap exhaustion and cancellation/close. Counters add allocation/disposal
operations only and are not accessible through guest `gm` or JavaScript globals.

The shared API bootstrap starts synchronous named-test callbacks at registration;
async callbacks form a serial chain. An uncaught source exception stops queued
callbacks while completed tests and logs remain in the error envelope. Framework
catch boundaries rethrow QuickJS InternalError resource failures, so heap/stack
exhaustion and interruption cannot be mistaken for failed assertions. Ordinary
assertion failures remain isolated to their named test.

Input JSON is parsed as data inside the guest rather than inserted as an object
literal; this preserves literal `__proto__` keys. Successful engine envelopes can
contain bootstrap-caught user errors, so both adapters normalize their source
locations as well as uncaught engine diagnostics. Public repository tests run the
same API suite in native and Chrome. The repository accepts an AssetBundle for
embedding/testing and defaults to rootBundle. Browser tests use a real Dio HTTP
asset bundle because Flutter's browser test harness has no platform asset channel
and NetworkAssetBundle uses dart:io. Test symlinks expose the checked-in bootstrap,
Worker and WASM relative to the test wrapper URL; no guest engine is mocked.

## Request workflow and public API

HTTP requests own a `RequestScripts` bundle (API version 1). `SCRIPTS` occupies
request section 4, with `PRE-REQUEST` and `POST-RESPONSE`, `ENABLED`, executable
snippets and API help. Opening, saving, importing, diffing or exporting source
never executes it. WS/SSE/MCP requests do not run these hooks. Unknown versions
are preserved but blocked from execution.

`gm.variables.get/has/set/unset` reads collection → captured environment →
temporary overlay. Unsetting a temporary value exposes its lower layer.
Strings stay strings; finite numbers, booleans, null, arrays and plain JSON
objects become JSON text. Undefined, nonfinite numbers, BigInt, functions,
symbols and cycles are rejected. Map keys such as `__proto__` are ordinary data.

`gm.environment.get/has/set/unset` reads the selected environment snapshot and
proposes persistent changes. No selected environment makes writes fail. A stage
commits its patch against live repository state only after successful execution;
pre-stage failed tests also discard the patch and prevent HTTP. Post-stage failed
tests preserve HTTP and commit valid patches. Uncaught post errors preserve HTTP
and available diagnostics but discard that stage's patch. 4xx/5xx responses still
run the post hook; a network failure without a response does not.

`gm.request.url/method/body` exposes the template. `setUrl`, `setMethod`,
`setBody` and `headers.set/unset` alter only the sent copy and are pre-stage only.
Methods come from `HttpMethods.all`; setBody requires raw mode. Headers use
case-insensitive lookup. Auth serialization retains its existing precedence.
History records the original template and scripts, not resolved payloads.

`gm.response.status/durationMs/text()/json()/header(name)/lookup(path)` is
post-stage only. JSONPath supports root, dot members, bracket-quoted keys and
nonnegative array indices. Lookup returns `{found,value}` so explicit null is
distinct from a missing path. Regex extraction uses ordinary JavaScript.

`gm.jwt.decode(token)` decodes the UTF-8 JSON payload of a compact three-segment
JWS. It **does not verify signatures or expiry** and does not accept JWE.
`gm.base64.encode/decode` and `gm.base64url.encode/decode` operate on UTF-8 text;
malformed alphabets, padding, trailing bits and invalid UTF-8 fail explicitly.

`gm.test(name, callback)` accepts synchronous/async callbacks, preserves order
and repeated names with distinct IDs. `gm.expect(value).to` supports `equal`,
`deep.equal`, `be.a`, `contain`, `be.lessThan`, `be.greaterThan`, `be.within`,
`exist` and `not.equal`. Equality is strict, deep equality compares JSON, numeric
ranges are inclusive/finite, and `exist` includes null but excludes undefined.
An assertion failure does not prevent later tests; resource exhaustion fails the
stage. Console log/info/warn/error messages handle cycles and truncate visibly.
The defaults are 200 tests and 200 console messages/64 KiB per stage.

## Ownership, trust and display

Each SEND captures an execution ID, tab ID, request snapshot and environment ID.
Cancel, resend and close invalidate prior work. Every asynchronous boundary
rechecks ownership before committing or publishing. Switching tabs or the active
environment does not redirect existing work. A patch already admitted to the
serialized environment queue may finish after cancellation; no rollback is
promised for writes or HTTP already started. Environment deletion is never
undone by a late script patch. Ordinary editor updates and imports share the
same serialized queue, merging edits with their prior snapshot.

Local trust stores the request identity plus SHA-256 of API version and both
source strings. Enabling a stage cannot grant trust. Local source editing can
approve its exact content; imported or externally changed source shows a
`REVIEW SCRIPTS` dialog and requires `TRUST EXACT CONTENT`. Approval applies to
the displayed snapshot, even if the request changes while the dialog is open.
Trust never travels through request/workspace/Postman serialization.

`TESTS` and `CONSOLE` are transient per-execution views, including failures before
HTTP. Error locations navigate to the correct stage/line. Known secret values,
including new values assigned to existing secret keys, are masked on display.
This is literal-value redaction, not information-flow tracking; arbitrary
transforms may evade recognition. Source may contain literal secrets, so prefer
variables rather than embedding credentials.

Workspace JSON stores request.scripts; Postman round-trip uses inert
`x-getman-scripts`. External Postman events are rejected recursively before any
collection nodes are saved. There is no pm/npm/Node/fetch/module compatibility.
Code generation displays `Scripts not included` and never evaluates source.
Diff/merge treats each source/enablement field independently; conflicts choose
content and never concatenate code.

The unused Rules feature has been removed without migration. Hive IDs 7/8/9
remain retired and old Rules files are neither opened nor deleted automatically.

Completed diagnostics survive fatal stage errors, including real timeout and
heap exhaustion. The native context installs a bounded host-only diagnostic sink;
the bootstrap captures it privately and deletes the global before user source
runs. After each completed test or console update it emits a snapshot containing
only diagnostic primitive fields. Serialization uses captured JSON stringifying
of primitive strings, avoiding user getters and `toJSON` hooks. Native code keeps
the latest bounded snapshot outside the exhausted guest heap and frees it with
the execution control. The WASM worker keeps the same snapshot and forwards it to
the owner, allowing watchdog/cancellation to retain the latest received data.
Neither adapter evaluates recovery JavaScript or extends the guest deadline.
Fatal output restores only validated tests/logs; all variable/request/environment
proposals remain empty. Snapshot storage obeys the stage output quota.

Web builds do not request code assets. The native package build hook returns
before reading native target configuration when `buildCodeAssets` is false.
