# TODO: I would prefer to test the lib modules more seperate than this,
# but I couldn't figure out yet how to make the settings availible
#
if Dir.pwd == File.dirname(File.expand_path(__FILE__))
  Dir.chdir '..'
end
require 'test/unit'
require 'rack/test'
require 'digest/md5' 
require 'fileutils'
require './zeitgeist.rb'

ENV['RACK_ENV'] = 'test'

module Sinatra
module Carrier

class TestCarrier < Test::Unit::TestCase
  def app
    Sinatra::Application
  end

  TEST_IMAGE = './test/test_42x42.png'
  TEST_TEMP = '/tmp/zg_carrier_test'

  def copy_test_image
    FileUtils.cp(TEST_IMAGE, TEST_TEMP)
  end

  def test_abstract_storage_not_implemented
    assert_raise(NotImplementedError) do
      Storage::AbstractStore.new
    end
  end

  # tests the complete workflow from image varify and thumbnail creation
  # this is a valid image, so there shouldn't be any error
  def test_local_with_valid_image
    copy_test_image

    settings.carrier_store = 'local'

    temp = LocalTemp.new(TEST_TEMP)
    temp.process!

    assert_equal(TEST_TEMP, temp.image)
    assert_equal('42x42', temp.dimensions)
    assert_equal('image/png', temp.mimetype)
    assert_equal('40a0e920a34f218c17981d296b9ecc3e', temp.checksum)
    assert_not_nil(temp.thumbnail)
    thumbnail = temp.thumbnail

    assert(File.exists?(TEST_TEMP), 'temporary image does not exist!')
    assert(File.exists?(thumbnail), 'temporary thumbnail does not exist!')

    # store moves the temp files to their correct location:
    identifier = temp.store!

    assert_match(/^<store:local>/, identifier,
                "identifier must include store identification")

    temp.cleanup!

    assert(!File.exists?(TEST_TEMP), 'temporary image not deleted!')
    assert(!File.exists?(thumbnail), 'temporary thumbnail not deleted!')

    # create a new store, which one is specified by the store identifier
    store = Storage::create_by_identifier(identifier)

    image = store.retrieve!(identifier)

    # just for this test:
    image_local = './public/'+image.to_s
    thumbnail_local = './public/'+image.thumbnail

    puts image.inspect

    # obviously they should exist
    assert(File.exists?(image_local), 'image does not exist! '+image_local)
    assert(File.exists?(thumbnail_local), 'thumbnail does not exist!'+image_local)
    # and not empty
    assert_not_equal(0, File.size(image_local), 'image zero size')
    assert_not_equal(0, File.size(thumbnail_local), 'thumbnail zero size')

    assert_equal(Image, image.class)
    assert_match(%r{/\d{6}/zg.qkdp.png}, image.to_s)
    assert_match(%r{/\d{6}/zg.qkdp_200.png}, image.thumbnail)

    # delete from storage:
    store.destroy!(identifier)

    assert(!File.exists?(image_local), 'image exists after destroy!')
    assert(!File.exists?(thumbnail_local), 'image exists after destory!')
  end
end

end
end

