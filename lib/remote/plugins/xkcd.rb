class Xkcd < Plugin
  TYPE = 'image'
  PATTERN = %r{xkcd\.(com|org)/\d*}
  def url
    search_one('#comic/img/@src') || super
  end
  def title
    search_one('#ctitle/text()') || super
  end
end
