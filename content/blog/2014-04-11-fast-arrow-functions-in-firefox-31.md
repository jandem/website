+++
title = "Fast arrow functions in Firefox 31"
date = 2014-04-11
aliases = ["blog/2014/04/11/fast-arrow-functions-in-firefox-31/"]
[taxonomies]
tags = ["Mozilla"]
+++
Last week I spent some time optimizing ES6 arrow functions. Arrow functions allow you to write function expressions like this:
```js
a.map(s => s.length);
```
Instead of the much more verbose:
```js
a.map(function(s){ return s.length });
```


Arrow functions are not just syntactic sugar though, they also bind their this-value lexically. This means that, unlike normal functions, arrow functions use the same this-value as the script in which they are defined. See the [documentation][arrowdocs] for more info.

Firefox has had support for arrow functions since Firefox 22, but they used to be slower than normal functions for two reasons:

1. **Bound functions**: SpiderMonkey used to do the equivalent of |arrow.bind(this)| whenever it evaluated an arrow expression. This made arrow functions slower than normal functions because calls to bound functions are currently not optimized or inlined in the JITs. It also used more memory because we’d allocate two function objects instead of one for arrow expressions.  
In [bug 989204][bug1] I changed this so that we treat arrow functions exactly like normal function expressions, except that we also store the lexical this-value in an extended function slot. Then, whenever this is used inside the arrow function, we get it from the function’s extended slot. This means that arrow functions behave a lot more like normal functions now. For instance, the JITs will optimize calls to them and they can be inlined.
2. **Ion compilation**: IonMonkey could not compile scripts containing arrow functions. I fixed this in [bug 988993][bug2].

With these changes, arrow functions are about as fast as normal functions. I verified this with the following micro-benchmark:

```js
function test(arr) {
    var t = new Date;
    arr.reduce((prev, cur) => prev + cur);
    alert(new Date - t);
}
var arr = [];
for (var i=0; i<10000000; i++) {
    arr.push(3);
}
test(arr);
```

I compared a nightly build from April 1st to today’s nightly and got the following results:
![](/img/arrow-function-speedup.png)

We’re 64x faster because Ion is now able to inline the arrow function directly without going through relatively slow bound function code on every call.

Other browsers don’t support arrow functions yet, so they are not used a lot on the web, but it’s important to offer good performance for new features if we want people to start using them. Also, Firefox frontend developers love arrow functions (grepping for “=>” in browser/ shows hundreds of them) so these changes should also help the browser itself :)

[arrowdocs]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Functions/Arrow_functions#Lexical_this
[bug1]: https://bugzilla.mozilla.org/show_bug.cgi?id=989204
[bug2]: https://bugzilla.mozilla.org/show_bug.cgi?id=988993
