require 'rubygems'
require 'bundler/setup'

Bundler.require(:default)

# ruby core requirements
require 'base64'
require 'digest/md5'
require 'json'
require 'uri'
require 'yaml'
require 'drb'

# remote url download library
require './lib/remote/remote.rb'

# upload, validate, process tempfile
require './lib/carrier/carrier.rb'

# used to symbolize the yaml config file
module HashExtensions
  def symbolize_keys
    inject({}) do |acc, (k,v)|
      key = String === k ? k.to_sym : k
    value = Hash === v ? v.symbolize_keys : v
    acc[key] = value
    acc
    end
  end
end
Hash.send(:include, HashExtensions)

#
# Config
#
configure do
  # configure by yaml file:
  yaml = YAML.load_file('config.yaml').symbolize_keys

  # apply environment specific options:
  yaml = yaml.merge yaml[settings.environment.to_sym]
  yaml.delete :production
  yaml.delete :development

  yaml.each_pair do |key, value|
    set(key, value)
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

  # item submitter
  belongs_to :dm_user, :required => false

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
  has n, :items

  property :api_secret, String

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

  def api_request?
    request.accept == ['application/json'] or request.xhr?
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
  end # TODO: ref

  def random_token(length)
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
    token = ''
    length.times do
      token += chars[rand(chars.length)]
    end
    token
  end
end

#
# General Filters
# 
before do
  if request.host =~ /^www\./
    redirect "http://#{request.host.gsub('www.', '')}:#{request.port}", 301
  end

  # X-Auth API authentication as specified in the documentation
  if request.env.has_key? 'HTTP_X_API_AUTH'
    email, api_secret = request.env['HTTP_X_API_AUTH'].split('|')
    user = User.get(:email => email)

    if not user or not user.api_secret
      raise 'user not found or no shared secret'
    end

    if api_secret == user.api_secret
      # authenticate current user
      session[:user] = user.id
    else
      raise 'invalid authentication'
    end
  end
end

#
# Routes
# 

