
class Imagenetz < Plugin
  TYPE = 'image'
  PATTERN = %r{http://www\.imagenetz\.de/[^/]+/.*}

  def url
    search_one '#picture/@src'
  end
end

