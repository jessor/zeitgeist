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
      'Imgur'      => ['http://imgur.com/vXUwn'],
      'Picpaste'   => ['http://picpaste.com/test_42x42.png'],
      'Soundcloud' => ['http://soundcloud.com/flux-pavilion/flux-pavilion-the-story-of-shadrok/'],
      'Twitpic'    => ['http://twitpic.com/8rfe1u'],
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
    assert_match(%r{abload\.de/img/test_42x42nupq\.png}, plugin.url)

    test_remote_file plugin.url
  end

  def test_flickr
    plugin = Loader::create 'http://www.flickr.com/photos/dcdead/6072830085/?f=hp'
    assert_match(/staticflickr\.com/, plugin.url)
    assert_equal('Path To Light', plugin.title)
  end

  def test_fukung
    plugin = Loader::create 'http://fukung.net/v/6873/catparrot.jpg'
    assert_equal('http://media.fukung.net/imgs/catparrot.jpg', plugin.url)
    assert(plugin.tags.length > 0)
  end  

  def test_twitter
    [
      'https://twitter.com/derPUPE/status/216162269489401856/photo/1',
      'https://twitter.com/abitofcode/status/219950547212578817/photo/1/large',
      'https://twitter.com/G33KatWork/status/222906687642800128/photo/1',
      'https://twitter.com/bpwned/status/223084380632006656/photo/1/large',
      'https://twitter.com/mdaoudi/status/223159077302312960/photo/1/large',
      'https://twitter.com/gerkeno/status/223886763045818368/photo/1',
      'https://twitter.com/e2b/status/224293729354268672/photo/1',
      'https://twitter.com/Freddy2805/status/225256579300204546/photo/1',
      'https://twitter.com/ninagarcia/status/224162888317796353/photo/1/large',
      'https://twitter.com/spacejunkienet/status/226246540111532033/photo/1/large',
      'https://twitter.com/littlewisehen/status/227031812013170688/photo/1',
      'https://twitter.com/littlewisehen/status/227031812013170688/photo/1',
      'https://twitter.com/littlewisehen/status/227031812013170688/photo/1'
    ].each do |url|
      puts '------------'
      puts url
      plugin = Loader::create url
      assert_match(%r{twimg.com/media}, plugin.url)
      assert(!plugin.title.empty?)

      puts " Image URL: #{plugin.url}"
      puts " Text: #{plugin.title}"
    end
  end  

  def test_imgur
    plugin = Loader::create 'http://imgur.com/vXUwn'
    assert_equal('http://i.imgur.com/vXUwn.png', plugin.url)
  end

=begin they delete images after a few weeks anyway
  def test_picpaste
    plugin = Loader::create 'http://picpaste.com/test_42x42.png'
    assert_match(%r{http://picpaste.com/pics/test_42x42.\d+.png}, plugin.url)
  end  
=end

  def test_soundcloud
    plugin = Loader::create 'http://soundcloud.com/flux-pavilion/flux-pavilion-the-story-of-shadrok/'
    assert_equal("Flux Pavilion - The Story Of Shadrok", plugin.title)
    assert_match(%r{<iframe}, plugin.embed)
    plugin = Loader::create 'http://soundcloud.com/shlohmo/shell-of-light-shlohmo-remix'
  end

  def test_soupasset
    plugin = Loader::create 'http://asset-6.soup.io/asset/10373/6349_6e2b_520.jpeg'
    assert_equal('http://asset-6.soup.io/asset/10373/6349_6e2b.jpeg', plugin.url)
  end

  def test_vimeo
    plugin = Loader::create 'http://vimeo.com/26134306'
    assert_equal("Eclectic Method - The Dark Side", plugin.title)
    assert_match(%r{<iframe src="https?://player.vimeo.com}, plugin.embed)
  end

  def test_xkcd
    plugin = Loader::create 'http://xkcd.com/420/'
    assert_equal('http://imgs.xkcd.com/comics/jealousy.png', plugin.url)
    assert_equal("Jealousy: Oh, huh, so you didn't know that story?", plugin.title)
  end

  def test_yfrog
    plugin = Loader::create 'http://yfrog.com/gywkzgj'
    assert_match(%r{yfrog\.com/img\d+/\d+/}, plugin.url)
  end

  def test_youtube
    plugin = Loader::create 'http://www.youtube.com/watch?v=PXRX47L_3yE&feature=feedbul'
    assert_equal("Medal of Honor Cat", plugin.title)
    assert_match(%r{embed/PXRX47L_3yE}, plugin.embed)
  end

  def test_imgurwebm
    plugin = Loader::create 'http://i.imgur.com/ose0MfD.gifv'
    assert_equal("This is bad, i guess.", plugin.title)
    assert_match(%r{.webm$}, plugin.url)
    plugin = Loader::create 'http://i.imgur.com/ose0MfD.gif'
    assert_equal("This is bad, i guess.", plugin.title)
    assert_match(%r{.webm$}, plugin.url)
  end

  def test_instagram
    plugin = Loader::create 'https://instagram.com/p/yQPOEVDkHX/'
    assert_equal('Klaus on Instagram', plugin.title)
    plugin = Loader::create 'https://instagram.com/p/0Dyn9HjkMt/'
    assert_equal('An other steelwool experiment w/ the guy in the dark', plugin.title)
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

