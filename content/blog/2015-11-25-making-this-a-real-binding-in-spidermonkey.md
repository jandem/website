+++
title = "Making `this` a real binding in SpiderMonkey"
date = 2015-11-25
aliases = ["blog/2015/11/25/making-this-a-real-binding-in-spidermonkey/"]
[taxonomies]
tags = ["Mozilla"]
+++
Last week I landed [bug 1132183](https://bugzilla.mozilla.org/show_bug.cgi?id=1132183), a pretty large patch rewriting the implementation of `this` in SpiderMonkey.

### How *this* Works In JS
In JS, when a function is called, an implicit `this` argument is passed to it. In strict mode, `this` inside the function just returns that value:

```js
function f() { "use strict"; return this; }
f.call(123); // 123
```

In non-strict functions, `this` always returns an object. If the this-argument is a primitive value, it's *boxed* (converted to an object):

```js
function f() { return this; }
f.call(123); // returns an object: new Number(123)
```

Arrow functions don't have their own `this`. They [inherit](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Functions/Arrow_functions#Lexical_this) the `this` value from their enclosing scope:

```js
function f() {
    "use strict";
    () => this; // `this` is 123
}
f.call(123);
```

And, of course, `this` can be used inside `eval`:

```js
function f() {
    "use strict";
    eval("this"); // 123
}
f.call(123);
```

Finally, `this` can also be used in top-level code. In that case it's *usually* the global object (lots of hand waving here).

### How *this* Was Implemented
Until last week, here's how this worked in SpiderMonkey:

* Every stack frame had a this-argument,
* Each `this` expression in JS code resulted in a single bytecode op (JSOP_THIS),
* This bytecode op *boxed* the frame's this-argument if needed and then returned the result.

Special case: to support the [lexical this](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Functions/Arrow_functions#Lexical_this) behavior of arrow functions, we emitted JSOP\_THIS when we defined (cloned) the arrow function and then copied the result to a slot on the function. Inside the arrow function, JSOP\_THIS would then [load the value from that slot](/blog/2014/04/11/fast-arrow-functions-in-firefox-31/).

There was some more complexity around `eval`: eval-frames also had their own this-slot, so whenever we did a direct `eval` we'd ensure the outer frame had a boxed (if needed) this-value and then we'd copy it to the eval frame.

### The Problem
The most serious problem was that it's fundamentally incompatible with ES6 [*derived class constructors*](https://hacks.mozilla.org/2015/08/es6-in-depth-subclassing/), as they initialize their 'this' value dynamically when they call super(). Nested arrow functions (and eval) then have to 'see' the initialized `this` value, but that was impossible to support because arrow functions and eval frames used *their own* (copied) this value, instead of the updated one.

Here's a worst-case example:

```js
class Derived extends Base {
    constructor() {
        var arrow = () => this;

        // Runtime error: `this` is not initialized inside `arrow`.
        arrow();

        // Call Base constructor, initialize our `this` value.
        eval("super()");

        // The arrow function now returns the initialized `this`.
        arrow();
    }
}
```
We currently (temporarily!) throw an exception when arrow functions or eval are used in derived class constructors in Firefox Nightly.

Boxing `this` lazily also added extra complexity and overhead. I already mentioned how we had to *compute* `this` whenever we used `eval`.

### The Solution
To fix these issues, I made `this` a real binding:

* Non-arrow functions that use `this` or `eval` define a special `.this` variable,
* In the function prologue, we get the this-argument, box it if needed (with a new op, JSOP_FUNCTIONTHIS) and store it in `.this`,
* Then we simply use that variable each time `this` is used.

Arrow functions and eval frames no longer have their own this-slot, they just reference the `.this` variable of the outer function. For instance, consider the function below:

```js
function f() {
    return () => this.foo();
}
```

We generate bytecode similar to the following pseudo-JS:

```js
function f() {
    var .this = BoxThisIfNeeded(this);
    return () => (.this).foo();
}
```

I decided to call this variable `.this`, because it nicely matches the other magic 'dot-variable' we already had, `.generator`. Note that these are not valid variable names so JS code can't access them. I only had to make sure with-statements don't intercept the `.this` lookup when `this` is used inside a with-statement...

Doing it this way has a number of benefits: we only have to check for primitive `this` values at the start of the function, instead of each time `this` is accessed (although in most cases our optimizing JIT could/can eliminate these checks, when it knows the this-argument must be an object). Furthermore, we no longer have to do anything special for arrow functions or eval; they simply access a 'variable' in the enclosing scope and the engine already knows how to do that.

In the global scope (and in eval or arrow functions in the global scope), we don't use a binding for `this` (I tried this initially but it turned out to be pretty complicated). There we emit JSOP_GLOBALTHIS for each this-expression, then that op gets the `this` value from a reserved slot on the lexical scope. This global `this` value never changes, so the JITs can get it from the global lexical scope at compile time and bake it in as a constant :) (Well.. in most cases. The embedding can run scripts with a non-syntactic scope chain, in that case we have to do a scope walk to find the nearest lexical scope. This should be uncommon and can be optimized/cached if needed.)

### The Debugger
The main nuisance was fixing the debugger: because we only give (non-arrow) functions that use `this` or `eval` their own this-binding, what do we do when the debugger wants to know the this-value of a frame *without* a this-binding?

Fortunately, the debugger (DebugScopeProxy, actually) already knew how to solve a similar problem that came up with `arguments` (functions that don't use `arguments` don't get an arguments-object, but the debugger can request one anyway), so I was able to cargo-cult and do something similar for `this`.

### Other Changes
Some other changes I made in this area:

* In [bug 1125423](https://bugzilla.mozilla.org/show_bug.cgi?id=1125423) I got rid of the innerObject/outerObject/thisValue Class hooks (also known as [the holy grail](https://bugzilla.mozilla.org/show_bug.cgi?id=604516)). Some scope objects had a (potentially effectful) thisValue hook to override their `this` behavior, this made it hard to see what was going on. Getting rid of that made it much easier to understand and rewrite the code.
* I posted patches in [bug 1227263](https://bugzilla.mozilla.org/show_bug.cgi?id=1227263) to remove the `this` slot from generator objects, eval frames and global frames.
* IonMonkey was unable to compile top-level scripts that used `this`. As I mentioned above, compiling the new JSOP_GLOBALTHIS op is pretty simple in most cases; I wrote a small patch to fix this ([bug 922406](https://bugzilla.mozilla.org/show_bug.cgi?id=922406)).
  
### Conclusion
We changed the implementation of `this` in Firefox 45. The difference is (hopefully!) not observable, so these changes should not break anything or affect code directly. They do, however, pave the way for more performance work and fully compliant [ES6 Classes](http://www.2ality.com/2015/02/es6-classes-final.html)! :)
