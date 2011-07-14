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
require './lib/remote/remote.rb'

# upload, validate, process tempfile
require './lib/carrier/carrier.rb'

#
# Config
#
configure do
  yaml = YAML.load_file('config.yaml')[settings.environment.to_s]
  yaml.each_pair do |key, value|
    set(key.to_sym, value)
  end

  #use Rack::Session::Cookie, :secret => settings.racksession_secret
  use Rack::Flash
  enable :sessions
  set :haml, {:format => :html5}
  set :allowed_mime, ['image/png', 'image/jpeg', 'image/gif']
  set :sinatra_authentication_view_path, 'views/auth_'

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

class Item
  include DataMapper::Resource

  property :id,         Serial
  property :type,       String, :default => 'image' # image, video, audio
  property :image,      String, :auto_validation => false
  property :source,     Text   # set to original (remote) url
  property :title,      Text
  property :created_at, DateTime

  # image meta information
  property :size,       Integer
  property :mimetype,   String
  property :checksum,   String, :unique => true
  property :dimensions, String

  # taggings
  has n, :tags, :through => Resource

  # hooks for processing either the upload or remote url
  # NOTE: raise a RuntimeError if something went wrong!
  before :save do
    tempfile = @image
    puts tempfile

    if not tempfile # remote upload!
      @plugin = Sinatra::Remote::Plugins::Loader::create(@source)
      raise 'invalid url!' if not @plugin

      if @plugin.url
        puts "Download remote content from url: #{@plugin.url}"
        downloader = Sinatra::Remote::Downloader.new(@plugin.url)
        begin
          downloader.download!
        rescue
          puts "error downloading remote URL(#{@source}): #{$!.message}"
          puts $@
          raise 'error downloading remote: ' + $!.message
        else
          tempfile = downloader.tempfile
          self.size = downloader.filesize
        end
      end

      self.type = @plugin.type
      self.title = @plugin.title[0..49]
      if @plugin.tags
        @plugin.tags.each do |tagname|
          # only add existing tags as association:
          tagname.downcase!; tagname.strip!
          tag = Tag.first(:tagname => tagname)
          self.tags << tag if tag
        end
      end
    end

    if tempfile # temporary fileupload
      begin
        localtemp = Sinatra::Carrier::LocalTemp.new(tempfile, @created_at)
        localtemp.process! # creates thumbnail, verify image

        self.dimensions = localtemp.dimensions
        self.mimetype = localtemp.mimetype
        self.checksum = localtemp.checksum
        self.size = localtemp.filesize if not @plugin

        if localtemp.checksum and (item = Item.first(:checksum => localtemp.checksum))
          raise "Duplicate image found based on checksum, id: #{item.id}"
        end

        # store file in configured storage
        self.image = localtemp.store!
      rescue
        puts $!.message
        puts $@
        raise $!.message
      ensure
        # to make sure tempfiles are deleted in case of an error 
        localtemp.cleanup! 
      end
    end
  end

  after :destroy do
    # get and destory file storage
    identifier = attribute_get(:image)
    return if not identifier
    store = Sinatra::Carrier::Storage::create_by_identifier(identifier)
    store.destroy! identifier
  end

  # the image property should return the URI for thumbnail
  # and full-sized image
  def image
    # this creates a storage object, which one is based on the
    # identification, this means the store can be switched in an
    # running installation. New images will be stored in the new
    # storage, but old not mitigated ones are still available.
    if not @image_obj
      identifier = attribute_get(:image)
      return nil if not identifier
      store = Sinatra::Carrier::Storage::create_by_identifier(identifier)
      @image_obj = store.retrieve! identifier # this returns an Image object for view
    end
    @image_obj
  end

  def title
    title = attribute_get(:title)
    return nil if not title or title.empty?
    super
  end
end

class Tag
  include DataMapper::Resource

  property :id,         Serial
  property :tagname,    String, :unique => true

  has n, :items, :through => Resource

  def tagname=(tag)
    # cleanup:
    tag.gsub!(%r{[<>/~\^,+]}, '')
    tag.strip!
    tag.downcase!
    super
  end
end

DataMapper.finalize
DataMapper.auto_upgrade!

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

  def pagination
    @items.pager.to_html(request.path, :size => 5)
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

get '/' do
  @autoload = h params['autoload'] if params['autoload']
  @items = Item.page(params['page'],
                     :per_page => settings.items_per_page,
                     :order => [:created_at.desc])
  pagination
  haml :index
end

