
class Imgur < Plugin
  TYPE = 'image'
  PATTERN = %r{http://imgur\.com/(gallery/)?[^/]+/?}

  def url
    search_one('link[@rel="image_src"]/@href') || super
  end

  def title
    title = search_one('*[@id="image-title"]/text()')
    if not title or title.chomp == 'Images'
      super
    else
      title
    end
  end
end

