xml.instruct! :xml, :version => "1.0"
xml.rss :version => "2.0" do
	xml.channel do
		xml.title "#{settings.pagetitle}"
		xml.description "#{settings.pagedesc}"
		xml.link request.url.chomp request.path_info

		@items.each do |item|
			xml.item do
				xml.title item.name
				xml.link "#{request.url.chomp request.path_info}/#{settings.assetpath}/#{item.name}"
				xml.guid "#{request.url.chomp request.path_info}/#{settings.assetpath}/#{item.name}"
				xml.pubDate Time.parse(item.created_at.to_s).rfc822
				xml.description item.name
			end
		end

	end
end
