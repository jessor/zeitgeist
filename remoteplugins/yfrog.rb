
module Sinatra::ZeitgeistRemote
  class Plugins::Yfrog < Plugin
    PATTERN = %r{http[s]?://(www\.)?yfrog\.com/}

    def url
      # <meta property="og:image" content="http://..." />
      search 'meta[@property="og:image"]/@content' 
    end
  end
end

