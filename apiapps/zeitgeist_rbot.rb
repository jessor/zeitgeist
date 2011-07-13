# debug __FILE__
# require './zeitgeist_api.rb'

module ::Zeitgeist

  # stack with recently added items via irc, does not store items
  # added via web, thus relative offsets only affects these items 
  class ItemHistory
    def initialize
      @items = []
      @max_size = 100
    end

    # make sure item is new otherwise old item will be overwritten (by id)
    def <<(item)
      debug "<<(#{item.inspect})"
      return if not item or item.class != Item
      while @items.length > @max_size
       @items.shift
      end
      debug "history size: #{@items.length}"

      @items.each_index do |i|
        if item.id == @items[i].id 
          @items[i] = item 
          return
        end
      end

      @items << item
    end

    def by_id_or_offset(id) 
      debug "by_id_or_offset(#{id})"
      if id < 0
        by_offset id
      else
        by_id id
      end
    end

    def by_id(id)
      @items.each do |item|
        return item if item.id == id
      end
      return nil
    end

    def delete_by_id(id)
      @items.delete by_id(id)
    end

    def by_offset(offset)
      @items[offset]
    end

    def length
      @items.length
    end
  end

end # Zeitgeist module

class ZeitgeistBotPlugin < Plugin
  #
  # patterns used to match public channel messages for urls etc.
  #
  
  # ignore messages altogether that match with this
  PATTERN_OPT_OUT = /^(#|\/\/|\/\*)/

  # scan messages for urls by this pattern
  PATTERN_LISTEN_URL = %r{(http[s]?://[^ \)\}\]]+)}

  # match messages (that include urls) for tags list with this pattern
  # match groups: tags list (see self.parse_tags_list)
  PATTERN_LISTEN_TAGS = %{^[^#]+[#] ([^#]+)(#[^#]*)?$}

  # parse messages for operators with this pattern
  # match groups: item offset or id (default: -1), tags list (optional)
  PATTERN_LISTEN_OP = %r{^\.?(\^|~|zg)(-?[0-9]+)? ?(.*)?$}

  MORON_PATTERNS = [/^\^\^/]

  Config.register(Config::StringValue.new('zeitgeist.base_url',
      :default => 'http://localhost/',
      :desc => 'Url to zeitgeist installation.'))
  Config.register(Config::StringValue.new('zeitgeist.api_secret',
      :default => 'changeme',
      :desc => 'Secret API key to allow to delete tags.')) # may change in future
  Config.register(Config::ArrayValue.new('zeitgeist.listen_channels',
      :default => [], :desc => 'Channels the bot should listen for urls'))
  Config.register(Config::ArrayValue.new('zeitgeist.log_destination',
      :default => [], :desc => 'Channels or nicks the bot should sent listen log messages'))

  def initialize
    super
    registry_load
    @api = Zeitgeist::ZeitgeistAPI.new(@bot.config['zeitgeist.base_url'],
                                       @bot.config['zeitgeist.api_secret'])
  end

  def help(plugin, topic='')
    domain = URI.parse(@bot.config['zeitgeist.base_url']).host
    case topic

    when 'get'
      "zg get <index or id>: show some item information (default: -1, last in channel history)"
    when 'add'
      "zg add <URL> <tags>: add url using (optional) tags"
    when 'tag'
      "zg tag <index or id> <tags>: add or remove tags from selected item (default for index: -1, last in channel history)"
    when 'op'
     "shortcut to view and tag items:" \
      "  [zg,~ or ^][offset or id] [tags] " \
      "default offset -1 (last in channel): " \
      "show some infos, (if specified) tags are added or deleted from the selected item" \
      " (you need to opt-in to use the '~' and '^' shortcuts! use '.zg short-opt-in' or '.zg short-opt-out')"
    else
      "[help zg <topic>] " + domain + " irc interface:" \
        " help topics: get|add|tag|op" \
      " (notes: comma separate multiple tags | tags are case-insensitive | " \
      "use -foo to delete a tag named foo | offsets (negative id) is valid for current channel only)" \
      " channel messages (#{@bot.config['zeitgeist.listen_channels'].join ','}) that include links are submitted as new" \
      " (notes: to opt-out this, start message with '#' | succeed a link by '# tags' to create " \
      "with tags)"
    end
  end

  def registry_load
    if not @registry.has_key? :zeitgeist_registry
      debug "initialize empty registry"
    else
      registry_data = @registry[:zeitgeist_registry]
      debug "read existing registry data" # : #{registry.length}"
      # registry_data = YAML::load(registry)
      @source_history = registry_data['source_history']
      @allow_noaddress = registry_data['allow_noaddress']
    end


    if not @source_history
      @source_history = {}
    end
    if not @allow_noaddress
      @allow_noaddress = []
    end

  end

  def save
    registry = {
      'source_history' => @source_history,
      'allow_noaddress' => @allow_noaddress
    }
    serialized = YAML::dump(registry)
    debug "save registry data: #{serialized.length}"
    @registry[:zeitgeist_registry] = registry # serialized
  end

  #
  # public bot commands
  #
  def cmd_item_new(m, params)
    url, tags = params[:url], params[:tags].join(' ')
    m.reply item_new(m.channel || m.source, url, tags, m.source.nick)
  end

  def cmd_item_del(m, params)
    id = params[:id]
    say_log(m, 'delete log id: ' + id)
    m.reply item_del(m.channel || m.source, id, m.source.nick)
  end

  def cmd_item_tags_edit(m, params)
    id, tags = params[:index].to_i, params[:tags].join(' ')
    m.reply item_tags_edit(m.channel || m.source, id, tags)
  end

  def cmd_item_get(m, params)
    id = params[:index].to_i
    m.reply item_get(m.channel || m.source, id)
  end

  def cmd_allow_noaddress_show(m, params)
    if @allow_noaddress.empty?
      m.reply 'nobody'
    else
      m.reply @allow_noaddress.join ', '
    end
  end

  def cmd_allow_noaddress_add(m, params)
    from = m.source.to_s
    return if @allow_noaddress.include? from
    m.reply "now you can use the shortcuts ~ and ^"
    @allow_noaddress = [] if not @allow_noaddress or @allow_noaddress.class != Array
    @allow_noaddress << from
  end

  def cmd_allow_noaddress_remove(m, params)
    from = m.source.to_s
    m.reply "opt-out complete, just use zg for op commands"
    @allow_noaddress.delete from
  end

  # listens to all messages in channel list for new urls to 
  # add or operators to edit item tags. 
  def message(m, dummy=nil)
    response = nil
    return if m.address? or not @bot.config['zeitgeist.listen_channels'].include? m.channel.to_s

    message = m.message.strip
    channel = m.channel.to_s
    source = m.source.to_s

    # opt-out this message
    if message =~ PATTERN_OPT_OUT
      debug "opt-out message [#{source}/#{channel}] #{message}"
      return
    end

    # scan message for links ...
    urls = message.scan(PATTERN_LISTEN_URL)
    debug "message (#{message}) pattern match PATTERN_LISTEN_URL: #{urls.inspect}"
    urls.each do |url|
      # ... and tags:
      if urls.length == 1 and message.match PATTERN_LISTEN_TAGS
        debug "message (#{message}) pattern match PATTERN_LISTEN_TAGS: #{$1}"
        tags = $1
      end

      response = item_new(channel, url, tags, source) 

      debug "[#{source}/#{channel}] #{response}"

      return if response =~ /no image signature found/

      if response =~ /Duplicate/
        # .blame/lart?
      end
    end

    # and we propably don't want any of these
    MORON_PATTERNS.each do |pattern|
      return if message.match pattern
    end

    # parse op
    if message.match PATTERN_LISTEN_OP
      if $1 != 'zg' and not @allow_noaddress.include? source
        debug "no opt-in! ignore short syntax"
        return
      end

      offset_or_id = $2 ? $2.strip : ''
      tags = $3 ? $3.strip : ''
      offset_or_id = -1 if offset_or_id.empty?
      offset_or_id = offset_or_id.to_i if offset_or_id.class == String

      debug "op [#{channel}/#{source}] off/id:#{offset_or_id} tags:#{tags.inspect}"

      if tags.empty? # get item 
        response = item_get(channel, offset_or_id)
        if not response =~ /Error:/
          m.reply response
        end
      else
        response = item_tags_edit(channel, offset_or_id, tags)
        if response =~ /no item found/
          m.reply 'item not found, sorry'
        #else
        #  m.reply response
        end
      end
      response = nil # no need to log

    end

    say_log(m, response)

  end

  private

  def say_log(m, log)
    return if not log
    channel = m.channel.to_s
    source = m.source.to_s
    @bot.config['zeitgeist.log_destination'].each do |dest|
      @bot.say(dest, "[#{source}/#{channel}] #{log}") 
    end
  end

  def item_new(source, url, tags, nick)
    history = history_by_source source
    begin
      item = Zeitgeist::Item::new_create(@api, url, tags)
      history << item
      return item.to_s
    rescue Exception => e
      debug e.inspect
      debug $@.join "\n"
      return e.message
    end
  end

  def item_del(source, id, nick)
    history = history_by_source source
    begin
      response = @api.item_delete(id)
      if response.has_key? 'error'
        return response['error']
      else
        # delete from history:
        history.delete_by_id id
        return "deleted item ##{id}"
      end
    rescue Exception => e
      debug e.inspect
      debug $@.join "\n"
      return e.message
    end
  end

  def item_tags_edit(source, id, tags)
    history = history_by_source source
    item = history.by_id_or_offset(id)
    if item
      item_or_id = item.id
    else
      item_or_id = id
    end
    return 'not in history, use item id' if item_or_id < 0

    add, del = parse_tags_list(tags)
    debug "zeitgeist add/delete tags: add:#{add.inspect} del:#{del.inspect}"

    begin
      item = Zeitgeist::Item::edit_tags(@api, item_or_id, add, del)
      history << item # NOTE: this may overwrite old items based on their id!
      return "##{item.id} tags: " + item.tags.join(', ')
    rescue Exception => e
      debug e.inspect
      debug $@.join "\n"
      return e.message
    end
  end
  
  def item_get(source, id)
    history = history_by_source source
    if not (item = history.by_id_or_offset(id))
      begin
        return 'not in history, use item id' if id < 0
        item = Zeitgeist::Item::new_existing(@api, id)
        history << item
        return item.to_s
      rescue Exception => e
        debug e.inspect
        debug $@.join "\n"
        return e.message
      end
    else
      item = Zeitgeist::Item::new_existing(@api, item.id)
      return item.to_s
    end
  end

  def history_by_source(source)
    if not @source_history.has_key? source
      @source_history[source] = Zeitgeist::ItemHistory.new
    end
    @source_history[source] 
  end

  def parse_tags_list(tags)
    add = []
    del = []

    tags.downcase!
    tags.split(',').each do |tag|
      tag.strip!
      next if tag.empty?
      if tag.match /^([\-|+]?)(.*)$/
        next if not $2 or $2.empty?

        if $1 == '-'
          del << $2.strip
        else
          add << $2.strip
        end
      end
    end
    [add, del]
  end


end


plugin = ZeitgeistBotPlugin.new

plugin.default_auth('del', false)

plugin.map('zg get :index', 
           :threaded => true, 
           :action => 'cmd_item_get')
plugin.map('zg add :url [*tags]', 
           :defaults => {:tags => ''},
           :threaded => true, 
           :action => 'cmd_item_new')
plugin.map('zg del :id', 
           :threaded => true, 
           :auth_path => 'del',
           :action => 'cmd_item_del')
plugin.map('zg tag [:index] *tags', 
           :threaded => true, 
           :defaults => {:index => -1},
           :action => 'cmd_item_tags_edit')

plugin.map('zg short-opt-show', :action => 'cmd_allow_noaddress_show') 
plugin.map('zg short-opt-in', :action => 'cmd_allow_noaddress_add') 
plugin.map('zg short-opt-out', :action => 'cmd_allow_noaddress_remove') 




