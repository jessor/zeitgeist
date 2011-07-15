class Xkcd < Plugin
  TYPE = 'image'
  PATTERN = %r{xkcd\.com/\d*}
  def url
    search_one '/html/body/div/div[2]/div/div[2]/div/div/img/@src'
    # search_one '.s img/@src'
    # href_match %r{http://imgs\.xkcd\.com/}
  end
  def title
    search_one '.s h1/text()'
  end
end
