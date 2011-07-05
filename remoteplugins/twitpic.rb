
module RemotePlugins 

  class Twitpic < RemotePlugin
    PATTERN = %r{http://twitpic\.com/[^/]+/?(full/?)?}

    def initialize(url)
      if not url.rindex '/full'
        url.gsub!(%r{(/?)$}, '/full')
      end
      super(url)
    end

    def img_url
      search 'img[3]/@src' 
    end
  end

end