get '/filter/by/type/:type' do
  @items = Item.page(params['page'],
                     :per_page => settings.items_per_page,
                     :type => params[:type],
                     :order => [:created_at.desc])
  pagination
  haml :index
end

get '/filter/by/tag/:tag' do
  @items = Item.page(params['page'],
                     :per_page => settings.items_per_page,
                     Item.tags.tagname => params[:tag],
                     :order => [:created_at.desc])
  pagination
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
  remoteplugin = Sinatra::Remote::Plugins::Loader::create(params['url'])
  remoteplugin.embed # returns html code for embedding
end

get '/search' do
  if is_ajax_request?
    haml :search, :layout => false
  else
    haml :search
  end
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

get '/new' do
  if is_ajax_request?
    haml :new, :layout => false
  else
    haml :new
  end
end

# we got ourselves an upload, sir
# with params for image_upload or remote_url
post '/new' do
  tags = params[:tags] ? params[:tags].split(',') : []

  tempfile = nil # stays nil for remote url
  if params[:image_upload]
    tempfile = params[:image_upload][:tempfile].path
    source = params['image_upload'][:filename]
  elsif params[:remote_url] and not params[:remote_url].empty?
    source = params[:remote_url]
  else
    raise 'You should select either an upload or an remote url!'
  end

  # store in database, the before save hook downloads/proccess the file
  @item = Item.new(:image => tempfile, :source => source)
  if @item.save
    # successful? append new tags:
    tags.each do |tagname|
      tag = Tag.first_or_create(:tagname => tagname)
      if tag.save
        @item.tags << tag
      else
        raise 'error saving new tag: ' + tag.errors.first
      end
    end
    @item.save # save the new associations

    # success message, api returns item created and tags added
    if is_ajax_request? or is_api_request? 
      content_type :json
      {:item => @item, :tags => @item.tags}.to_json
    else
      flash[:notice] = 'New item added successfully.'
      redirect '/'
    end
  else
    raise 'new item error: ' + @item.errors.full_messages.inspect
  end
end

get '/:id' do
  pass unless params[:id].match /^\d+$/
  @item = Item.get(params[:id])
  raise "no item found with id #{params[:id]}" if not @item

  if is_ajax_request? or is_api_request? 
    content_type :json
    {:item => @item, :tags => @item.tags}.to_json
  elsif @item.type == 'image'
    redirect @item.image
  else
    remoteplugin = Sinatra::Remote::Plugins::Loader::create(@item.source)
    remoteplugin.embed # returns html code for embedding
  end
end

# adds or removes tags from an item
post '/:id/update' do
  id = params[:id]
  add_tags = (params[:add_tags] || '').split(',')
  del_tags = (params[:del_tags] || '').split(',')

  added_tags = []
  deleted_tags = []

  # get the item to edit
  @item = Item.get(id)
  raise "item with id #{id} not found!" if not @item

  # add tags (create them if not exists)
  add_tags.each do |tag|
    newtag = Tag.first_or_create(:tagname => tag)
    # (try to) save tag
    if not newtag or not newtag.save
      raise "error saving tags: #{newtag.errors.inspect}" 
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

  raise "error save item: #{@item.errors.inspect}" if not @item.save

  if is_ajax_request?
    content_type :json
    {:added_tags => added_tags, :deleted_tags => deleted_tags}.to_json
  elsif is_api_request? 
    content_type :json
    {:item => @item, :tags => @item.tags}.to_json
  else
    redirect '/'
  end
end

post '/:id/delete' do
  if current_user.admin? or is_api_request?
    item = Item.get(params[:id])
    raise 'item not found' if not item
    item.destroy
    if is_api_request?
      content_type :json
      {:id => item.id}.to_json
    else
      flash[:notice] = "Item ##{params[:id]} is gone now."
      redirect params['return_to']
    end
  else
    raise 'Y U NO AUTHENTICATE?'
  end
end

get '/feed' do
  @items = Item.all(:limit => 10, :order => [:created_at.desc])
  builder :itemfeed 
end

error 400..510 do # error RuntimeError do
  puts "error exception do"
  @error = env['sinatra.error'].message
  @code = response.status.to_s
  if is_ajax_request? or is_api_request? 
    status 200 # much easier to handle when it response normally
    content_type :json
    {:error => @error}.to_json
  elsif request.get?
    haml :error, :layout => false 
  else
    flash[:error] = @error
    redirect '/'
  end
end

# compile sass stylesheet
get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end

