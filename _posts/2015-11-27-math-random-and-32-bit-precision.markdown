---
layout: post
title:  "Math.random() and 32-bit precision"
date:   "2015-11-27 21:45:00"
categories: mozilla
---
Last week, Mike Malone, CTO of [Betable](https://betable.com), wrote a very insightful and informative [article](https://medium.com/@betable/tifu-by-using-math-random-f1c308c4fd9d) on Math.random() and PRNGs in general. Mike pointed out V8/Chrome used a pretty bad algorithm to generate random numbers and, since this week, V8 uses a better algorithm.

The article also mentioned the RNG we use in Firefox (it was copied from Java a long time ago) should be improved as well. I fully agree with this. In fact, the past days I've been [working on](https://bugzilla.mozilla.org/show_bug.cgi?id=322529) upgrading Math.random() in SpiderMonkey to XorShift128+, see [bug 322529](https://bugzilla.mozilla.org/show_bug.cgi?id=322529). We think XorShift128+ is a good choice: we already had a copy of the RNG in our repository, it's fast (even faster than our current algorithm!), and it passes BigCrush (the most complete RNG test available).

While working on this, I looked at a number of different RNGs and noticed Safari/WebKit [uses GameRand](https://github.com/WebKit/webkit/blob/67985c34ffc405f69995e8a35f9c38618625c403/Source/WTF/wtf/WeakRandom.h#L104). It's extremely fast but **very** weak. (Update Dec 1: WebKit is now [also using](https://bugs.webkit.org/show_bug.cgi?id=151641) XorShift128+, so this doesn't apply to newer Safari/WebKit versions.)

Most interesting to me, though, was that, like the previous V8 RNG, it has only 32 bits of precision: it generates a 32-bit unsigned integer and then divides that by `UINT_MAX + 1`. This means the result of the RNG is always one of about 4.2 billion different numbers, instead of 9007199 billion (2^53). In other words, it can generate 0.00005% of all numbers an ideal RNG can generate.

I wrote a [small testcase](/test/random-precision.htm) to visualize this. It generates random numbers and plots all numbers smaller than 0.00000131072.

Here's the output I got in Firefox (old algorithm) after generating 115 billion numbers:

![](/img/rand-firefox-old.png)

And a Firefox build with XorShift128+:

![](/img/rand-firefox-new.png)

In Chrome (before Math.random was fixed):

![](/img/rand-chrome.png)

And in Safari:

![](/img/rand-safari.png)

These pics clearly show the difference in precision.

### Conclusion
Safari and older Chrome versions both generate random numbers with only 32 bits of precision. This issue has been fixed in Chrome, but Safari's RNG should probably be fixed as well. Even if we ignore its suboptimal precision, the algorithm is still extremely weak.

Math.random() is not a [cryptographically-secure PRNG](https://en.wikipedia.org/wiki/Cryptographically_secure_pseudorandom_number_generator) and should never be used for anything security-related, but, as Mike argued, there are a lot of much better (and still very fast) RNGs to choose from.
