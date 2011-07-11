=begin

you can use this api in any ruby application to post urls,
add and delete tags:

api = Zeitgeist::ZeitgeistAPI.new('http://zeitgeist.li/', 'changeme')

# get item:
item = Zeitgeist::Item::new_existing(api, 1234)
item.id
item.type
item.source
item.tags
item.image
item.name
item.size
item.mimetype
item.dimensions

# create new item:
Zeitgeist::Item::new_create(api, 
  'http://example.com/resource/link.png', 
  ['tags', 'to', 'add'])

# add or delete tags:
Zeitgeist::Item::edit_tags(api, 1234, ['add', 'tags'], ['del', 'tags'])

=end

begin
require 'rubygems'
rescue LoadError # ignore
end
require 'mechanize'

module ::Zeitgeist

  # this is likely to change in the future
  class ZeitgeistAPI
    attr_reader :base_url

    def initialize(base_url, api_secret)
      @base_url = base_url
      @api_secret = api_secret
      @agent = nil
    end

    def init_agent
      @agent = Mechanize.new
      @agent.request_headers['X-API-Secret'] = @api_secret
      @agent.max_history = 0
      @agent.redirect_ok = false
      # @agent.keep_alive = false, no longer in effect need to reinit manually now m(
    end

    def item_new(url, tags) # /item/new
      debug "item_new(#{url}, #{tags.inspect})"
      tags = tags.join ',' if tags.class == Array
      url = url.first if url.class == Array
      request(url_builder('new'), {:remote_url => url, :tags => tags})
    end

    def item_tags_edit(id, add, del) # /item/tags/edit
      debug "item_tags_edit(#{id}, #{add.inspect}, #{del.inspect})"
      add = add.join ',' if add.class == Array
      del = del.join ',' if del.class == Array
      request(url_builder('edit', id), {
        :add_tags => add,
        :del_tags => del
      })
    end

    def item_get(id) # /item
      debug "item_get(#{id})"
      request(url_builder('item', id))
    end

    private

    def url_builder(*action)
      debug "url_builder(#{action.inspect})"
      action = action.join '/' if action.class == Array

      "#{@base_url}#{action}"
    end
    
    # makes GET request, POST if data is specified
    def request(url, data = nil, tries = 1)
      init_agent if not @agent
      debug "zeitgeist http request for #{url} and #{data.inspect}" 
      begin
        if data
          page = @agent.post(url, data)
        else
          page = @agent.get(url)
        end
      rescue Exception => e
        debug "zeitgeist app http error (try:#{tries}): (#{e.class}) #{e.message}"
        debug $@.join "\n"

        if tries < 3
          tries+=1
          @agent = nil
          return request(url, data, tries)
        end

        raise e
      else
        if not page.body.empty?
          begin
            response = JSON.parse(page.body)
            debug response.inspect
            return response
          rescue
            debug "zeitgeist response not valid json? #{$!.message}"
            debug $@.join "\n"
            raise $!
          end
        else
          debug 'empty http response from zeitgeist'
          raise Exception.new 'empty http response from zeitgeist'
        end
      end
    end
  end

  class Item
    attr_reader :id, :tags

    #
    # objects of this class may safely be serialized
    #
    def initialize(item)
      item = { 
        'base_url'=>nil,'id'=>nil,'type'=>nil,'source'=>nil,'tags'=>[], 
        'image'=>nil,'name'=>nil,'size'=>nil,'mimetype'=>nil,'dimensions'=>nil
      }.merge(item)
      item.each_pair do |name, value|
        instance_variable_set("@#{name}", value) 
      end

      # split and trim tags
      @tags = @tags.split(',').map { |tag| tag.strip } if @tags.class == String
    end

    def to_s
      if @source and not @source.empty?
        url = @source
      else
        url = "#{@base_url}item/#{@id}"
      end
      if @type == 'image' and @mimetype
        type = @mimetype
      else
        type = @type
      end
      string = "##{@id} [#{type}] #{url}"
      if @size and @dimensions
        string += " [#{'%0.2f' % (@size / 1024.0)} KiB" \
               " #{@dimensions}]"
      end
      if @tags and not @tags.empty?
        string += " tagged: #{@tags.join(', ')}" 
      end

      return string
    end

    #
    # static methods for api interaction
    #

    def self.new_create(api, url, tags = [])
      response = api.item_new(url, tags)
      new_by_api_response(response, api.base_url)
    end

    def self.new_existing(api, id)
      response = api.item_get(id)
      new_by_api_response(response, api.base_url)
    end

    # add or remove tags, return created/updated item
    def self.edit_tags(api, item_or_id, add, del)
      if item_or_id.class == Item
        id = item_or_id.id
      else
        id = item_or_id
      end

      response = api.item_tags_edit(id, add, del)
      self.new_by_api_response(response, api.base_url)
    end

    private

    def self.new_by_api_response(response, base_url)
      if response['error']
        raise Exception.new "API Response Error: #{response['error']}"
      else
        item = response['item']
        item['tags'] = response['tags'].map { |tag| tag['tagname'] }
        item['base_url'] = base_url 
        Item.new(item)
      end
    end

  end

end # Zeitgeist module

