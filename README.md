# webkit-jsc-ios16-regression: Demo of a regression in iOS 16 beta 1+2: running WASM > 10 MB asserts in `slow_path_wasm_loop_osr`.

If you have a WebAssembly module with > 10 MB of code, containing code with a hot loop, WebKit fails an internal assertion inside JavaScriptCore.

As a result, the `com.apple.WebKit.WebContent` process crashes, and Safari/WKWebView shows an error message.

## Steps

1. Get an iOS/iPadOS device or simulator running iOS 16 Developer Beta 1 or 2.
2. In Safari, visit [loop-bad.html](loop-bad.html).

### Expected: 
Web page loads and says "Loading wasm... Loaded. Success!"
### Actual:
`WebContent` crashes. Safari shows an error: "A problem repeatedly occurred on *URL*".

See [crash-beta2.txt](crash-beta2.txt) for a sample crash log.

## Regression

The page loads and runs correctly on iOS 15.5.

It also runs correctly on macOS 12.4 and 13.0 Developer Beta.

If the `wasm` file has < 10 MB of code, there is no crash. See [loop-good.html](loop-good.html).

## Notes

### Cause

The failure is caused by WebKit commit [`e38fc8815`](https://github.com/WebKit/WebKit/commit/e38fc8815d7063e888a1eb3ecb2c7c93ba3fbe84) for bug [234587](https://bugs.webkit.org/show_bug.cgi?id=234587) "Allow loop tier up to the Air tier".

As of that commit, the crash is at [`JavaScriptCore/wasm/WasmSlowPaths.cpp:203`](https://github.com/WebKit/WebKit/commit/e38fc8815d7063e888a1eb3ecb2c7c93ba3fbe84#diff-8ef011487f54489d434fd97bb37b55273a415ddaf4968f3760a0af07ae6b855dR203):
```cpp
    RELEASE_ASSERT(osrEntryScratchBufferSize >= osrEntryData.values.size());
```

`osrEntryScratchBufferSize` is 0, but `osrEntryData.values.size()` is > 0.

### Explanation

Apparently there are two different modes for the "BBQ" JIT: "Air" and "B3".  Normally, Air is used.

However, on iOS only, WASM modules over 10 MB fall back to B3. See `JavaScriptCore/runtime/OptionsList.h`:

```
    v(Size, webAssemblyBBQAirModeThreshold, isIOS() ? (10 * MB) : 0, Normal, "If 0, we always use BBQ Air. If Wasm module code size hits this threshold, we compile Wasm module with B3 BBQ mode.") \
```

The commit above added code in `WASM_SLOW_PATH_DECL(loop_osr)` that assumes that if `Options::wasmLLIntTiersUpToBBQ()` is true, then Air must have been used. That is not the case on iOS when the module is over 10 MB.

### Potential fix

Make this code path check whether B3 was forced, exactly the same as the code in `JavaScriptCore/wasm/WasmBBQPlan.cpp` that checks `webAssemblyBBQAirModeThreshold`. If it was, fall back to the older code in the `else` clause below.

### Tests

Apparently, none of the JavaScriptCore automated tests cover the code path that falls back from Air to B3.

To see failures, run `./Tools/Scripts/run-javascriptcore-tests --env-vars JSC_webAssemblyBBQAirModeThreshold=1`.

I got the following failures:

```
** The following JSC stress test failures have been introduced:
	microbenchmarks/interpreter-wasm.js.default
	microbenchmarks/memcpy-wasm-large.js.bytecode-cache
	microbenchmarks/memcpy-wasm-large.js.default
	microbenchmarks/memcpy-wasm-large.js.dfg-eager
	microbenchmarks/memcpy-wasm-large.js.dfg-eager-no-cjit-validate
	microbenchmarks/memcpy-wasm-large.js.eager-jettison-no-cjit
	microbenchmarks/memcpy-wasm-large.js.ftl-eager
	microbenchmarks/memcpy-wasm-large.js.ftl-eager-no-cjit-b3o1
	microbenchmarks/memcpy-wasm-large.js.ftl-no-cjit-b3o0
	microbenchmarks/memcpy-wasm-large.js.ftl-no-cjit-no-inline-validate
	microbenchmarks/memcpy-wasm-large.js.ftl-no-cjit-no-put-stack-validate
	microbenchmarks/memcpy-wasm-large.js.ftl-no-cjit-small-pool
	microbenchmarks/memcpy-wasm-large.js.ftl-no-cjit-validate-sampling-profiler
	microbenchmarks/memcpy-wasm-large.js.mini-mode
	microbenchmarks/memcpy-wasm-large.js.no-cjit-validate-phases
	microbenchmarks/memcpy-wasm-large.js.no-ftl
	microbenchmarks/memcpy-wasm-large.js.no-llint
	microbenchmarks/memcpy-wasm-medium.js.ftl-eager
	microbenchmarks/memcpy-wasm-small.js.dfg-eager-no-cjit-validate
	microbenchmarks/memcpy-wasm-small.js.eager-jettison-no-cjit
	microbenchmarks/memcpy-wasm-small.js.ftl-eager-no-cjit-b3o1
	microbenchmarks/memcpy-wasm-small.js.ftl-no-cjit-b3o0
	microbenchmarks/memcpy-wasm-small.js.ftl-no-cjit-no-inline-validate
	microbenchmarks/memcpy-wasm-small.js.ftl-no-cjit-no-put-stack-validate
	microbenchmarks/memcpy-wasm-small.js.ftl-no-cjit-small-pool
	microbenchmarks/memcpy-wasm-small.js.ftl-no-cjit-validate-sampling-profiler
	microbenchmarks/memcpy-wasm-small.js.no-cjit-validate-phases
	microbenchmarks/memcpy-wasm.js.bytecode-cache
	microbenchmarks/memcpy-wasm.js.default
	microbenchmarks/memcpy-wasm.js.dfg-eager
	microbenchmarks/memcpy-wasm.js.dfg-eager-no-cjit-validate
	microbenchmarks/memcpy-wasm.js.eager-jettison-no-cjit
	microbenchmarks/memcpy-wasm.js.ftl-eager
	microbenchmarks/memcpy-wasm.js.ftl-eager-no-cjit-b3o1
	microbenchmarks/memcpy-wasm.js.ftl-no-cjit-b3o0
	microbenchmarks/memcpy-wasm.js.ftl-no-cjit-no-inline-validate
	microbenchmarks/memcpy-wasm.js.ftl-no-cjit-no-put-stack-validate
	microbenchmarks/memcpy-wasm.js.ftl-no-cjit-small-pool
	microbenchmarks/memcpy-wasm.js.ftl-no-cjit-validate-sampling-profiler
	microbenchmarks/memcpy-wasm.js.no-cjit-validate-phases
	microbenchmarks/memcpy-wasm.js.no-ftl
	microbenchmarks/memcpy-wasm.js.no-llint
	stress/sampling-profiler-wasm.js.default
	wasm.yaml/wasm/function-tests/br-if-loop-less-than.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/function-tests/loop-mult.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/function-tests/loop-sum.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/function-tests/memcpy-wasm-loop.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/multi-value-spec-tests/loop.wast.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/references-spec-tests/memory_copy.wast.js.wasm-eager-jettison
	wasm.yaml/wasm/references-spec-tests/memory_copy.wast.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/references-spec-tests/memory_fill.wast.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/references-spec-tests/memory_grow.wast.js.default-wasm
	wasm.yaml/wasm/references-spec-tests/memory_grow.wast.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/references-spec-tests/memory_grow.wast.js.wasm-no-tls-context
	wasm.yaml/wasm/regress/llint-callee-saves-with-fast-memory.js.default-wasm
	wasm.yaml/wasm/regress/llint-callee-saves-with-fast-memory.js.wasm-eager
	wasm.yaml/wasm/regress/llint-callee-saves-with-fast-memory.js.wasm-eager-jettison
	wasm.yaml/wasm/regress/llint-callee-saves-with-fast-memory.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/regress/llint-callee-saves-with-fast-memory.js.wasm-no-tls-context
	wasm.yaml/wasm/regress/llint-callee-saves-with-fast-memory.js.wasm-slow-memory
	wasm.yaml/wasm/regress/llint-callee-saves-without-fast-memory.js.default-wasm
	wasm.yaml/wasm/regress/llint-callee-saves-without-fast-memory.js.wasm-eager
	wasm.yaml/wasm/regress/llint-callee-saves-without-fast-memory.js.wasm-eager-jettison
	wasm.yaml/wasm/regress/llint-callee-saves-without-fast-memory.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/regress/llint-callee-saves-without-fast-memory.js.wasm-no-tls-context
	wasm.yaml/wasm/regress/llint-callee-saves-without-fast-memory.js.wasm-slow-memory
	wasm.yaml/wasm/spec-tests/float_exprs.wast.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/spec-tests/loop.wast.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/spec-tests/memory_grow.wast.js.default-wasm
	wasm.yaml/wasm/spec-tests/memory_grow.wast.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/spec-tests/memory_grow.wast.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/exception-liveness-tier-up.js.default-wasm
	wasm.yaml/wasm/stress/exception-liveness-tier-up.js.wasm-eager
	wasm.yaml/wasm/stress/exception-liveness-tier-up.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/exception-liveness-tier-up.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/exception-liveness-tier-up.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/exception-liveness-tier-up.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-basic.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-basic.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-basic.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-basic.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-basic.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-basic.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-many-locals-f32.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-many-locals-f32.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-many-locals-f32.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-many-locals-f32.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-locals-f32.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-locals-f32.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-many-locals-f64.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-many-locals-f64.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-many-locals-f64.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-many-locals-f64.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-locals-f64.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-locals-f64.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-many-locals-i32.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-many-locals-i32.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-many-locals-i32.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-many-locals-i32.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-locals-i32.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-locals-i32.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-many-locals-i64.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-many-locals-i64.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-many-locals-i64.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-many-locals-i64.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-locals-i64.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-locals-i64.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f32.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f32.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f32.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f32.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f32.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f32.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f64.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f64.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f64.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f64.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f64.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-stacks-f64.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i32.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i32.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i32.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i32.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i32.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i32.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i64.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i64.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i64.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i64.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i64.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-many-stacks-i64.js.wasm-slow-memory
	wasm.yaml/wasm/stress/osr-entry-with-loop-arguments.js.default-wasm
	wasm.yaml/wasm/stress/osr-entry-with-loop-arguments.js.wasm-eager
	wasm.yaml/wasm/stress/osr-entry-with-loop-arguments.js.wasm-eager-jettison
	wasm.yaml/wasm/stress/osr-entry-with-loop-arguments.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/stress/osr-entry-with-loop-arguments.js.wasm-no-tls-context
	wasm.yaml/wasm/stress/osr-entry-with-loop-arguments.js.wasm-slow-memory
	wasm.yaml/wasm/stress/top-most-enclosing-stack.js.wasm-eager
	wasm.yaml/wasm/stress/top-most-enclosing-stack.js.wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above-no-consts.wasm)-default-wasm
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above-no-consts.wasm)-wasm-eager
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above-no-consts.wasm)-wasm-eager-jettison
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above-no-consts.wasm)-wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above-no-consts.wasm)-wasm-no-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above-no-consts.wasm)-wasm-slow-memory
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above.wasm)-default-wasm
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above.wasm)-wasm-eager
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above.wasm)-wasm-eager-jettison
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above.wasm)-wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above.wasm)-wasm-no-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop-branch-above.wasm)-wasm-slow-memory
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop.wasm)-default-wasm
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop.wasm)-wasm-eager
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop.wasm)-wasm-eager-jettison
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop.wasm)-wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop.wasm)-wasm-no-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-inner-loop.wasm)-wasm-slow-memory
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-multiple-enclosed-contexts.wasm)-default-wasm
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-multiple-enclosed-contexts.wasm)-wasm-eager
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-multiple-enclosed-contexts.wasm)-wasm-eager-jettison
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-multiple-enclosed-contexts.wasm)-wasm-no-cjit-yes-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-multiple-enclosed-contexts.wasm)-wasm-no-tls-context
	wasm.yaml/wasm/wast-tests/harness.js.(osr-entry-multiple-enclosed-contexts.wasm)-wasm-slow-memory
```
