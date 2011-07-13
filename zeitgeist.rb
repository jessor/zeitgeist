require 'rubygems'
require 'bundler/setup'

Bundler.require(:default)

# ruby core requirements
require 'base64'
require 'digest/md5'
require 'json'
require 'uri'
require 'yaml'

# remote url download library
require './remote.rb'

#
# Config
#
configure do
  set :haml, {:format => :html5}
  use Rack::Flash
  enable :sessions
  set :allowed_mime, ['image/png', 'image/jpeg', 'image/gif']

  yaml = YAML.load_file('config.yaml')[settings.environment.to_s]
  yaml.each_pair do |key, value|
    set(key.to_sym, value)
  end

  if settings.pagespeed
    use Rack::PageSpeed, :public => 'public' do
      store :disk => 'public'
      combine_javascripts
      minify_javascripts
    end
  end
end

#
# Models
#
if settings.respond_to? 'datamapper_logger'
  DataMapper::Logger.new(STDOUT, settings.datamapper_logger)
end
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/zeitgeist.db")

class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  storage :file

  def filename
    make_filename
  end

  def store_dir
=begin
    thats not gonna work... the year/month directory needs to
    be stored somewhere else (within filename?) but the
    thumbnail filename is not easily overwritten with model
    instance attributes, atleast i wasn't able to figure
    it out yet.

    year_month = Time.now.strftime('%Y%m')
    path = "#{settings.assetpath}/#{year_month}/"
    Dir.mkdir path if not Dir.exists? path
    path
=end
   "#{settings.assetpath}/"
  end

  def extensions_white_list
    %w(jpg jpeg gif png)
  end

  version :thumbnail do
    def collapse
      manipulate! do |img|
        img.collapse!
        img
      end
    end
    process :collapse # to first frame for gif animations
    # http://rubydoc.info/github/jnicklas/carrierwave/master/CarrierWave/MiniMagick/ClassMethods
    process :resize_to_fill => [200, 200]
  end

  def make_filename(postfix='')
    mimetype = model.mimetype
    checksum = [model.checksum].pack('H*')
    extension = '.' + mimetype.slice(mimetype.index('/')+1, mimetype.length)

    self.class::base64_filename(store_dir, checksum, postfix + extension)
  end

  def self.base64_filename(path, hash, postfix, prefix='zg.')
    path += '/' if path[-1] != '/'
    (1..6).each do |k|
      partial = hash[0...(k*3)]
      partial = partial.ljust(k*3) if k == 6 # "impossible"
      encoded = Base64::urlsafe_encode64(partial).downcase
      filename = prefix + encoded + postfix
      return filename if not File.exists?(path + filename)
    end
    return nil
  end
end

class Item
  include DataMapper::Resource

  property :id,         Serial
  property :type,       String # image, video, audio
  property :image,      String, :auto_validation => false
  property :source,     Text   # set to original (remote) url
  property :name,       String # original filename
  property :created_at, DateTime

  # image meta information
  property :size,       Integer
  property :mimetype,   String
  property :checksum,   String
  property :dimensions, String

  mount_uploader :image, ImageUploader
  has n, :tags, :through => Resource
end

class Tag
  include DataMapper::Resource

  property :id,         Serial
  property :tagname,    String, :unique => true

  has n, :items, :through => Resource

  def tagname=(tag)
    tag.downcase!
    super
  end
end

class Downloaderror
  include DataMapper::Resource

  property :id,         Serial
  property :source,     Text
  property :code,       String
end

DataMapper.finalize
DataMapper.auto_upgrade!

# initialize oembed
# later detect embed provider by url 
# (if not overwritten by url)
OEmbed::Providers.register_all

#
# Helpers
# 

