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
  # configure by yaml file:
  yaml = YAML.load_file('config.yaml')

  # apply environment specific options:
  yaml = yaml.merge yaml[settings.environment.to_s]

  yaml.each_pair do |key, value|
    set(key.to_sym, value)
  end

  #use Rack::Session::Cookie, :secret => settings.racksession_secret
  use Rack::Flash
  enable :sessions
  set :haml, {:format => :html5}
  set :allowed_mime, ['image/png', 'image/jpeg', 'image/gif']
  set :sinatra_authentication_view_path, 'views/auth_'
  # NOTE: _must_ be disabled otherwise our custom error handler does not work correctly 
  disable :show_exceptions
  disable :dump_errors
  disable :raise_errors 

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
  puts "Setup DataMapper logging: #{settings.datamapper_logger}"
  DataMapper::Logger.new(STDOUT, settings.datamapper_logger)
end
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/zeitgeist.db")


class DuplicateError < Exception
  attr_reader :id
  def initialize(id)
    @id = id
    super("Duplicate image found based on checksum, id: #{id}")
  end
end

class Item
  include DataMapper::Resource

  property :id,         Serial
  property :type,       String, :default => 'image' # image, video, audio
  property :image,      String, :auto_validation => false
  property :source,     Text   # set to original (remote) url
  property :title,      Text
  property :created_at, DateTime
  # currently this only 'caches' if this item has the nsfw tag or not
  # otherwise its stupidly difficult with dm to query non-nsfw tagged items
  property :nsfw,       Boolean, :default => false

  # image meta information
  property :size,       Integer
  property :mimetype,   String
  property :checksum,   String, :unique => true
  property :dimensions, String

  # taggings
  has n, :tags, :through => Resource

  # upvotes, count of upvotes for this item, (caching)
  has n, :upvotes
  property :upvote_count, Integer, :default => 0

  # hooks for processing either the upload or remote url
  # NOTE: raise a RuntimeError if something went wrong!
  before :create do
    tempfile = @image

    if not tempfile and @source # remote upload!
      @plugin = Sinatra::Remote::Plugins::Loader::create(@source)
      raise 'invalid url!' if not @plugin

      if @plugin.url
        puts "Download remote content from url: #{@plugin.url}"
        downloader = Sinatra::Remote::Downloader.new(@plugin.url)
        begin
          downloader.download!
        rescue Exception => e
          puts "error downloading remote URL(#{@source}): #{e.message}"
          puts e.backtrace
          raise 'error downloading remote: ' + e.message
        else
          tempfile = downloader.tempfile
          self.size = downloader.filesize
        end
      elsif @plugin.type == 'image'
        # plugins for image hosting providers need to return a media url,
        # and can not just live with their source url alone
        raise "selected plugin (#{@plugin.class.to_s}) doesn't found image"
      end

      self.type = @plugin.type
      self.title = @plugin.title[0..49] if @plugin.title 
      if @plugin.tags
        @plugin.tags.each do |tagname|
          if @plugin.only_existing_tags
            # only add existing tags as association:
            tagname.downcase!; tagname.strip!
            tag = Tag.first(:tagname => tagname)
            self.tags << tag if tag
          else
            tagname.downcase!; tagname.strip!
            tag = Tag.first_or_create(:tagname => tagname)
            self.tags << tag if tag
          end
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
    
        # animated autotagging
        self.tags << Tag.first_or_create(:tagname => 'animated') if localtemp.animated

        if localtemp.checksum and (item = Item.first(:checksum => localtemp.checksum))
          raise DuplicateError.new(item.id)
        end

        # store file in configured storage
        self.image = localtemp.store!
      rescue Exception => e
        puts e.message
        puts e.backtrace
        raise e.message
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

  # build html title/alternate text
  def html_title
    html_title = "#{self.id}: "
    title = (self.title || self.source)
    if self.source =~ /^http/
      html_title += '<a href="%s">%s</a>' % [self.source, title]
    else
      html_title += title
    end
    # dimensions (only relevant for images)
    if self.type == 'image'
      html_title += (' at <a href="/show/dimensions/%s">%s</a>' % 
          [self.dimensions, self.dimensions])
    end
  end

  # returns the embed code for this item
  def embed
    return if self.type == 'image'
    remoteplugin = Sinatra::Remote::Plugins::Loader::create(self.source)
    remoteplugin.embed # returns html code for embedding
  end

  def add_tags(tags)
    tags = tags.split(',') if tags.class != Array
    return if tags.empty?
    puts "Append tags to item(##{self.id}): #{tags.join('|')}"
    added_tags = []
    tags.each do |tagname|
      Tag.cleanup! tagname
      tag = Tag.first_or_create(:tagname => tagname)
      puts "First or create for tagname:#{tagname}: id=#{tag.id}"
      if not tag.errors.empty?
        puts "Errors occured: DataMapper first_or_create: " + 
          tag.errors.full_messages.join(',')
        next # just try the next one ;)
      end

      # nsfw item cache property
      self.nsfw = true if tagname == 'nsfw'

      self.tags << tag
      added_tags << tag
    end
    self.save # save the new associations
    return added_tags
  end

  def del_tags(tags)
    tags = tags.split(',') if tags.class != Array
    return if tags.empty?
    puts "Drop tags from item(##{self.id}): #{tags.join('|')}"
    deleted_tags = []
    tags.each do |tag|
      Tag.cleanup! tag
      self.tags.each do |old_tag|
        if old_tag.tagname == tag
          puts "Drop existing tag #{old_tag.tagname}!"
          self.tags.delete(old_tag) 
          deleted_tags << old_tag

          # nsfw item cache property
          self.nsfw = false if tag == 'nsfw'
        end
      end
    end
    self.save # save the new associations
    return deleted_tags
  end
