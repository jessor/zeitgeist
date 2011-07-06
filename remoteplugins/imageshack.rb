
module Sinatra::ZeitgeistRemote
  class Plugins::Imageshack < Plugin
    PATTERN = %r{http[s]?://(www\.)?imageshack\.us/photo/}

    def url
      search 'link[@rel="image_src"]/@href' 
    end
  end
end

