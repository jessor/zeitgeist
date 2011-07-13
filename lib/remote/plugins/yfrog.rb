
module Sinatra::ZeitgeistRemote
  class Plugins::Yfrog < Plugin
    TYPE = 'image'
    PATTERN = %r{http[s]?://(www\.)?yfrog\.com/}

    def url
      og_search 'image'
    end
  end
end

