
module Sinatra::ZeitgeistRemote
  class Plugins::Fukung < Plugin
    TYPE = 'image'
    PATTERN = %r{http[s]?://(www\.)?fukung\.net/}

    def url
      search_one 'link[@rel="image_src"]/@href' 
    end

    def tags
      search '#taglist a/text()'
    end
  end
end

