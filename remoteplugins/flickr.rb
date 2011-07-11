
module Sinatra::ZeitgeistRemote
  class Plugins::Flickr < Plugin
    TYPE = 'image'
    PATTERN = %r{http[s]?://(www\.)?flickr\.com/photos/}

    def url
      search_one '.photo-div/img/@src' 
    end

    def title
      search_one 'h1.photo-title/text()'
    end
  end
end

