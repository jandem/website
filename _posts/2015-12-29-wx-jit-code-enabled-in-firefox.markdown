---
layout: post
title:  "W^X JIT-code enabled in Firefox"
date:   "2015-12-29 22:30:00"
categories: mozilla
---
Back in June, I [added](https://bugzilla.mozilla.org/show_bug.cgi?id=977805) an option to SpiderMonkey to enable W^X protection of JIT code. The past weeks I've been [working on](https://bugzilla.mozilla.org/show_bug.cgi?id=1215479) fixing the remaining performance issues and yesterday I enabled W^X on the Nightly channel, on all platforms. What this means is that each page holding JIT code is either executable *or* writable, never both at the same time.

### Why?

Almost all JITs (including the ones in Firefox until now) allocate memory pages for code with RWX (read-write-execute) permissions. JITs typically need to *patch* code (for inline caches, for instance) and with writable memory they can do that with no performance overhead. RWX memory introduces some problems though:

* **Security**: RWX pages make it easier to exploit certain bugs. As a result, all modern operating systems store code in executable but non-writable memory, and data is usually not executable, see [W^X](https://en.wikipedia.org/wiki/W^X) and [DEP](https://en.wikipedia.org/wiki/Data_Execution_Prevention). RWX JIT-code is an exception to this rule and that makes it an interesting target.
* **Memory corruption**: I've seen some memory dumps for crashes in JIT-code that might have been caused by memory corruption elsewhere. All memory corruption bugs are serious, but *if* it happens for whatever reason, it's much better to crash immediately.

### How It Works
With W^X enabled, all JIT-code pages are non-writable by default. When we need to patch JIT-code for some reason, we use a [RAII-class](https://en.wikipedia.org/wiki/Resource_Acquisition_Is_Initialization), `AutoWritableJitCode`, to make the page(s) we're interested in writable (RW), using [VirtualProtect](https://msdn.microsoft.com/en-us/library/windows/desktop/aa366898%28v=vs.85%29.aspx) on Windows and [mprotect](http://man7.org/linux/man-pages/man2/mprotect.2.html) on other platforms. The destructor then toggles this back from RW to RX when we're done with it.

(As an aside, an alternative to W^X is a dual-mapping scheme: pages are mapped twice, once as RW and once as RX. In 2010, some people [wrote patches](https://bugzilla.mozilla.org/show_bug.cgi?id=506693) to implement this for TraceMonkey, but this work never landed. This approach avoids the mprotect overhead, but for this to be safe, the RW mapping should be in a separate process. It's also more complicated and introduces IPC overhead.)

### Performance
Last week I [fixed](https://bugzilla.mozilla.org/show_bug.cgi?id=1233818) implicit interrupt checks to work with W^X, [got rid of](https://bugzilla.mozilla.org/show_bug.cgi?id=1234246) some unnecessary mprotect calls, and [optimized](https://bugzilla.mozilla.org/show_bug.cgi?id=1235046) code poisoning to be faster with W^X.

After that, the performance overhead was pretty small on all benchmarks and websites I tested: Kraken and Octane are less than 1% slower with W^X enabled. On (ancient) SunSpider the overhead is bigger, because most tests finish in a few milliseconds, so any compile-time overhead is measurable. Still, it's less than 3% on Windows and Linux. On OS X it's less than 4% because mprotect is slower there.

I think W^X works well in SpiderMonkey for a number of reasons:

* We run bytecode in the interpreter before Baseline-compiling it. On the web, most functions have less than ~10 calls or loop iterations, so we never JIT those and we don't have any memory protection overhead.
* The Baseline JIT uses [IC stubs](https://en.wikipedia.org/wiki/Inline_caching) for most operations, but we use indirect calls here, so we don't have to make code writable when attaching stubs. Baseline stubs also share code, so only the first time we attach a particular stub we compile code for it. Ion IC stubs do require us to make memory writable, but Ion doesn't use ICs as much as Baseline.
* For asm.js (and soon [WebAssembly](https://bugzilla.mozilla.org/show_bug.cgi?id=1188259)!), we do [AOT-compilation](https://en.wikipedia.org/wiki/Ahead-of-time_compilation) of the whole module. After compilation, we need only one mprotect call to switch everything from RW to RX. Furthermore, this code is only modified on some slow paths, so there's basically no performance overhead for asm.js/WebAssembly code.

### Conclusion
I've enabled W^X protection for all JIT-code in Firefox Nightly. Assuming we don't run into bugs or serious performance issues, this will ship in Firefox 46.

Last but not least, thanks to the OpenBSD and HardenedBSD teams for being [brave](http://undeadly.org/cgi?action=article&sid=20151021191401) enough to [flip](https://bugzilla.mozilla.org/show_bug.cgi?id=1215479#c12) the W^X switch [before](https://bugzilla.mozilla.org/show_bug.cgi?id=1215479#c7) we did!