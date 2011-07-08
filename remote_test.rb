require 'test/unit'
require 'rack/test'
require 'digest/md5' 
require './zeitgeist.rb'
require './remote.rb'

ENV['RACK_ENV'] = 'test'

module Sinatra
module ZeitgeistRemote

class TestRemotePlugins < Test::Unit::TestCase
  include Plugins

  def app
    Sinatra::Application
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

  def test_imageshack
    plugin = Imageshack.new 'http://imageshack.us/photo/my-images/20/test42x42.png/'
    assert_match(plugin.url, %r{imageshack\.us/[^/]+/[^/]+/test42x42\.png})
  end

  def test_yfrog
    plugin = Yfrog.new 'http://yfrog.com/gywkzgj'
    assert_match(plugin.url, %r{yfrog\.com/img\d+/\d+/})
  end
    
end

class TestRemoteImage < Test::Unit::TestCase
  def app
    Sinatra::Application
  end

  def test_remote_image
    # using twitpic plugin
    remote = RemoteDownloader.new('http://twitpic.com/5lg4ai')
    puts remote.tempfile
    assert_equal(remote.mimetype, 'image/png')
    assert_equal(remote.filesize, 568)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')

    # using imgur plugin
    remote = RemoteDownloader.new('http://imgur.com/qbJ52')
    puts remote.tempfile
    assert_equal(remote.mimetype, 'image/png')
    assert_equal(remote.filesize, 568)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')

    # using the default plugin
    remote = RemoteDownloader.new('http://apoc.cc/test_42x42.png')
    puts remote.tempfile
    assert_equal(remote.mimetype, 'image/png')
    assert_equal(remote.filesize, 568)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')

    # test error handling:
    # not an image
    assert_raise(RemoteException) do
      remote = RemoteDownloader.new('http://apoc.cc/')
    end
    # 404:
    assert_raise(RemoteException) do
      remote = RemoteDownloader.new('http://apoc.cc/this_never_exists')
    end
    # dns error:
    assert_raise(RemoteException) do
      remote = RemoteDownloader.new('http://icann_wouldnt_be.that_stupid/')
    end
  end
end

end # end namespace ZeitgeistRemote
end # end namespace Sinatra