end

class Tag
  include DataMapper::Resource

  property :id,         Serial
  property :tagname,    String, :unique => true

  has n, :items, :through => Resource

  def tagname=(tagname)
    if not tagname.valid_encoding?
      puts "Invalid Encoding tagname(#{tagname.inspect})!"
      tagname = tagname.force_encoding('ISO-8859-1').encode('UTF-8')
      raise 'Broken Encoding!' if not tagname.valid_encoding?
    end
    self.class::cleanup! tagname
    super
  end

  def tagname
    tagname = super
    if not tagname.valid_encoding?
      puts "Invalid Encoding tagname(#{tagname.inspect})"
      tagname = tagname.force_encoding('ISO-8859-1').encode('UTF-8')
      puts "Save fixed tagname(#{tagname.inspect})"
      self.tagname = tagname # save the fixed version
      self.save
      raise 'Broken Encoding!' if not tagname.valid_encoding?
    end
    return tagname
  end

  def self.cleanup!(tag)
    tag.gsub!(%r{[<>/~\^,]}, '')
    tag.strip!
    tag.downcase!
  end
end

class Upvote
  include DataMapper::Resource

  property :id,       Serial
  property :hostmask, String
  belongs_to :dm_user
  belongs_to :item

  after :create do
    # item = self.item
    item.update(:upvote_count => item.upvote_count + 1)
  end

  after :destroy do
    # item = self.item
    item.update(:upvote_count => item.upvote_count - 1)
  end
end

class DmUser
  has n, :upvotes

  def to_ary
    [self]
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

  def logger
    request.logger
  end

  def shorten(str)
    if str.length > 11
      "#{str[0..(10)]}..."
    else
      str
    end
  end

  # used as a helper function to test if this item
  # has been upvoted by the current user
  def item_upvoted?(item)
    item.upvotes.count(:dm_user_id => current_user.id) > 0
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
                     :nsfw => false,
                     :order => [:created_at.desc])
  pagination
  haml :index
end

get '/show/:type' do
  type = params[:type]

  if %w{video audio image}.include? type
    @title = "#{type.capitalize}s at #{settings.pagetitle}"
    @items = Item.page(params[:page],
                       :per_page => settings.items_per_page,
                       :type => type,
                       :nsfw => false,
                       :order => [:created_at.desc]) 
  elsif type == 'nsfw'
    @title = "nsfw at #{settings.pagetitle}"
    @items = Item.page(params[:page],
                       :per_page => settings.items_per_page,
                       :order => [:created_at.desc])
  elsif type == 'voted'
    @title = "popular at #{settings.pagetitle}"
    @items = Item.page(params[:page], 
                       :per_page => settings.items_per_page,
                       :upvote_count.gt => 0,
                       :order => [:upvote_count.desc])
  else
    raise 'show what?'
  end

  pagination
  haml :index
end

