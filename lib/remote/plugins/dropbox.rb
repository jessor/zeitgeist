
class Dropbox < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?dropbox\.com/}

  def title
    og_search 'title'
  end

  def url
    search_one '#default_content_download_button/@href'
  end
end

