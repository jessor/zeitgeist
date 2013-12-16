
class SoupAsset < Plugin
  TYPE = 'image'
  PATTERN = %r{asset[^\.]+\.soup\.io/asset/}

  def url # remove the image width (thumbnail) from the url
    if @orig_url.match /\/[^_]+_[^_]+(_[0-9]+)\.(gif|png|jpeg|jpg)$/
      @orig_url.slice! $1
    end
    @orig_url
  end
end

