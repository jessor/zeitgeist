
class Flickr < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?flickr\.com/photos/}

  def url
    search_one('.photo-div/img/@src, #allsizes-photo/img/@src') || super
  end

  def title
    search_one('h1.photo-title/text()') || super
  end
end

