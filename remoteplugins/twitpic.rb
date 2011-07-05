
module Sinatra::ZeitgeistRemote
  class Plugins::Twitpic < Plugin
    PATTERN = %r{http://twitpic\.com/[^/]+/?(full/?)?}

    def orig_url
      if not @orig_url.rindex '/full'
        @orig_url.gsub!(%r{(/?)$}, '/full')
      end
      super
    end

    def url
      search 'img[3]/@src' 
    end
  end
end

