
class Youtube < Plugin
  TYPE = 'video'
  PATTERN = %r{http[s]?://(www\.)?youtube\.com/watch}

  def filename
    return self.title.gsub(/[^a-zA-Z0-9_\-\.]/, '')
  end

  def url # return url to preview image
    preview_url = og_search 'image'
    if preview_url.include? 'ytimg.com'
      preview_url.gsub(/default\.jpg/, 'hqdefault.jpg')
    else
      nil
    end
  end

  def title
    search_one 'meta[@name="title"]/@content'
  end

  def tags
    search '#eow-tags li a/text()'
  end

  def only_existing_tags
    true
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
    id = match_one /'VIDEO_ID': "([^"]+)",/
    if not id
      id = @orig_url.match(/v=([^&]+)/)[1]
    end
    return id
  end
end

