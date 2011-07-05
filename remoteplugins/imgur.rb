
module RemotePlugins 

  class Imgur < RemotePlugin
    PATTERN = %r{http://imgur\.com/(gallery/)?[^/]+/?}

    def img_url
      # <link rel="image_src" href="http://i.imgur.com/KkB15.png" />
      return search 'link[@rel="image_src"]/@href' 
    end

    def title
      return search '.panel h2[1]/text()'
    end
  end

end

