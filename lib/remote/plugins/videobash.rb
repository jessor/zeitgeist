
class Videobash < Plugin
  TYPE = 'image'
  PATTERN = %r{^http://(www)?\.videobash\.com/photo_show}

  def url
    search_one('#imageContent/@src') || super
  end

  def title
    search_one('#imageContent/@alt') || super
  end
end


