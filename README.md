Zeitgeist ![http://stillmaintained.com/jessor/zeitgeist](http://stillmaintained.com/jessor/zeitgeist.png)
=========

Extendable image and media gallery built with [Sinatra](http://www.sinatrarb.com).
See it in action: [zeitgeist.li](http://zeitgeist.li) (deployed with Phusion Passenger)[http://modrails.com/]).
This is work in progress, come and join the fun!


Current Features
----------------

* Upload items or just post the URL
* Non-image URLs currently supported: YouTube, Vimeo, Soundcloud (easily extendable)
* Porn Mode: Use cursor keys in Fancybox, it even switches to the next page for you
* Tags: easily add and filter by tags
* Host images on S3 or Google Storage or locally (CarrierWave)
* IRC Bot for watching URLs posted in channels and adding/removing of tags (not released yet)


Development
-----------

* fork (on github)
* (install [rvm](http://rvm.beginrescueend.com/) and use the 1.9.2 ruby)
* rvm use 1.9.2
* rvm gemset create zeitgeist
* git clone git@github.com:username/zeitgeist.git
* rvm rvmrc trust zeitgeist/.rvmrc
* cd zeitgeist
* gem install bundler && bundle install
* cp config.yaml.sample config.yaml
* shotgun -E production zeitgeist.rb

Ignore "DataObjects::URI.new with arguments is deprecated", it's not our bug, see [dm-do-adapter/issues/4](https://github.com/datamapper/dm-do-adapter/issues/4)


Licence
-------

Zeitgeist is licensed under the GPLv2+. Please drop me a line if you use or modify it :)
