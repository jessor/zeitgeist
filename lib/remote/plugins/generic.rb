
# simple generic plugin, used for html/text links
#   (not used normally)

class Generic < Plugin
  TYPE = 'link'
  PATTERN = nil

  def title
    search_one 'head/title/text()' 
  end
end

