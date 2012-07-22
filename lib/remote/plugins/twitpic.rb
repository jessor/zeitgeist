
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
    search_one '#media-full img/@src' 
  end

  def title
    og_search 'title'
  end
end

