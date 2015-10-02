---
layout: post
title:  "Using segfaults to interrupt JIT code"
date:   2014-02-18
categories: mozilla
disqus_identifier: "7 http://www.jandemooij.nl/blog/?p=7"
---
(I just installed my own blog so I decided to try it out by writing a bit about interrupt checks :) )

Most browsers allow the user to interrupt JS code that runs too long, for instance because it’s stuck in an infinite loop. This is especially important for Firefox as it uses a single process for chrome and content (though that’s [about to change][e10s]), so without this dialog a website could hang the browser forever and the user is forced to kill the browser and could lose work. Firefox will show the slow script dialog when a script runs for more than 10 seconds (power users can [customize][timeoutpref] this).

### SpiderMonkey
Firefox uses a separate (watchdog) thread to interrupt script execution. It triggers the “operation callback” (by calling JS_TriggerOperationCallback) every second. Whenever this happens, SpiderMonkey promises to call the operation callback as soon as possible. The browser’s operation callback then checks the execution limit, shows the dialog if necessary and returns true to continue execution or false to stop the script.

How this works internally is that JS_TriggerOperationCallback sets a flag on the JSRuntime, and the main thread is responsible for checking this flag every now and then and invoke the operation callback if it’s set. We check this flag for instance on JS function calls and loop headers. We have to do this both for scripts running in the interpreter and the JITs, of course. For example, consider this function:

{% highlight javascript %}
function f() {
    for (var i=0; i<100000000; i++) {
    }
}
{% endhighlight %}

Until Firefox 26, IonMonkey would emit the following code for this loop:

Note that the loop itself is only 4 instructions, but we need 2 more instructions for the interrupt check. These 2 instructions can measurably slow down tight loops like this one. Can we do better?

### OdinMonkey
OdinMonkey is our ahead-of-time (AOT) compiler for asm.js. When developing Odin, we (well, mostly Luke) tried to shave off as much overhead as possible, for instance we want to get rid of bounds checks and interrupt checks if possible to close the gap with native code. The result is that Odin does not emit loop interrupt checks at all! Instead, it makes clever use of signal handlers.

When the watchdog thread wants to interrupt Odin execution on the main thread, it uses mprotect (Unix) or VirtualProtect (Windows) to clear the executable bit of the asm.js code that’s currently executing. This means any asm.js code running on the main thread will immediately segfault. However, before the kernel terminates the process, it gives us one last chance to interfere: because we installed our own signal handler, we can trap the segfault and, if the address is inside asm.js code, we can make the signal handler return to a little trampoline that calls the operation callback. Then we can either jump back to the faulting pc or stop execution by returning from asm.js code. (Note that handling segfaults is serious business: if the faulting address is not inside asm.js code, we have an unrelated, “real” crash and we must be careful not to interfere in any way, so that we don’t sweep real crashes under the rug.)

This works really well and is pretty cool: asm.js code has no runtime interrupt checks, just like native code, but we can still interrupt it and show our slow script dialog.

### IonMonkey
A while later, Brian Hackett [wanted to see][ionbug] if we could make IonMonkey (our optimizing JIT) as fast as OdinMonkey on asm.js code. This means he also [had to][ionbug2] eliminate interrupt checks for normal JS code running in Ion (we don’t bother doing this for our Baseline JIT as we’ll spend most time in Ion code anyway).

The first thought is to do exactly what Odin does: mprotect all Ion-code, trigger a segfault and return to some trampoline where we handle the interrupt. It’s not that simple though, because Ion-code can modify the GC heap. For instance, when we store a boxed Value, we emit two machine instructions on 32-bit platforms, to store the type tag and the payload. If we use signal handlers the same way Odin does, it’s possible we store the type tag but are interrupted before we can store the payload. Everything will be fine until the GC traces the heap and crashes horribly. Even worse, an attacker could use this to access arbitrary memory.

There’s another problem: when we call into C++ from Ion code, the register allocator tracks GC pointers stored in registers or on the stack, so that the garbage collector can mark them. If we call the operation callback at arbitrary points though, we don’t have this information. This is a problem because the operation callback is also used to trigger garbage collections, so it has to know where all GC pointers are.

What Brian implemented instead is the following:

1. The watchdog thread will mprotect all Ion code (we had to use a separate allocator for Ion code so that we can do this efficiently).
2. The main thread will segfault and call our signal handler.
3. The signal handler unprotects all Ion-code again and patches all loop backedges (jump instructions) to jump to a slow, out-of-line path instead.
4. We return from the signal handler and continue execution until we reach the next (patched) loop backedge and call the operation callback, show the slow script dialog, etc.
5. All loop backedges are patched again to jump to the loop header.

Note that this only applies to the loop interrupt check: there’s another interrupt check when we enter a script, but for JIT code we combine it with the stack overflow check: when we trigger the operation callback, the watchdog thread also sets the stack limit to a very high value so that the stack check always fails and we also end up in the VM where we can handle the operation callback and reset the stack limit :)

### Conclusion
Firefox 26 and newer uses signal handlers and segfaults for interrupting Ion code. This was a measurable speedup, especially for tight loops. For example, the empty for-loop I posted earlier runs 33% faster (43 ms to 29 ms). It helps more interesting loops as well, for instance Octane-crypto got ~8% faster.


[e10s]: http://billmccloskey.wordpress.com/2013/12/05/multiprocess-firefox/
[timeoutpref]: http://kb.mozillazine.org/Dom.max_script_run_time
[ionbug]: https://bugzilla.mozilla.org/show_bug.cgi?id=860923
[ionbug2]: https://bugzilla.mozilla.org/show_bug.cgi?id=864220
