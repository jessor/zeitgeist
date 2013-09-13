
class Twitter < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www)?twitter\.com/.*status/\d+}

  def url
    search_one('.media-slideshow-image/@src')
  end

  def title
    search_one('p.tweet-text').map(&:content)
  end
end

