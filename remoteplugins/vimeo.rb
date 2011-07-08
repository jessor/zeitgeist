
module Sinatra::ZeitgeistRemote
  class Plugins::Vimeo < Plugin
    TYPE = 'video'
    PATTERN = %r{http[s]?://(www\.)?vimeo\.com/}

    def filename
      return self.title.gsub(/[^a-zA-Z0-9_\-\.]/, '')
    end

    def url # return url to preview image
      results = match /thumbs: {\d+: '([^']+)'/im
      puts "def url: results: #{results.inspect}"
      if results 
        return results[0]
      else
        nil
      end
    end

    def title
      og_search 'title'
    end
  end
end

