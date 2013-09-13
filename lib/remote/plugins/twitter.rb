
class Twitter < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www)?twitter\.com/.*status/\d+}

  def url
    image = search_one('.media-slideshow-image/@src').to_s
    image = search_one('.media-thumbnail/@data-url').to_s if not image or image.empty?
    image
  end

  def title
    search_one('p.tweet-text').content
  end
end

