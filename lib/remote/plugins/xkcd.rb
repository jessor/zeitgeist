class Xkcd < Plugin
  TYPE = 'image'
  PATTERN = %r{xkcd\.(com|org)/\d*}
  def url
    search_one '/html/body/div/div[2]/div/div[2]/div/div/img/@src'
  end
  def title
    search_one '.s h1/text()'
  end
end