helpers do

  include Rack::Utils
  alias_method :h, :escape_html

  def partial(page, options={})
    unless @partials == false
      haml page, options.merge!(:layout => false)
    end
  end

  def is_ajax_request?
    if respond_to? :content_type
      if request.xhr?
        true
      else
        false
      end
    else
      false
    end
  end

  def is_api_request?
    ( env['HTTP_X_API_SECRET'] == settings.api_secret )
  end

  def fileprefix
    "#{Time.now.strftime("%y%m%d%H%M%S")}_zeitgeist"
  end

end

#
# General Filters
# 
before do
  if request.host =~ /^www\./
    redirect "http://#{request.host.gsub('www.', '')}:#{request.port}", 301
  end
end

#
# Routes
# 


error RuntimeError do
  @error = env['sinatra.error'].message
  if request.get?
    haml :error, :layout => false
  elsif is_ajax_request? or is_api_request? 
    status 200 # much easier to handle when it response normally
    content_type :json
    {:error => @error}.to_json
  else
    flash[:error] = @error
    redirect '/'
  end
end

get '/' do
  @autoload = h params['autoload'] if params['autoload']
  @items = Item.page(params['page'], 
                     :per_page => settings.items_per_page,
                     :order => [:created_at.desc])
  @pagination = @items.pager.to_html('/', :size => 5)
  haml :index
end

get '/filter/by/type/:type' do
  @items = Item.all(:type => params[:type], :order => [:created_at.desc])
  haml :index
end

get '/filter/by/tag/:tag' do
  @items = Item.all(Item.tags.tagname => params[:tag], :order => [:created_at.desc])
  haml :index
end

get '/about' do
  if is_ajax_request?
    haml :about, :layout => false
  else
    haml :about
  end
end

post '/embed' do
  remoteplugin = Sinatra::ZeitgeistRemote::Plugins::plugin_by_url(params['url'])
  remoteplugin.embed # returns html code for embedding
end

post '/search' do
  @items = Tag.all(:tagname.like => "%#{params['q']}%")
  if is_ajax_request?
    content_type :json
    @items.to_json
  else
    redirect "/filter/by/tag/#{params['searchquery']}"
  end
end

get '/search' do
  if is_ajax_request?
    haml :search, :layout => false
  else
    haml :search
  end
end

get '/new' do
  if is_ajax_request?
    haml :new, :layout => false
  else
    haml :new
  end
end

get '/item/:id' do
  @item = Item.get(params[:id])
  if not @item
    error = "no item found with id #{params[:id]}"
  end

  if is_ajax_request? or is_api_request? 
    content_type :json
    if error
      {:error => error}.to_json
    else
      {:item => @item, :tags => @item.tags}.to_json
    end
  else
    if error
      flash[:error] = error
      redirect '/'
    else
      redirect @item.image
    end
  end
end