get '/show/tag/:tag' do
  tag = params[:tag]
  @title = "#{tag} at #{settings.pagetitle}"
  @items = Item.page(params['page'],
                     :per_page => settings.items_per_page,
                     :nsfw => false,
                     Item.tags.tagname => params[:tag],
                     :order => [:created_at.desc])
  pagination
  haml :index
end

get '/show/dimensions/:dimensions' do
  dimensions = params[:dimensions]
  @title = "#{dimensions} at #{settings.pagetitle}"
  @items = Item.page(params['page'],
                     :per_page => settings.items_per_page,
                     :nsfw => false,
                     :dimensions => dimensions,
                     :order => [:created_at.desc])
  pagination
  haml :index
end

get '/list/:attribute' do
  @title = "List of #{params[:attribute]} on #{settings.pagetitle}"

  case params[:attribute]
  when 'tags'
    @items = Tag.all(:order => [:tagname.asc])
  when 'dimensions'
    @items = Item.all(:fields => [:dimensions], :unique => true, :order => [:dimensions.asc])
  else
    flash[:error] = "Currently unsupported"
    redirect '/'
  end

  haml :list
end

get '/about' do
  @title = "About #{settings.pagetitle}"
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
  @title = "Search #{settings.pagetitle}"
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
    redirect "/show/tag/#{params['searchquery']}"
  end
end

get '/new' do
  @title = "Upload something to #{settings.pagetitle}"
  if is_ajax_request?
    haml :new, :layout => false
  else
    haml :new
  end
end

# we got ourselves an upload, sir
# with params for image_upload or remote_url
post '/new' do
  tags = params.has_key?('tags') ? params['tags'] : ''

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
  begin
    @item = Item.new(:image => tempfile, :source => source)
    if @item.save
      # successful? append new tags:
      @item.add_tags(tags)

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
  rescue DuplicateError => e
    item = Item.get(e.id)
    item.add_tags(tags)
    raise "Duplicate image found based on checksum, id: #{e.id}"
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

post '/upvote' do
  item_id = params[:id]
  item = Item.get(item_id)

  user_id = hostmask = nil
  if is_api_request?
    # hostmask...
  elsif logged_in?
    user_id = current_user.id
  end

  if not user_id and not hostmask
    raise 'you need to login to upvote'
  end

  if params[:remove]
    upvote = Upvote.all(:item => item, :conditions => ['dm_user_id = ? OR (hostmask <> null AND hostmask = ?)', user_id, hostmask])
    raise 'upvote not found!' if not upvote
    if upvote.destroy
      flash[:notice] = 'Upvote removed.'
      redirect '/'
      return
    else
      raise 'upvote not removed, error occured'
    end
  end

  # upvote only once:
  if Upvote.count(:item => item, :conditions => ['dm_user_id = ? OR (hostmask <> null AND hostmask = ?)', user_id, hostmask]) > 0
    raise 'you cannot upvote twice'
  end

  upvote = Upvote.new(:item => item, 
                      :dm_user_id => user_id, 
                      :hostmask => hostmask)
  if upvote.save
    flash[:notice] = 'Item upvoted.'
    redirect '/'
  else
    raise 'upvote error: ' + upvote.errors.full_messages.inspect
  end
end

# adds or removes tags from an item
post '/:id/update' do
  id = params[:id]
  add_tags = (params[:add_tags] || '').split(',')
  del_tags = (params[:del_tags] || '').split(',')

  # get the item to edit
  @item = Item.get(id)
  raise "item with id #{id} not found!" if not @item

  # add tags (create them if not exists)
  added_tags = @item.add_tags(add_tags)
  deleted_tags = @item.del_tags(del_tags)

  if is_ajax_request? or is_api_request?
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

get %r{/feed(/nsfw)?} do
  nsfw = params[:captures] ? true : false

  @base = request.url.chomp(request.path_info)

  if nsfw
    @items = Item.all(:limit => 10, :order => [:created_at.desc])
  else
    @items = Item.all(:limit => 10, :nsfw => false, :order => [:created_at.desc])
  end

  content_type :xml
  haml :feed, :layout => false, :format => :xhtml
end

def handle_error
  error = env['sinatra.error']
  puts "Zeitgeist application error occured: #{error.inspect}"
  puts "Backtrace: " + error.backtrace.join("\n")
  @error = error.message
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

error RuntimeError do
  handle_error
end

error 400..510 do # error RuntimeError do
  handle_error
end

# compile sass stylesheet
get '/stylesheet.css' do
  scss :stylesheet, :style => :compact
end

