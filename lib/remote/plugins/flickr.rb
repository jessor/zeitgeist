
class Flickr < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?flickr\.com/photos/}

  def url
    match_one /o: {\s+url: '([^']+)'/
  end

  def title
    search_one('h1.photo-title/text()') || super
  end
end

