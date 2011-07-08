
module Sinatra::ZeitgeistRemote
  class Plugins::Youtube < Plugin
    TYPE = 'video'
    PATTERN = %r{http[s]?://(www\.)?youtube\.com/watch}

    def filename
      return self.title.gsub(/[^a-zA-Z0-9_\-\.]/, '')
    end

    def url # return url to preview image
      preview_url = search 'meta[@property="og:image"]/@content'
      if preview_url.include? 'ytimg.com'
        preview_url.gsub(/default\.jpg/, 'hqdefault.jpg')
      else
        nil
      end
    end

    def title
      search 'meta[@name="title"]/@content'
    end
  end
end