get '/' do
  @autoload = h params['autoload'] if params['autoload']

  @items = Item.page(params[:page],
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
  tag = unescape params[:tag]
  @title = "#{tag} at #{settings.pagetitle}"
  @items = Item.page(params[:page],
                     :per_page => settings.items_per_page,
                     Item.tags.tagname => tag,
                     :order => [:created_at.desc])
  pagination
  haml :index
end

get '/show/dimensions/:dimensions' do
  dimensions = params[:dimensions]
  @title = "#{dimensions} at #{settings.pagetitle}"
  @items = Item.page(params[:page],
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
  if api_request?
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
  if api_request?
    haml :search, :layout => false
  else
    haml :search
  end
end

post '/search' do
  @items = Tag.all(:tagname.like => "%#{params['q']}%")
  if api_request?
    content_type :json
    @items.to_json
  else
    redirect "/show/tag/#{params['searchquery']}"
  end
end

get '/new' do
  @title = "Upload something to #{settings.pagetitle}"
  if api_request?
    haml :new, :layout => false
  else
    haml :new
  end
end

# upload images/remote download urls
# params: tags, image_upload[], remote_url[], announce
post '/new' do
  tags = params.has_key?('tags') ? params['tags'] : ''
  uploads = params.has_key?('image_upload') ? params['image_upload'] : []
  remotes = params.has_key?('remote_url') ? params['remote_url'] : []
  announce = params['announce']

  # legacy (api) / depricated api
  if uploads.class != Array and uploads.class == Hash # just to make sure
    uploads = [ uploads ]
  end
  if remotes.class != Array and remotes.class == String
    remotes = [ remotes ]
  end

  # neiter upload nor remote? -> error
  if uploads.empty? and remotes.empty?
    raise 'You should select at least one upload or remote url!'
  end

  # process uploads and remote urls, stop if an error occured
  items = [] # Array of Item Objects
  tag_objects = [] # Array of Tag Objects
  begin

    while not uploads.empty? or not remotes.empty? 
      upload = uploads.pop
      remote = remotes.pop if not upload

      # for upload use the tempfile as image and the orig. filename as source
      # for remote unset image and use the url as source
      image = upload ? upload[:tempfile].path : nil
      source = remote ? remote : upload[:filename]

      # skip empty ones
      next if not image and source.empty?

      # the hook will perform the remote downloading and image processing
      item = Item.new(:image => image, 
                      :source => source, 
                      :dm_user_id => (logged_in?) ? current_user.id : nil)
      if item.save
        item.add_tags(tags)
        items << item
        tag_objects = item.tags #i dont like this either
      else
        raise 'Item create error: ' + item.errors.full_messages.join(', ')
      end
    end

    # announce in irc:
    irc_settings = settings.irc_announce
    if irc_settings[:active] and announce
      rbot = DRbObject.new_with_uri(irc_settings[:uri])
      login = "remote login #{irc_settings[:username]} #{irc_settings[:password]}"
      id = rbot.delegate(nil, login)[:return]
      rbot.delegate(id, "dispatch zg announce #{items.first.id}")
    end

    if api_request?
      content_type :json
      {:items => items, :tags => tag_objects}.to_json
    else
      flash[:notice] = 'New item added successfully.'
      redirect '/'
    end

  rescue Exception => e

    puts e.message.to_s
    puts e.backtrace

    if e.class == DuplicateError and not tags.empty?
      # add the tags incase there some new one:
      item = Item.get e.id
      item.add_tags(tags) if item #errm
    end

    if api_request?
      content_type :json
      {:items => items, :tags => tag_objects, :error => e.message}.to_json
    else
      raise e # let the error handler handle the error
    end

  end
end

get '/:id' do
  pass unless params[:id].match /^\d+$/
  @item = Item.get(params[:id])
  raise "no item found with id #{params[:id]}" if not @item

  if api_request? 
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

  user_id = nil
  user_id = current_user.id if logged_in?

  if not user_id
    raise 'you need to login to upvote'
  end

  if params[:remove] == 'true'
    upvote = Upvote.all(:item => item, :conditions => ['dm_user_id = ?', user_id])
    raise 'upvote not found!' if not upvote
    if upvote.destroy
      if api_request? 
        content_type :json
        return {:id => item_id, :upvotes => Upvote.count(:item => item)}.to_json
      else
        flash[:notice] = 'Upvote removed.'
        redirect '/'
        return
      end
    else
      raise 'upvote not removed, error occured'
    end
  end

  # upvote only once:
  if Upvote.count(:item => item, :conditions => ['dm_user_id = ?', user_id]) > 0
    raise 'you cannot upvote twice'
  end

  upvote = Upvote.new(:item => item, 
                      :dm_user_id => user_id) 
  if upvote.save
    if api_request?
      content_type :json
      return {:item_id => item_id, :upvotes => Upvote.count(:item => item)}.to_json
    else
      flash[:notice] = 'Item upvoted.'
      redirect '/'
    end
  else
    raise 'upvote error: ' + upvote.errors.full_messages.inspect
  end
end

# adds or removes tags from an item
post '/update' do
  id = params[:id]
  add_tags = (params[:add_tags] || '').split(',')
  del_tags = (params[:del_tags] || '').split(',')

  # get the item to edit
  @item = Item.get(id)
  raise "item with id #{id} not found!" if not @item

  # add tags (create them if not exists)
  added_tags = @item.add_tags(add_tags)
  deleted_tags = @item.del_tags(del_tags)

  if api_request?
    content_type :json
    {:item => @item, :tags => @item.tags}.to_json
  else
    redirect '/'
  end
end

post '/delete' do
  item = Item.get(params[:id])
  raise 'item not found' if not item
  if item.dm_user_id == current_user.id or current_user.admin?
    item.destroy
    if api_request?
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

get '/api_secret/?:regenerate?' do
  if not logged_in?
    redirect '/login'
  end

  user = current_user.db_instance
  if not user.api_secret or params[:regenerate]
    @api_secret = random_token 48
    user.update({:api_secret => @api_secret})
  else
    @api_secret = user.api_secret
  end
  @redirect = params[:redirect]

  if api_request?
    content_type :json
    {email: user.email, api_secret: @api_secret}.to_json
  else
    haml :api_secret
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
  if api_request? 
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

