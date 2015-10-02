---
layout: post
title:  "Using Rust to generate Mercurial short-hash collisions"
date:   2015-05-05
categories: mozilla rust
disqus_identifier: "156 http://www.jandemooij.nl/blog/?p=156"
---
At Mozilla, we use [Mercurial](https://www.mercurial-scm.org/) for the main Firefox repository. Mercurial, like Git, uses [SHA1](http://en.wikipedia.org/wiki/SHA-1) hashes to identify a commit.

### Short hashes
SHA1 hashes are fairly long, a string of 40 hex characters (160 bits), so Mercurial and Git allow using a prefix of that, as long as the prefix is unambiguous. Mercurial also typically only shows the first 12 characters (let’s call them *short hashes*), for instance:

{% highlight bash %}
$ hg id
34828fed1639
$ hg log -r tip
changeset:   242221:312707328997
tag:         tip
...
{% endhighlight %}

And those are the hashes most Mercurial users use, for instance they are posted [in Bugzilla](https://bugzilla.mozilla.org/show_bug.cgi?id=1031529#c16) whenever we land a patch etc.

Collisions with short hashes are much more likely than full SHA1 collisions, because the short hashes are only 48 bits long. As the [Mercurial FAQ](https://www.mercurial-scm.org/wiki/FAQ#FAQ.2FTechnicalDetails.What_about_hash_collisions.3F_What_about_weaknesses_in_SHA1.3F) states, such collisions don’t really matter, because Mercurial will check if the hash is unambiguous and if it’s not it will require more than 12 characters.

So, short hash collisions are not the end of the world, but they are inconvenient because the standard 12-chars hg commit ids will become ambiguous and unusable. Fortunately, the [mozilla-central repository](https://hg.mozilla.org/mozilla-central/) at this point does not contain any short hash collisions (it has about 242,000 commits).

### Finding short-hash collisions
I’ve wondered for a while, can we create a commit that has the same short hash as another commit in the repository?

A brute force attack that works by committing and then reverting changes to the repository should work, but it’d be super slow. I haven’t tried it, but it’d probably take years to find a collision. Fortunately, there’s a much faster way to brute force this. Mercurial computes the commit id/hash [like this](https://www.mercurial-scm.org/wiki/Nodeid):

{% highlight python %}
hash = sha1(min(p1, p2) + max(p1, p2) + contents)
{% endhighlight %}
Here p1 and p2 are the hashes of the parent commits, or a null hash (all zeroes) if there’s only one parent. To see what *contents* is, we can use the *hg debugdata* command:

{% highlight bash %}
$ hg debugdata -c 34828fed1639
40c6a58ef0be7591e6b0d48b36a8e1f88486b0ee
Carsten "Tomcat" Book <cbook@mozilla.com>
1430739274 -7200
extensions/spellcheck/locales/en-US/hunspell/dictionary-sources/chromium_en_US.dic_delta
...list of changed files...

merge mozilla-inbound to mozilla-central a=merge
{% endhighlight %}
Perfect! This contains the commit message, so all we have to do is append some random data to the commit message, compute the (short) hash, check if there’s a collision and repeat until we find a match.

I wrote a small [Rust program](https://github.com/jandem/hgcollision) to brute-force this. You can use it like this (I used the popular [mq extension](https://www.mercurial-scm.org/wiki/MqExtension), there are other ways to do it):

{% highlight bash %}
$ cd mozilla-central
$ echo "Foo" >> CLOBBER # make a random change
$ hg qnew patch -m "Some message"
$ hgcollision
...snip...
Got 242223 prefixes
Generated random prefix: 1631965792_
Tried 242483200 hashes
Found collision! Prefix: b991f0726738, hash: b991f072673876a64c7a36f920b2ad2885a84fac
Add this to the end of your commit message: 1631965792_24262171
{% endhighlight %}

After about 2 minutes it’s done and tells us we have to append “1631965792_24262171” to our commit message to get a collision! Let’s try it (we have to be careful to preserve the original date/time, or we’ll get a different hash):

{% highlight bash %}
$ hg log -r tip --template "{date|isodatesec}"
2015-05-05 20:21:59 +0200
$ hg qref -m "Some message1631965792_24262171" -d "2015-05-05 20:21:59 +0200"
$ hg id
b991f0726738 patch/qbase/qtip/tip
$ hg log -r b991f0726738
abort: 00changelog.i@b991f0726738: ambiguous identifier!
{% endhighlight %}

Voilà! We successfully created a Mercurial short hash collision!

And no, I didn’t use this on any patches I pushed to mozilla-central..

### Rust
The Rust source code is available [here](https://github.com/jandem/hgcollision). It was my first, quick-and-dirty Rust program but writing it was a nice way to get more familiar with the language. I used the rust-crypto crate to calculate SHA1 hashes, installing and using it was much easier than I expected. Pretty nice experience.

The program can check about 100 million hashes in one minute on my laptop. It usually takes about 1-5 minutes to find a collision, this also depends on the size of the repository (mozilla-central has about 242,000 commits). It’d be easy to use multiple threads (you can also just use X processes though) and there are probably a lot of other ways to improve it. For this experiment it was good and fast enough to get the job done :)