# Regression in iOS 16 beta 1 + 2: running WASM > 10 MB asserts in `slow_path_wasm_loop_osr`

In iOS 16 Developer Beta 1 or 2, if you have a WebAssembly module with > 10 MB of code, containing code with a hot loop, WebKit fails an internal assertion inside JavaScriptCore.

As a result, the `com.apple.WebKit.WebContent` process crashes, and Safari or WKWebView show an error message.

## Steps

Files are hosted at [https://krevis-figma.github.io/webkit-jsc-ios16-regression/](https://krevis-figma.github.io/webkit-jsc-ios16-regression/).

1. Get an iOS/iPadOS device or simulator running iOS 16 Developer Beta 1 or 2.
2. In Safari, visit [loop-bad.html](https://krevis-figma.github.io/webkit-jsc-ios16-regression/loop-bad.html).

This loads a WebAssembly module `loop-bad.wasm` and calls a function that runs a simple loop. It's the same code as in JavaScriptCore test [`stress/osr-entry-basic.js`](https://github.com/WebKit/WebKit/blob/main/JSTests/wasm/stress/osr-entry-basic.js). The module contains other unused functions to make it > 10 MB large.

### Expected: 
Web page loads and says "Loading wasm... Loaded. Success!"
### Actual:
`WebContent` crashes. Safari shows an error: "A problem repeatedly occurred on *URL*".

See [crash-beta2.txt](crash-beta2.txt) for a sample crash log.

## Regression

The page loads and runs correctly on iOS 15.5. It's broken in iOS 16 Developer Beta 1 and 2.

It also runs correctly in Safari in macOS 12.4 and macOS 13.0 Developer Beta.

If the `wasm` file has < 10 MB of code, there is no crash. See [loop-good.html](https://krevis-figma.github.io/webkit-jsc-ios16-regression/loop-good.html).

When using a `WKWebView` in an app, the behavior is the same as in Safari.

## Notes

### References

WebKit bug [242294](https://bugs.webkit.org/show_bug.cgi?id=242294)
Apple Feedback Reporter IDs: FB10107783, FB10120166

### Cause

The failure was caused by WebKit commit [`e38fc8815`](https://github.com/WebKit/WebKit/commit/e38fc8815d7063e888a1eb3ecb2c7c93ba3fbe84) for bug [234587](https://bugs.webkit.org/show_bug.cgi?id=234587) "Allow loop tier up to the Air tier".

As of that commit, the crash is at [`JavaScriptCore/wasm/WasmSlowPaths.cpp:203`](https://github.com/WebKit/WebKit/commit/e38fc8815d7063e888a1eb3ecb2c7c93ba3fbe84#diff-8ef011487f54489d434fd97bb37b55273a415ddaf4968f3760a0af07ae6b855dR203):
```cpp
    RELEASE_ASSERT(osrEntryScratchBufferSize >= osrEntryData.values.size());
```

`osrEntryScratchBufferSize` is 0, but `osrEntryData.values.size()` is > 0.

### Explanation

I'm not familiar with the JavaScriptCore JIT implementation, but here's what I've gleaned:

Apparently there are two different modes for the "BBQ" JIT: "Air" and "B3".  

Normally, Air is used. However, on iOS, WASM modules over 10 MB fall back to B3. See `JavaScriptCore/runtime/OptionsList.h`:

```cpp
    v(Size, webAssemblyBBQAirModeThreshold, isIOS() ? (10 * MB) : 0, Normal, "If 0, we always use BBQ Air. If Wasm module code size hits this threshold, we compile Wasm module with B3 BBQ mode.") \
```

and the code that checks the flag in `JavaScriptCore/wasm/WasmBBQPlan.cpp`:

```cpp
    // FIXME: Some webpages use very large Wasm module, and it exhausts all executable memory in ARM64 devices since the size of executable memory region is only limited to 128MB.
    // The long term solution should be to introduce a Wasm interpreter. But as a short term solution, we introduce heuristics to switch back to BBQ B3 at the sacrifice of start-up time,
    // as BBQ Air bloats such lengthy Wasm code and will consume a large amount of executable memory.
    bool forceUsingB3 = false;
    if (Options::webAssemblyBBQAirModeThreshold() && m_moduleInformation->codeSectionSize >= Options::webAssemblyBBQAirModeThreshold())
        forceUsingB3 = true;
    else if (!Options::wasmBBQUsesAir())
        forceUsingB3 = true;
```

The bad commit added code in `WASM_SLOW_PATH_DECL(loop_osr)` that assumes that if `Options::wasmLLIntTiersUpToBBQ()` is true, then Air must have been used. That is not the case when `forceUsingB3` is true.

### Potential fix

A [potential fix](3-fix.patch):

Make this code path check whether B3 was forced, exactly the same as the code in `JavaScriptCore/wasm/WasmBBQPlan.cpp` that checks `webAssemblyBBQAirModeThreshold`. If it was, fall back to the older code in the `else` clause below.


### Tests

Apparently, none of the JavaScriptCore automated tests cover the code path that falls back from Air to B3.

To see failures, run `./Tools/Scripts/run-javascriptcore-tests --env-vars JSC_webAssemblyBBQAirModeThreshold=1`.  I got 162 failures, all of which are fixed by the patch above.

Here's a [patch to add a regression test](1-add-regression-test.patch) for this bug.

Also, it seems like it would be a good idea to test the fallback-to-B3 path more widely. Here's a [patch to do this in the stress tests](2-add-stress-tests.patch), similar to the existing "wasm-b3" and "wasm-air" tests, neither of which caught this bug.
