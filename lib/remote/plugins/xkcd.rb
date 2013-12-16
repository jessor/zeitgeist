class Xkcd < Plugin
  TYPE = 'image'
  PATTERN = %r{xkcd\.(com|org)/\d*}
  def url
    search_one('#comic/img/@src') || super
  end
  def title
    ctitle = search_one('#ctitle/text()')
    alt = search_one('#comic/img/@title')
    if ctitle and alt
      ctitle+': '+alt
    else
      super
    end
  end
end
