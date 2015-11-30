---
layout: post
title:  "Testing Math.random(): Crushing the browser"
date:   "2015-11-30 22:25:00"
categories: mozilla
---
(For **tl;dr**, see the Conclusion.)

A few days ago, [I wrote about](/blog/2015/11/27/math-random-and-32-bit-precision/) Math.random() implementations in Safari and (older versions of) Chrome using only 32 bits of precision. As I mentioned in that blog post, I've been [working on](https://bugzilla.mozilla.org/show_bug.cgi?id=322529) upgrading Math.random() in SpiderMonkey to XorShift128+. V8 has been using the same algorithm since last week.

The most extensive RNG test is [TestU01](http://simul.iro.umontreal.ca/testu01/tu01.html). It's a bit of a pain to run: to test a custom RNG, you have to compile the library and then link it to a test program. I did this initially for the SpiderMonkey shell but after that I thought it'd be more interesting to use [Emscripten](http://emscripten.org/) to compile TestU01 to asm.js so we can easily run it in different browsers.

Today I [tried this](https://github.com/jandem/TestU01.js) and even though I had never used Emscripten before, I had it running in the browser in less than an hour. Because the tests can take a long time, it runs in a web worker. You can [try it for yourself here](https://jandem.github.io/TestU01.js/test.htm).

I also wanted to test [window.crypto.getRandomValues()](https://developer.mozilla.org/nl/docs/Web/API/window.crypto.getRandomValues) but unfortunately it's not available [in workers](https://bugzilla.mozilla.org/show_bug.cgi?id=842818).

Disclaimer: browsers implement Math functions like Math.sin differently and this can affect their precision. I don't know if TestU01 uses these functions and whether it affects the results below, but it's possible. Furthermore, some test failures are intermittent so results can vary between runs.

## Results
TestU01 has three *batteries* of tests: SmallCrush, Crush, and BigCrush. SmallCrush runs only a few tests and is very fast. Crush and especially BigCrush have a lot more tests so they are much slower.

### SmallCrush

Running SmallCrush takes about 15-30 seconds. It runs 10 tests with 15 statistics (results). Here are the number of failures I got:

|Browser | Number of failures
|-------------| -------------
| Firefox Nightly | 1: BirthdaySpacings |
| Firefox with XorShift128+ | 0 |
| Chrome 48 | 11 |
| Safari 9 | 1: RandomWalk1 H |
| Internet Explorer 11 | 1: BirthdaySpacings |
| Edge 20 | 1: BirthdaySpacings |

Chrome/V8 failing 11 out of 15 is [not too surprising](https://medium.com/@betable/tifu-by-using-math-random-f1c308c4fd9d). Again, the V8 team fixed this last week and the new RNG should pass SmallCrush.

#### Crush
The Crush battery of tests is much more time consuming. On my MacBook Pro, it finishes in less than an hour in Firefox but in Chrome and Safari it can take at least 2 hours. It runs 96 tests with 144 statistics. Here are the results I got:

|Browser | Number of failures
|-------------| -------------
| Firefox Nightly | 12 |
| Firefox with XorShift128+ | 0
| Chrome 48 | 108 |
| Safari 9 | 33 |
| Internet Explorer 11 | 14 |

XorShift128+ passes Crush, as expected. V8's previous RNG fails most of these tests and Safari/WebKit isn't doing too great either.

### BigCrush
BigCrush didn't finish in the browser because it requires more than 512 MB of memory. To fix that I probably need to recompile the asm.js code with a different TOTAL\_MEMORY value or with ALLOW\_MEMORY\_GROWTH=1.

Furthermore, running BigCrush would likely take at least 3 hours in Firefox and more than 6-8 hours in Safari, Chrome, and IE, so I didn't bother.

The XorShift128+ algorithm being implemented in Firefox and Chrome should pass BigCrush (for Firefox, I [verified this](https://bugzilla.mozilla.org/show_bug.cgi?id=322529#c101) in the SpiderMonkey shell).

## About IE and Edge

I noticed Firefox (without XorShift128+) and Internet Explorer 11 get **very** similar test failures. When running SmallCrush, they both fail the same BirthdaySpacings test. Here's the list of Crush failures they have in common:

* 11  BirthdaySpacings, t = 2
* 12  BirthdaySpacings, t = 3  
* 13  BirthdaySpacings, t = 4  
* 14  BirthdaySpacings, t = 7  
* 15  BirthdaySpacings, t = 7  
* 16  BirthdaySpacings, t = 8  
* 17  BirthdaySpacings, t = 8  
* 19  ClosePairs mNP2S, t = 3
* 20  ClosePairs mNP2S, t = 7
* 38  Permutation, r = 15
* 40  CollisionPermut, r = 15
* 54  WeightDistrib, r = 24  
* 75  Fourier3, r = 20

This suggests the RNG in IE may be very similar to the one we used in Firefox (imported from Java decades ago). Maybe Microsoft imported the same algorithm from somewhere? If anyone on the Chakra team is reading this and can tell us more, it would be much appreciated :)

IE 11 fails 2 more tests that pass in Firefox. Some failures are intermittent and I'd have to rerun the tests to see if these failures are systematic.

Based on the SmallCrush results I got with Edge 20, I think it uses the same algorithm as IE 11 (not too surprising). Unfortunately the Windows VM I downloaded to test Edge shut down for some reason when it was running Crush so I gave up and don't have full results for it.

### Conclusion
I used Emscripten to port TestU01 [to the browser](https://jandem.github.io/TestU01.js/test.htm). Results confirm most browsers currently don't use very strong RNGs for Math.random(). Both Firefox and Chrome are implementing XorShift128+, which has no systematic failures on any of these tests.

Furthermore, these results indicate IE and Edge **may** use the same algorithm as the one we used in Firefox.