# we got ourselves an upload, sir
# with params for image_upload or remote_url
post '/new' do
  error = nil
  flash[:error] = nil
  type = upload = source = filename = filesize = mimetype = checksum = dimensions = nil

  tags = []
  tags = params[:tags].split(',').map { |tag| tag.strip!; tag.downcase! } if params[:tags]
  tempfile = nil

  if params[:image_upload]
    type = 'image'
    tempfile = params[:image_upload][:tempfile]
    title = params['image_upload'][:filename]

  elsif params[:remote_url] and not params[:remote_url].empty? # remote upload
    source = params[:remote_url]
    plugin = Sinatra::ZeitgeistRemote::Plugins::plugin_by_url(source)
    if not plugin
      raise 'invalid url'
    end

    if plugin.url
      downloader = Sinatra::ZeitgeistRemote::RemoteDownloader.new(plugin)
      begin
        downloader.download!
      rescue Sinatra::ZeitgeistRemote::RemoteException => e
        puts "Error downloading remote source URL (#{source}): #{e.message}" 
        puts $@
        raise "#{e.message}"
      else
        tempfile = downloader.tempfile
      end
    end

    type = plugin.type
    title = plugin.title
    # only existing tags:
    plugin.tags.each do |tag|
      tag.downcase!
      tags << tag if Tag.first(:tagname => tag)
    end
    puts "new tags: " + tags.inspect
  else
    raise 'You need to specifiy either a file or remote url for uploading!'
  end

  # check upload file and generate meta infos
  if tempfile
    mimetype = FileMagic.new(FileMagic::MAGIC_MIME).file(tempfile)
    mimetype = mimetype.slice 0...mimetype.index(';')

    # mimetype not allowed? = no image file?
    if not settings.allowed_mime.include? mimetype
      raise "Image file with invalid mimetype: #{mimetype}!"
    end
    
    # more meta information (only for image types!)
    checksum = Digest::MD5.file(tempfile).hexdigest
    filesize = File.size(tempfile) if not filesize
    dimensions = MiniMagick::Image.open(tempfile)["dimensions"].join 'x'
  end

  # for non image types hash the original url instead of
  # (preview) image or nil
  if type != 'image'
    checksum = Digest::MD5.hexdigest(source)
  end

  # check for duplicate images before inserting
  if checksum and (item = Item.first(:checksum => checksum))
    raise "Duplicate image found based on checksum, id: #{item.id}"
  end

  # store in database, let carrierwave take care of the upload
  @item = Item.new(:type => type, :image => File.open(tempfile), :source => source,
              :name => title[0...49], :size => filesize, :mimetype => mimetype,
              :checksum => checksum, :dimensions => dimensions)

  if not @item.save
    raise "error saving item: #{@item.errors.full_messages.inspect}"
  end

  tags.each do |newtag|
    tag = Tag.first_or_create(:tagname => newtag)
    if not tag.save 
      raise "error saving tags: #{tag.errors.full_messages.inspect}" 
    end
    @item.tags << tag
  end
  @item.save # save the new associations

  if is_ajax_request? or is_api_request? 
    content_type :json
    {:item => @item, :tags => @item.tags}.to_json
  else
    flash[:notice] = 'New item added successfully.'
    redirect '/'
  end
end

# adds or removes tags from an item
post '/edit/:id' do
  id = params[:id]
  add_tags = (params[:add_tags] || '').split(',').map { |tag| tag.strip!; tag.gsub(/<\/?[^>]*>/,'') }
  del_tags = (params[:del_tags] || '').split(',').map { |tag| tag.strip!; tag.gsub(/<\/?[^>]*>/,'') }

  added_tags = []
  deleted_tags = []

  # get the item to edit
  @item = Item.get(id)
  if not @item
    error = "item with id #{id} not found!"
  else
    add_tags.each do |tag|
      puts add_tags.inspect
      newtag = Tag.first_or_create(:tagname => tag)
      puts newtag.inspect
      # (try to) save tag
      if not newtag or not newtag.save
        error = "#{newtag.errors}"
        break
      end
      # create association
      @item.tags << newtag
      added_tags << newtag
    end

    # atm only allowed via api
    if is_api_request?
      del_tags.each do |tag|
        @item.tags.each do |old_tag|
          if old_tag.tagname == tag 
            @item.tags.delete(old_tag) 
            deleted_tags << old_tag
          end
        end
      end
    end

    if not @item.save
      error = @item.errors
    end
  end

  if is_ajax_request?
    content_type :json
    if error
      {:error => error}.to_json
    else
      {:added_tags => added_tags, :deleted_tags => deleted_tags}.to_json
    end
  elsif is_api_request? 
    content_type :json
    if error
      {:error => error}.to_json
    else
      {:item => @item, :tags => @item.tags}.to_json
    end
  else
    flash[:error] = error 
    redirect '/'
  end
end

get '/feed' do
  @items = Item.all(:limit => 10, :order => [:created_at.desc])
  builder :itemfeed 
end

error 400..510 do
  @code = response.status.to_s
  haml :error, :layout => false
end

# compile sass stylesheet
get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end

