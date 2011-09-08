
class Abload < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?abload\.de/image\.php\?img}

  def url
    search_one('#image/@src') || super
  end
end

