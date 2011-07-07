xml.instruct! :xml, :version => "1.0"
xml.rss :version => "2.0" do
	xml.channel do
		xml.title "#{settings.pagetitle}"
		xml.description "#{settings.pagedesc}"
		xml.link request.url.chomp request.path_info

		@items.each do |item|
			xml.item do
				xml.title item.name ? item.name : item.image
				xml.link "#{request.url.chomp request.path_info}#{item.image}"
				xml.guid "#{request.url.chomp request.path_info}#{item.image}"
				xml.pubDate Time.parse(item.created_at.to_s).rfc822
                if item.tags and item.tags.length > 0
                  xml.description item.tags.map { |tag| tag.tagname }.join ', '
                else
                  xml.description item.name
                end
			end
		end

	end
end
