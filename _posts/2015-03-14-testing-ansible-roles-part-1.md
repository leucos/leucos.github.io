---
layout: post
title: Testing Ansible roles, part 1
excerpt: "Testing Ansible roles, TDD style, with rolespec, Vagrant and Guard: creating a basic nginx role"
tags: [ansible, tdd, rolespec, guard, vagrant]
modified: 
comments: true
---

[RoleSpec](https://github.com/nickjj/rolespec/) does a great job helping out
testing your roles. It is maintained and used primarily to test the
[debops](https://github.com/debops/debops) role suite. RoleSpec handles all the
boiler plate to run tests (installing the right version of Ansible, adjusting
paths, taking care of the inventory, wrapping your role in a playbook, ...) and
privides a simple DSL to write tests.

However, in its current state, RoleSpec is mostly intended to run a test suite
on travis. And this test suite is separated from your role.

I personally prefer to have my role tests along the Ansible role, in a `tests` directory.

We see below how we can achieve this with RoleSpec, and will leverage Vagrant
for this. We'll also use Guard to continuously test our role while writing it.

## A simple role

Let's start by creating a simple nginx role:

{% highlight bash %}

mkdir -p ansible-nginx/{defaults,handlers,tasks,templates,tests/ansible-nginx/inventory}

{% endhighlight %}

The `tests` directory will be sued for our tests later.

If you already have a role want to convert it, create the `tests/ansible-
nginx/inventory` file and skip straight to 
[part 2]({% post_url 2015-03-15-testing-ansible-roles-part-2 %}).

### Defaults

In `default/main.yml`, we'll declare a few default values for our role. We won't do much,
in our role, just install nginx and set a few variables, so let's keep this
simple:

{% highlight yaml %}

nginx_root: /var/lib/nginx/
nginx_worker_connections: 1024
nginx_ie8_support: yes
nginx_port: 80

{% endhighlight %}

### Handlers

For the handlers part, `handlers/main.yml` will contain a basic restart handler, followed by a port check for good measure:

{% highlight yaml %}
{% raw %}

- name: Restart nginx
  action: service name=nginx state=restarted
  notify: Check nginx

- name: Check nginx
  wait_for: port={{ nginx_port }} delay=5 timeout=10

{% endraw %}
{% endhighlight %}

### Tasks

Now the task part. I always put my tasks in a separate file, and include this
file from `main.yml`. This trick will allow you to set a tag for the whole
included file, like so:

{% highlight yaml %}
{% raw %}

- include: nginx.yml tags=nginx

{% endraw %}
{% endhighlight %}

And then, in `nginx.yml`, put the real tasks:

{% highlight yaml %}
{% raw %}

- name: Adds nginx ppa
  apt_repository:
    repo=ppa:nginx/stable

- name: Adds PPA key
  apt_key: 
    url=http://keyserver.ubuntu.com:11371/pks/lookup?op=get&search=0x00A6F0A3C300EE8C
    state=present

- name: Installs nginx
  apt:
    pkg=nginx-full
    state=latest

- name: Writes nginx.conf
  template: 
    src="../templates/nginx.conf.j2"
    dest=/etc/nginx/nginx.conf
    validate='nginx -tc %s'
  notify:
  - Restart nginx

- name: Replaces nginx default server
  template:
    src="../templates/default.j2"
    dest=/etc/nginx/sites-available/default
  notify:
    - Restart nginx

{% endraw %}
{% endhighlight %}

### Templates

We just need to add 2 templates, and our role will be ready. The first one is the main `nginx.conf.j2` file:

{% highlight yaml %}
{% raw %}

user www-data;
worker_processes {{ ansible_processor_count }};

pid         /var/run/nginx.pid;

events {
    worker_connections {{ nginx_worker_connections }};
    # multi_accept on;
}

http {
    ##
    # Basic Settings
    ##
    sendfile    on;
    tcp_nopush  on;
    tcp_nodelay on;

    # SSL stuff
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;

{% if nginx_ie8_support %}
    ssl_ciphers "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4";
{% else %}
    ssl_ciphers "EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EECDH+aRSA+SHA256:EECDH+aRSA+RC4:EECDH:EDH+aRSA:!RC4:!aNULL:!eNULL:!LOW:!3DES:!MD5:!EXPORT:!PSK:!SRP:!DSS";
{% endif %}

    ssl_session_cache shared:SSL:32m;
    ssl_buffer_size 8k;
    ssl_session_timeout 10m;

    keepalive_timeout     65;
    types_hash_max_size 2048;

    server_tokens off;

    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    ##
    # Gzip Settings
    ##
    gzip on;
    gzip_disable "msie6";
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_types  application/javascript 
                application/json 
                application/x-javascript 
                application/xml 
                application/xml+rss 
                image/svg+xml
                text/css 
                text/plain
                text/xml 
                text/javascript;

    ##
    # If HTTPS, then set a variable so it can be passed along.
    ##
    map $scheme $server_https {
        default off;
        https on;
    }

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

{% endraw %}
{% endhighlight %}

The file is a bit long, but it just contains basic settings. Note that we're
aligning the number of worker processes to the number of processors reported by
Ansible for the host.

We are also switching cipher suites depending on whether we want to support IE8
or not.

Then, we just add a default virtualhost on our server:

{% highlight nginx %}
{% raw %}

server {
  listen {{ nginx_port }}; ## listen for ipv4; this line is default and implied

  root {{ nginx_root }};
  index index.html index.htm;

  # Make site accessible from http://localhost/
  server_name _;

  location / {
    try_files $uri $uri/ /index.php?q=$uri&$args;
  }

  error_page 404 /404.html;

  # redirect server error pages to the static page /50x.html
  #
  error_page 500 502 503 504 /50x.html;
  location = /50x.html {
    root /usr/share/nginx/html/;
  }

  # deny access to .htaccess files, if Apache's document root
  # concurs with nginx's one
  #
  location ~ /\.ht {
    deny all;
  }
}

{% endraw %}
{% endhighlight %}

Our role is now ready. We can now setup the tooling for our tests as explained in [part 2]({% post_url 2015-03-15-testing-ansible-roles-part-2 %})


