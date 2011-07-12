
module Sinatra::ZeitgeistRemote
  class Plugins::Imgur < Plugin
    TYPE = 'image'
    PATTERN = %r{http://imgur\.com/(gallery/)?[^/]+/?}

    def url
      search_one 'link[@rel="image_src"]/@href' 
    end

    def title
      search_one '.panel h2[1]/text()'
    end
  end
end

