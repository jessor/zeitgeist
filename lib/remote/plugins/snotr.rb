
class Snotr < Plugin
  TYPE = 'video'
  PATTERN = %r{http[s]?://(www\.)?(snotr\.com/video/\d+)}

  def filename
    return self.title.gsub(/[^a-zA-Z0-9_\-\.]/, '')
  end

  def url # return url to preview image
    search_one('link[@rel="image_src"]/@href') || super
  end

  def title
    og_search 'title'
  end

  def embed(width=400, height=330)
    <<snotr
    <iframe src="http://www.snotr.com/embed/#{video_id}"
      width="#{width}" height="#{height}" frameborder="0"></iframe>
snotr
  end

  private

  def video_id
    @orig_url.match %r{video/(\d+)}
    return $1
  end
end

