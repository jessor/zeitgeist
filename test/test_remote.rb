if Dir.pwd == File.dirname(File.expand_path(__FILE__))
  Dir.chdir '..'
end
require 'test/unit'
require 'rack/test'
require 'digest/md5' 
require './zeitgeist.rb'
require './lib/remote/remote.rb'

ENV['RACK_ENV'] = 'test'

module Sinatra
module ZeitgeistRemote

class TestRemotePlugins < Test::Unit::TestCase
  include Plugins

  def app
    Sinatra::Application
  end

  def test_url_patterns
    {
      NilClass   => ['this.is.not.a.url!'],
      Plugin     => ['http://example.com/a/generic/url.jpg'],
      Flickr     => ['http://www.flickr.com/photos/kintel/5693336211/'],
      Fukung     => ['http://fukung.net/v/6873/catparrot.jpg'],
      Imageshack => ['http://imageshack.us/photo/my-images/20/test42x42.png/'],
      Imgur      => ['http://imgur.com/vXUwn'],
      Soundcloud => ['http://soundcloud.com/flux-pavilion/flux-pavilion-the-story-of-shadrok/'],
      Twitpic    => ['http://twitpic.com/5lg4ai'],
      Vimeo      => ['http://vimeo.com/26134306'],
      Yfrog      => ['http://yfrog.com/gywkzgj'],
      Youtube    => ['http://www.youtube.com/watch?v=PXRX47L_3yE&feature=feedbul']
    }.each_pair do |plugin, urls|
      urls.each do |url|
        assert_equal(
          plugin, 
          Plugins::plugin_by_url(url).class, 
          "expect plugin (#{plugin.class}) for url: #{url}")
      end
    end
  end

  def test_imgur
    plugin = Imgur.new 'http://imgur.com/vXUwn'
    assert_equal(plugin.url, 'http://i.imgur.com/vXUwn.png')
  end

  def test_twitpic
    plugin = Twitpic.new 'http://twitpic.com/5lg4ai'
    assert_match(%r{^http://s3\.amazonaws\.com/twitpic/photos/full/}, plugin.url)
    plugin = Twitpic.new 'http://twitpic.com/5lg4ai/full'
    assert_match(%r{^http://s3\.amazonaws\.com/twitpic/photos/full/}, plugin.url)
  end

  def test_flickr
    plugin = Flickr.new 'http://www.flickr.com/photos/kintel/5693336211/'
    assert_match(plugin.url, /static\.flickr\.com/)
    assert_equal(plugin.title, 'New neck piece')
  end

  def test_fukung
    plugin = Fukung.new 'http://fukung.net/v/6873/catparrot.jpg'
    assert_equal(plugin.url, 'http://media.fukung.net/images/6873/catparrot.jpg')
    assert_equal(plugin.tags, ["thegame", "animals", "tbag8uk"])
  end  

  def test_picpaste
    plugin = Picpaste.new 'http://picpaste.com/test_42x42.png'
    assert_match(plugin.url, %r{http://picpaste.com/pics/test_42x42.\d+.png})
  end  

  def test_imageshack
    plugin = Imageshack.new 'http://imageshack.us/photo/my-images/20/test42x42.png/'
    assert_match(plugin.url, %r{imageshack\.us/[^/]+/[^/]+/test42x42\.png})
  end

  def test_yfrog
    plugin = Yfrog.new 'http://yfrog.com/gywkzgj'
    assert_match(plugin.url, %r{yfrog\.com/img\d+/\d+/})
  end

  def test_youtube
    plugin = Youtube.new 'http://www.youtube.com/watch?v=PXRX47L_3yE&feature=feedbul'
    assert_equal(plugin.title, "Medal of Honor Cat")
    assert_match(plugin.embed, %r{embed/PXRX47L_3yE})
    assert(plugin.tags.include?("freddiyw"), 
          "tags not scraped correctly? #{plugin.tags.inspect}")
  end
    
  def test_vimeo
    plugin = Vimeo.new 'http://vimeo.com/26134306'
    assert_equal(plugin.title, "Eclectic Method - The Dark Side")
    assert_match(plugin.embed, %r{<iframe src="http://player.vimeo.com})
    assert(plugin.tags.include?("star wars"), 
          "tags not scraped correctly? #{plugin.tags.inspect}")
  end

  def test_soundcloud
    plugin = Soundcloud.new 'http://soundcloud.com/flux-pavilion/flux-pavilion-the-story-of-shadrok/'
    assert_equal(plugin.title, "Flux Pavilion - The Story Of Shadrok")
    assert_match(plugin.embed, %r{<object height="81"})
    plugin = Soundcloud.new 'http://soundcloud.com/shlohmo/shell-of-light-shlohmo-remix'
    assert(plugin.tags.include?("remix"), 
          "tags not scraped correctly? #{plugin.tags.inspect}")
    
  end
end

class TestRemoteImage < Test::Unit::TestCase
  def app
    Sinatra::Application
  end

  def test_remote_downloader_twitpic
    # using twitpic plugin
    plugin = Plugins::plugin_by_url 'http://twitpic.com/5lg4ai'
    remote = RemoteDownloader.new plugin
    remote.download!
    puts remote.tempfile
    assert_equal('image/png', remote.mimetype)
    assert_equal(568, remote.filesize)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')
  end

  def test_remote_downloader_imgur
    # using imgur plugin
    plugin = Plugins::plugin_by_url 'http://imgur.com/qbJ52'
    remote = RemoteDownloader.new plugin
    remote.download!
    puts remote.tempfile
    assert_equal('image/png', remote.mimetype)
    assert_equal(568, remote.filesize)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')
  end

  def test_remote_downloader_generic
    # using the default plugin
    plugin = Plugins::plugin_by_url 'http://apoc.cc/test_42x42.png'
    remote = RemoteDownloader.new plugin
    remote.download!
    puts remote.tempfile
    assert_equal('image/png', remote.mimetype)
    assert_equal(568, remote.filesize)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')
  end

  def test_remote_downloader_errors
    # test error handling:
    # not an image
    plugin = Plugins::plugin_by_url 'http://apoc.cc/'
    remote = RemoteDownloader.new plugin
    assert_raise(RemoteException) do
      remote.download!
    end
    # 404:
    remote = RemoteDownloader.new('http://apoc.cc/this_never_exists')
    assert_raise(RemoteException) do
      remote.download!
    end
  end
end

end # end namespace ZeitgeistRemote
end # end namespace Sinatra

