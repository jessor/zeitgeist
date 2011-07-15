
class Imageshack < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?imageshack\.us/photo/}

  def url
    search_one 'link[@rel="image_src"]/@href' 
  end
end

