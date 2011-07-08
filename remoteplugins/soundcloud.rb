
module Sinatra::ZeitgeistRemote
  class Plugins::Soundcloud < Plugin
    TYPE = 'audio'
    PATTERN = %r{^http[s]?://soundcloud\.com/[\S]+/[\S]+}

    def url
      nil # prevent downloading (there is no preview image)
    end

    def title
      og_search 'title'
    end

    def oembed
      OEmbed::Provider.new('http://soundcloud.com/oembed').get(@orig_url)
    end
  end
end

