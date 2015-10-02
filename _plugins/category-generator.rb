module Jekyll

  class CategoryPage < Page
    def initialize(site, base, dir, category)
      @site = site
      @base = base
      @dir = dir
      @name = 'index.html'

      self.process(@name)
      self.read_yaml(File.join(base, '_layouts'), 'category.html')
      self.data['category'] = category
      self.data['title'] = "Category: #{category}"
    end
  end

  class CategoryFeedPage < Page
    def initialize(site, base, dir, category)
      @site = site
      @base = base
      @dir = dir
      @name = 'feed.xml'

      self.process(@name)
      self.read_yaml(File.join(base, '_layouts'), 'category-feed.html')
      self.data['category'] = category
      self.data['title'] = "Category: #{category}"
    end
  end

  class CategoryPageGenerator < Generator
    safe true

    def generate(site)
      dir = File.join('blog', 'category')
      site.categories.each_key do |category|
        catdir = File.join(dir, category)
        site.pages << CategoryPage.new(site, site.source, catdir, category)
        site.pages << CategoryFeedPage.new(site, site.source, catdir, category)
      end
    end
  end

end
