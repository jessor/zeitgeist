
class Instagram < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www\.)?instagram\.com/[^/]*p/.+}

  def url
    og_search 'image'
  end

  def title
    def clean(str)
      str = str.gsub(/^([^#]*)#.*$/, '\\1')
        .gsub(/^\W+/,'')
        .gsub(/\W+$/,'').strip if str
      str if str and not str.empty?
    end

    title = clean(og_search 'title')
    description = clean(og_search 'description')
    description or title
  end
end

