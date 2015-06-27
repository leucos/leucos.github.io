---
layout: post
title: "Decoupling your Ansible roles"
excerpt: Stay sane, decouple your Ansible roles
category: 
tags: ansible
permalink: decoupling-your-ansible-roles
---

Having tightly coupled role is the best way to have a hard time
maintaining roles and playbooks, and live in fear of changing anything
in them.

Here is a journey into role decoupling.

## The problem

Let say we have a role (_my\_app_) that depend on _php-fpm_ role. In the php-fpm
role, we want to display errors in HTML output depending on the application
running environment (e.g. always display unless we're running in production
environment).

The application running environment is available in `myapp_environment`.

## First idea

The first idea that comes to mind is to change the php.ini according to
`myapp_environment`, like so:
    
    {% raw %}
    {% if myapp_environment == "production" %}
    display_errors = Off
    {% else %}
    display_errors = On
    {% endif %}
    {% endraw %}

The problem with this approach if that php-fpm role now needs
`myapp_environment` to be defined, which is quite absurd.

So instead, you could rename the variable `environment`, and use this in
both roles (`myapp` and `php-fpm`). This is better, but not much. The
problem with this approach is that a plain `environment` variable is not
linked (by it's name) to any role, and this can lead to great confusion
is it is used and set in many roles or in different places in the
inventory.

## Another try

So the best way is to have two variables, `php_fpm_environment`, which is
meaningful, and `myapp_environment`. But now how can I sync them together ?

One ways is to match them in your inventory, like so :

    # Somewhere in inventory
    myapp_environment = "production"
    php_fpm_environment = {% raw %}{{ myapp_environment }}{% endraw %}

However, this has some drawbacks. For instance, we are still talking about
`php_fpm_environment` and, while not a big deal, it has no php-fpm
meaning per se and it is not obvious what this variable does.

Also, in the `php.ini` template, we will still have to test against the string
"production" to set `display_errors`. Testing against a string set somewhere
else is quite dangerous. What is the production name for the app is "live"
instead ? Our php-fpm role is broken now.

## Some progress

We could go a better way: let's call the variable `php_fpm_display_error` (more
meaningful) and make it a boolean. We now can do this :

    {% raw %}
    {% if php_fpm_display_errors %}
    display_errors = On
    {% else %}
    display_errors = Off
    {% endif %}
    {% endraw %}

and somewhere in inventory:

    myapp_environment = "production"
    {% raw %}php_fpm_display_errors = {{ myapp_environment =="production"  }}{% endraw %}


## Streamlining our solution

Well, this is better now. But it is not perfect. The inventory is more verbose
than required and handles something that it shouldn't have to take care
of. It is also quite easy to forget add it to the inventory and end up
with errors showing in production.

By moving this logic away from the inventory, and directly in the role
dependencies, this configuration setting becomes completely transparent. We
just have to add the following lines in `myapp/meta/main.yml`:

{% highlight yaml %}
dependencies:
  - role: role-php-fpm
    {% raw %}php_fpm_display_errors: {{ myapp_environment == "production" }}{% endraw %}
{% endhighlight %}

Now, php-fpm role is completely decoupled from myapp role, and the production
setting is completely transparent to the role user. Setting `myapp_environment`
is enough to have the depending role set variables accordingly. You don't even
have to be aware of the `myapp` role dependency. If you swap, let say
nginx/php-fpm for apache/php, you just have to change the role dependency and
have no impact on your inventory. If you want to name your production
environment "live", you can do so by changing `meta/main.yml` and not
touching anything else.

Keeping role decoupled is the best way to have manageable and reusable
roles. Try to make them self sufficient, and avoid cross variables or
even worse, group names in roles !
