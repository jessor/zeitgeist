
class Twitpic < Plugin
  TYPE = 'image'
  PATTERN = 'twitpic.com' #  %r{http://twitpic\.com/[^/]+/?(full/?)?}

  def orig_url
    if not @orig_url.rindex '/full'
      @orig_url.gsub!(%r{(/?)$}, '/full')
    end
    super
  end

  def url
    search_one 'img[3]/@src' 
  end
end

