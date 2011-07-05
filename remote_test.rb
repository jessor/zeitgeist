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
end

class TestRemoteImage < Test::Unit::TestCase
  def app
    Sinatra::Application
  end

  def test_remote_image
    # using twitpic plugin
    remote = ImageDownloader.new('http://twitpic.com/5lg4ai')
    puts remote.tempfile
    assert_equal(remote.mimetype, 'image/png')
    assert_equal(remote.filesize, 568)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')

    # using imgur plugin
    remote = ImageDownloader.new('http://imgur.com/qbJ52')
    puts remote.tempfile
    assert_equal(remote.mimetype, 'image/png')
    assert_equal(remote.filesize, 568)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')

    # using the default plugin
    remote = ImageDownloader.new('http://apoc.cc/test_42x42.png')
    puts remote.tempfile
    assert_equal(remote.mimetype, 'image/png')
    assert_equal(remote.filesize, 568)
    assert_equal(Digest::MD5.file(remote.tempfile).to_s, '40a0e920a34f218c17981d296b9ecc3e')

    # test error handling:
    # not an image
    assert_raise(RemoteException) do
      remote = ImageDownloader.new('http://apoc.cc/')
    end
    # 404:
    assert_raise(RemoteException) do
      remote = ImageDownloader.new('http://apoc.cc/this_never_exists')
    end
    # dns error:
    assert_raise(RemoteException) do
      remote = ImageDownloader.new('http://icann_wouldnt_be.that_stupid/')
    end
=begin
    begin
      remote = RemoteImage.new(params[:remote_url])
      puts remote.url # remote url, but maybe changed in case of redirect
      puts remote.mime # image/{png/gif/jpg}
      puts remote.tags # array of extracted tags
      # puts remote.text # may include image description, alt-tag, etc.
      puts remote.temp # local path to downloaded image
    rescue RemoteImageException => e
      puts "unable to download or verify image: #{e.message}!"
    end
=end
  end
end

end # end namespace ZeitgeistRemote
end # end namespace Sinatra
