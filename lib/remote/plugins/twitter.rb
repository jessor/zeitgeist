
class Twitter < Plugin
  TYPE = 'image'
  PATTERN = %r{http[s]?://(www)?twitter\.com/.*status/\d+}

  def url
    @orig_url.match %r{status/(\d+)}
    id = $1
    @item = json('http://api.twitter.com/1/statuses/show.json?include_entities=true&contributor_details=true&id=%d' % id)

    media = @item['entities']['media'].first
    if media['type'] == 'photo'
      media['media_url']
    else
      nil
    end
  end

  def title
    @item['text']
  end
end

