class Xkcd < Plugin
  TYPE = 'image'
  PATTERN = %r{xkcd\.com/\d+}
  def url
    search_one '.s img/@src'
  end
  def title
    search_one '.s h1/text()'
  end
end
