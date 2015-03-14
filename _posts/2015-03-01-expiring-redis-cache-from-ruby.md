---
layout: post
title: Invalidating REDIS cache from Ruby
excerpt: "Using REDIS cursors for cache invalidation"
tags: [redis, ruby, padrino]
modified: 2015-03-01
comments: true
---

## REDIS as Padrino cache

Using REDIS as and application cache is very handy. You can easily use
it in, say, [Padrino](http://www.padrinorb.com/) like this:

[^1]: <http://www.padrinorb.com/>

{% highlight ruby %}

module MyApp
  class App < Padrino::Application
    enable :caching
    set :cache, Padrino::Cache.new( :Redis, 
                                    :host => ENV['REDIS_SERVER'],
                                    :port => ENV['REDIS_PORT'],
                                    :db => 0)
  end
end

MyApp::App.controllers :test do
  get :index, :cache => true do
    cache_key { current_account.email + ":test:index" }
    expires 3600
    @title = "Some page with expensively computed values"
    render 'test/index'
  end
end

{% endhighlight %}

Note that we have a specific cache entry for each user
(`current_account.email`). For instance, a user with email `foo@bar.com`
will have this entry cached at `foo@bar.com:test:index`

## Cache invalidation

Now, sometimes you need to expire the cache forcibly. For instance,
let's say you know you've changed something in the database and that you
don't want stale data to be served, you can invalidate the cache
manually. Or may be you want to invalidate a complete user cache at
login time.

However, this is not easy in our case, since we want to remove all
entries matching `*:test:index` (or `foo@bar.com:*` if we want to
completely wipe out the user cache).

The first idea that comes to mind is to use the Redis `KEYS` command that can
accept globs to match key names, like `KEYS foo@bar.com:*`.

But in the documentation[^1], you'll find a big fat warning about KEYS: 

[^1]: <http://redis.io/commands/KEYS>

> Warning: consider KEYS as a command that should only be used in production
> environments with extreme care. It may ruin performance when it is executed
> against large databases. This command is intended for debugging and special
> operations, such as changing your keyspace layout. Don't use KEYS in your
> regular application code. If you're looking for a way to find keys in a 
> subset of your keyspace, consider using SCAN or sets.

Scary as it sounds.

## Cursors to the rescue

REDIS comes with a nice, but not very known feature since v2.8: SCAN. The SCAN
command is a cursor based iterator. You give him a key pattern, and every time
you call it, it will return the next set of matching keys, and an index for the
next call.

Here is a piece of code that can invalidate key wildcards from padrino :

{% highlight ruby %}

MyApp::App.controllers :test do
  define_method :invalidate_cache_like do |wildcard|
    r = Redis.new(:host => ENV['REDIS_SERVER'], :port => ENV['REDIS_PORT'])
    cursor = nil

    while cursor != "0" do
      cursor, keys = r.scan(cursor||e, { match: wildcard})

      keys.each do |k|
        r.del(k)
      end
    end
  end
end

{% endhighlight %}


You can not easily invalidate a cache wildcard calling
`invalidate_cache_like`. 

For instance, at user login, you could call :

{% highlight ruby %}
`invalidate_cache_like "#{current_account.email}:test:index"
{% endhighlight %}

and the user cache is now cleared.

## Benchmarking

Let's play with `Benchmark` a bit to compare `SCAN` and `KEYS` performance on a
moderately sized database. While we're at it, we'll also check these commands using `redis` and `hiredis` drivers, to see if it makes any difference.

I used the following piece of code for that:

{% highlight ruby %}

#!/bin/env ruby

require 'hiredis'
require 'em-synchrony'
require 'redis'
require 'benchmark'

def build_cache(redis)
  ('aaaa'..'zzzz').each do |s|
    redis.set(s, 1)
  end
end

def invalidate_cache_cursor(redis, wildcard)
  cursor = nil

  while cursor != "0" do
    cursor, keys = redis.scan(cursor||0, { match: wildcard})

    keys.each do |k|
      redis.del(k)
    end
  end
end

def invalidate_cache_keys(redis, wildcard)
  redis.keys(wildcard).each do |k|
    redis.del(k)
  end
end

hiredis = Redis.new(:driver => :hiredis)
redis = Redis.new()

Benchmark.bm(22) do |x|
  [:ruby, :hiredis].each do |d|
    r = Redis.new(:driver => d)
    build_cache(r)
    x.report("looping (#{d}):") {
      ('aaa'..'aaz').each do |l|
        invalidate_cache_keys(r, "#{l}*")
      end
    }
    build_cache(r)
    x.report("scanning (#{d}):") {
      ('aaa'..'aaz').each do |l|
        invalidate_cache_cursor(r, "#{l}*")
      end
    }
  end
end


{% endhighlight %}

After a few minutes running, I got those surprising results:

    $ ./redis-expire-wildcard.rb 
                                user     system      total        real
    looping (ruby):          0.040000   0.010000   0.050000 (  1.059056)
    scanning (ruby):        49.000000  11.490000  60.490000 ( 61.113561)
    looping (hiredis):       0.020000   0.010000   0.030000 (  1.073681)
    scanning (hiredis):     19.680000  12.880000  32.560000 ( 44.972220)

First, there is no much improvements using `hiredis` over `redis` when looping
in our case. This sounds legit, since we loop only 26 times here and the
`hiredis` performance benefit doesn't rise with so few commands (`hiredis` does
a much more better job if you change the tested range so more commands are
issued).

Second, using `SCAN` here is *much* slower than using `KEYS` !

So why use `SCAN` instead of `KEYS` ? The problem with `KEYS` is that it will block your server while retrieving all the keys. The cursor based approach will return small chunks of keys and won't block the server for the time of a whole key scan.

However, handling cursor based expiration can be tricky in a web application.
Since it takes so much longer (but is friendlier to Redis), you might have to
handle it in a separate task from your application process (in Sidekiq for instance).

It all depends on your app. You can start using simply `KEYS`, but will have to
keep in mind that cursors will be needed if usage or concurrent trafic rises and
monitor your Redis statistics for this.


