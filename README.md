Zeitgeist
=========

You don't need to know what this is just yet.
Workcopy, alpha, do not touch ;)


Dev Env
-------

* fork (on github)
* install rvm and 1.9.2 ruby if you haven't already
* rvm use 1.9.2
* rvm gemset create zeitgeist
* git clone git@github.com:username/zeitgeist.git
* rvm rvmrc trust zeitgeist/.rvmrc
* cd zeitgeist
* gem install bundler && bundle install
* shotgun -E production zeitgeist.rb
* Ignore "DataObjects::URI.new with arguments is deprecated", it's not our bug: https://github.com/datamapper/dm-do-adapter/issues/4
* Send Pull Requests :)


TODO
----

* bookmarklet
* (infinite scrolling)
* admin interface (bowtie?, wind?)
* user models?
* refactoring :D
