
class Fukung < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?fukung\.net/}

  def url
    search_one('link[@rel="image_src"]/@href') || super 
  end

  def tags
    search('#taglist a/text()') || super
  end
end

