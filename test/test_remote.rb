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
module Remote

# properties of the /test/test_42x42.png file
TEST_IMG_MIME = 'image/png'
TEST_IMG_SIZE = 568
TEST_IMG_HASH = '40a0e920a34f218c17981d296b9ecc3e'

class TestRemotePlugins < Test::Unit::TestCase
  include Plugins

  def app
    Sinatra::Application
  end

  def test_url_patterns
    {
      'Plugin'     => ['http://example.com/a/generic/url.jpg'],
      'Abload'     => ['http://www.abload.de/image.php?img=test_42x42nupq.png'],
      'Flickr'     => ['http://www.flickr.com/photos/kintel/5693336211/'],
      'Fukung'     => ['http://fukung.net/v/6873/catparrot.jpg'],
      'Imagenetz'  => ['http://www.imagenetz.de/f7a20f74f/test_42x42.png.html'],
      'Imageshack' => ['http://imageshack.us/photo/my-images/20/test42x42.png/'],
      'Imgur'      => ['http://imgur.com/vXUwn'],
      'Picpaste'   => ['http://picpaste.com/test_42x42.png'],
      'Soundcloud' => ['http://soundcloud.com/flux-pavilion/flux-pavilion-the-story-of-shadrok/'],
      'Twitpic'    => ['http://twitpic.com/5lg4ai'],
      'Vimeo'      => ['http://vimeo.com/26134306'],
      'Yfrog'      => ['http://yfrog.com/gywkzgj'],
      'Youtube'    => ['http://www.youtube.com/watch?v=PXRX47L_3yE&feature=feedbul'],
      'Xkcd'       => ['http://xkcd.com/364/'],

      'NilClass'   => ['this.is.not.a.url!']
    }.each_pair do |plugin, urls|
      urls.each do |url|
        loaded = Loader::create url
        assert(loaded.class.to_s.include?(plugin),
          "expected selected plugin (#{plugin.class}) for url: #{url}")
      end
    end
  end

  def test_abload
    plugin = Loader::create 'http://www.abload.de/image.php?img=test_42x42nupq.png'
    assert_match(plugin.url, %r{abload\.de/img/test_42x42nupq\.png})

    test_remote_file plugin.url
  end

  def test_flickr
    plugin = Loader::create 'http://www.flickr.com/photos/dcdead/6072830085/?f=hp'
    assert_match(plugin.url, /staticflickr\.com/)
    assert_equal(plugin.title, 'Path To Light')
  end

  def test_fukung
    plugin = Loader::create 'http://fukung.net/v/6873/catparrot.jpg'
    assert_equal(plugin.url, 'http://media.fukung.net/images/6873/catparrot.jpg')
    assert_equal(plugin.tags, ["thegame", "animals", "tbag8uk"])
  end  

  def test_imagenetz
    plugin = Loader::create 'http://www.imagenetz.de/f7a20f74f/test_42x42.png.html'
    assert_match(plugin.url, %r{imagenetz\.de/img\.php\?file=})

    test_remote_file plugin.url
  end

  def test_imageshack
    plugin = Loader::create 'http://imageshack.us/photo/my-images/20/test42x42.png/'
    assert_match(plugin.url, %r{imageshack\.us/[^/]+/[^/]+/test42x42\.png})

    test_remote_file plugin.url
  end

  def test_imgur
    plugin = Loader::create 'http://imgur.com/vXUwn'
    assert_equal(plugin.url, 'http://i.imgur.com/vXUwn.png')
  end

=begin they delete images after a few weeks anyway
  def test_picpaste
    plugin = Loader::create 'http://picpaste.com/test_42x42.png'
    assert_match(plugin.url, %r{http://picpaste.com/pics/test_42x42.\d+.png})
  end  
=end

  def test_soundcloud
    plugin = Loader::create 'http://soundcloud.com/flux-pavilion/flux-pavilion-the-story-of-shadrok/'
    assert_equal(plugin.title, "Flux Pavilion - The Story Of Shadrok")
    assert_match(plugin.embed, %r{<object height="81"})
    plugin = Loader::create 'http://soundcloud.com/shlohmo/shell-of-light-shlohmo-remix'
    assert(plugin.tags.include?("remix"), 
          "tags not scraped correctly? #{plugin.tags.inspect}")
  end

  def test_soupasset
    plugin = Loader::create 'http://a.asset.soup.io/asset/2353/1306_3150_20.png'
    assert_equal(plugin.url, 'http://a.asset.soup.io/asset/2353/1306_3150.png')

    test_remote_file plugin.url
  end

  def test_twitpic
    plugin = Loader::create 'http://twitpic.com/5lg4ai'
    # assert_match(%r{^http://s3\.amazonaws\.com/twitpic/photos/full/}, plugin.url)
    plugin = Loader::create 'http://twitpic.com/5lg4ai/full'
    # assert_match(%r{^http://s3\.amazonaws\.com/twitpic/photos/full/}, plugin.url)
    # (deactivated for now, the url is unpredictable)

    test_remote_file plugin.url
  end

  def test_vimeo
    plugin = Loader::create 'http://vimeo.com/26134306'
    assert_equal(plugin.title, "Eclectic Method - The Dark Side")
    assert_match(plugin.embed, %r{<iframe src="http://player.vimeo.com})
    assert(plugin.tags.include?("star wars"), 
          "tags not scraped correctly? #{plugin.tags.inspect}")
  end

  def test_xkcd
    plugin = Loader::create 'http://xkcd.com/420/'
    assert_equal(plugin.url, 'http://imgs.xkcd.com/comics/jealousy.png')
    assert_equal(plugin.title, 'Jealousy')
  end

  def test_yfrog
    plugin = Loader::create 'http://yfrog.com/gywkzgj'
    assert_match(plugin.url, %r{yfrog\.com/img\d+/\d+/})
  end

  def test_youtube
    plugin = Loader::create 'http://www.youtube.com/watch?v=PXRX47L_3yE&feature=feedbul'
    assert_equal(plugin.title, "Medal of Honor Cat")
    assert_match(plugin.embed, %r{embed/PXRX47L_3yE})
    assert(plugin.tags.include?("freddiyw"), 
          "tags not scraped correctly? #{plugin.tags.inspect}")
  end

  private

  # this tests the remote plugins (that parses the direct links) by
  # downloading the test urls and check them against the test_42x42.png file
  def test_remote_file(url)
    remote = Downloader.new url
    remote.download!
    assert_equal(TEST_IMG_MIME, remote.mimetype)
    assert_equal(TEST_IMG_SIZE, remote.filesize)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, TEST_IMG_HASH)
  end
end

class TestRemoteImage < Test::Unit::TestCase
  def app
    Sinatra::Application
  end

  def test_remote_downloader_generic
    # using the default plugin
    plugin = Plugins::Loader::create 'http://apoc.cc/test_42x42.png'
    remote = Downloader.new plugin.url
    remote.download!
    puts remote.tempfile
    assert_equal(TEST_IMG_MIME, remote.mimetype)
    assert_equal(TEST_IMG_SIZE, remote.filesize)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, TEST_IMG_HASH)
  end

  def test_remote_downloader_errors
    # test error handling:
    # not an image
    plugin = Plugins::Loader::create 'http://apoc.cc/'
    remote = Downloader.new plugin.url
    assert_raise(RemoteException) do
      remote.download!
    end
    # 404:
    remote = Downloader.new('http://apoc.cc/this_never_exists')
    assert_raise(RemoteException) do
      remote.download!
    end
  end
end

end # end namespace Remote
end # end namespace Sinatra

