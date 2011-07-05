
module Sinatra::ZeitgeistRemote
  class Plugins::Imgur < Plugin
    PATTERN = %r{http://imgur\.com/(gallery/)?[^/]+/?}

    def url
      # <link rel="image_src" href="http://i.imgur.com/KkB15.png" />
      search 'link[@rel="image_src"]/@href' 
    end

    def title
      search '.panel h2[1]/text()'
    end
  end
end

