
require_relative 'zeitgeist.rb'

nsfw_items = Item.all(Item.tags.tagname => 'nsfw')
nsfw_items.update(:nsfw => true)

