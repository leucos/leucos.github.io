require "rubygems"
require "bundler/setup"
#require "stringex"
require 'rake'
#require 'rdoc'
require 'date'
require 'yaml'
require 'tmpdir'
require 'jekyll'


## -- Config -- ##

posts_dir    = "_posts"    # directory for blog files
new_post_ext = "md"  # default new post file extension when using the new_post task
new_page_ext = "md"  # default new page file extension when using the new_page task
url          = "http://leucos.github.io/blog-iceland/"

desc "Generate blog files"
task :generate do
  Jekyll::Site.new(Jekyll.configuration({
    "source"      => ".",
    "destination" => "_site",
    "url" => url
  })).process
end

desc "Generate blog files for link checking"
task :generate_check do
  Jekyll::Site.new(Jekyll.configuration({
    "source"      => ".",
    "destination" => "_site",
    "url" => "http://127.0.0.1:4000",
    "owner" => { "facebook" => nil }
  })).process
end

desc "Checks links"
task :check => [:generate_check] do
  system "check-links ./_site/"  
end

desc "Generate and publish blog to gh-pages"
task :publish do
  Dir.mktmpdir do |tmp|
    system "jgd"
  end
end
task :deploy => :publish
task :default => :publish

