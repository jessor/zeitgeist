
class Imgur < Plugin
  TYPE = 'image'
  PATTERN = %r{http://imgur\.com/(gallery/)?[^/]+/?}

  def url
    search_one('link[@rel="image_src"]/@href') || super
  end

  def title
    search_one('.panel h2[1]/text()') || super
  end
end

