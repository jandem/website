---
layout: post
title:  "Bye Wordpress, hello Jekyll!"
date:   2015-10-03
categories: mozilla
---
This week I migrated this blog from Wordpress to [Jekyll](https://jekyllrb.com), a popular static site generator. This post explains why and how I did this, maybe it will be useful to someone.

### Why?
Wordpress powers thousands of websites, is regularly updated, has a ton of features. Why did I abandon it?

I still think Wordpress is great for a lot of websites and blogs, but I felt it was overkill for my simple website. It had so many features I never used and this came at a price: it was hard to understand how everything worked, it was hard to make changes and it required regular security updates.

This is what I like most about Jekyll compared to Wordpress:

* **Maintainance, security**: I don't blog often, yet I still had to update Wordpress every few weeks or months. Even though the process is pretty straight-forward, it got cumbersome after a while.
* **Setup**: Setting up a local Wordpress instance with the same content and configuration was annoying. I never bothered so the little development I did was directly on the webserver. This didn't feel very good or safe. Now I just have to install Jekyll, clone my repository and generate plain HTML files. No database to setup. No webserver to install (Jekyll comes with a little webserver, see below).
* **Transparency**: With Wordpress, the blog posts were stored somewhere in a MySQL database. With Jekyll, I have Markdown files in a Git repository. This makes it trivial to backup, view diffs, etc.
* **Customizability**: After I started using Jekyll, customizing this blog (see below) was very straight-forward. It took me less than a few hours. With Wordpress I'm sure it'd have taken longer and I'd have introduced a few security bugs in the process.
* **Performance**: The website is just some static HTML files, so it's fast. Also, when writing a blog post, I like to preview it after writing a paragraph or so. With Wordpress it was always a bit tedious to wait for the website to save the blog post and reload the page. With Jekyll, I save the markdown file in my text editor and, in the background, `jekyll serve` immediately updates the site, so I can just refresh the page in the browser. Everything runs locally.
* **Hosting**: In the future I may move this blog to GitHub Pages or another free/cheaper host.

### Why Jekyll?
I went with Jekyll because it's widely used, so there's a lot of documentation and it'll likely still be around in a year or two. Octopress is also popular but under the hood it's just Jekyll with some plugins and changes, and it seems to be updated less frequently.

### How?
I decided to use the default template and customize it where needed. I made the following changes:

* Links to previous/next post at the end of each post, see [post.html](https://github.com/jandem/website/blob/master/_layouts/post.html)
* Pagination on the homepage, based on [the docs](https://jekyllrb.com/docs/pagination/). I also changed the home page to include the contents instead of just the post title.
* [Archive page](/blog/archive/), a list of posts grouped by year, see [archive.html](https://github.com/jandem/website/blob/master/archive.html)
* Category pages. I wrote a small plugin to generate [a page](/blog/category/mozilla) + [feed](/blog/category/mozilla/feed.xml) for each category. This is based on the example in the [plugin documentation](http://jekyllrb.com/docs/plugins/#generators).
See [_plugins/category-generator.rb](https://github.com/jandem/website/blob/master/_plugins/category-generator.rb) and [_layouts/category.html](https://github.com/jandem/website/blob/master/_layouts/category.html)
* List of categories in the header of each post (with a link to the category page), see [post.html](https://github.com/jandem/website/blob/master/_layouts/post.html)
* Disqus comments and number of comments in the header of each post, based on [the docs](https://help.disqus.com/customer/portal/articles/565624-adding-comment-count-links-to-your-home-page), see [post.html](https://github.com/jandem/website/blob/master/_layouts/post.html). I was able to export the Wordpress comments to Disqus.
* In _config.yml I changed the post URL format ("permalink" option) to not include the category names. This way links to my posts still work.
* Some minor tweaks here and there.

I still want to change the code highlighting style, but that can wait for now.

### Conclusion
After using Jekyll for a few hours, I'm a big fan. It's simple, it's fun, it's powerful. If you're tired of Wordpress and Blogger, or just want to experiment with something else, I highly recommend giving it a try.