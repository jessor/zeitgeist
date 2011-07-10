
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

    def embed
      <<yt
      <iframe class="youtube-player" type="text/html" width="640" height="385" 
              src="http://www.youtube.com/embed/#{video_id}" 
              frameborder="0">
      </iframe>
yt
    end

    private

    def video_id
      id = match(/'VIDEO_ID': "([^"]+)",/).first
      if not id
        @orig_url.match /v=([^&]+)/
        id = $1
      end
      return id
    end
  end
end

