---
layout: post
title: Testing Ansible roles, part 2
excerpt: "Testing Ansible roles, TDD style, with rolespec, Vagrant and Guard"
tags: [ansible, tdd, rolespec, guard, vagrant]
modified: 
comments: true
---

Now that we have created our basic role in [part 1]({% post_url 2015-03-14-testing-ansible-roles-part-1 %}), we need to set-up a Vagrant machine and some tooling to run our tests.

## Creating the Vagrant machine

To run our tests in a Vagrant machine, we need to create a `Vagrantfile`. We'll create it in our role top directory:

{% highlight ruby %}
{% raw %}

Vagrant.configure(2) do |config|
  config.vm.box = "ubuntu/trusty64"
  config.vm.define "nginx" do |nginx|
  end
  config.vm.provision "shell",
    :path => "vagrant_specs.sh",
    :upload_path => "/home/vagrant/specs",
    # change role name below
    :args => "--install ansible-nginx"
end

{% endraw %}
{% endhighlight %}

You can change `config.vm.box` to another Vagrant box that better suits your
needs. We'll provision this machine with a shell script (not with Ansible, so we
don't end up in an inception style situation).

The provisionning script, `vagrant_specs.sh` serves two purposes:

1. it takes care of installing RoleSpec and setting up the test directory when
called with `--install`. This happens only at vagrant provisionning time (e.g.
`vagrant up` of `vagrant provision`)
2. it can be called to run the test suite; to make invocation easier, it will copy itself to `/usr/local/bin/specs`

Create the `vagrant_specs.sh` with the following content:

{% highlight bash %}

#!/bin/bash
#
# Vagrant provisionning script
#
# Usage for provisionning VM & running (in Vagrant file):
# 
# script.sh --install <role>
#
# e.g. : 
# script.sh --install ansible-nginx
# 
# Usage for running only (from host):
#
# vagrant ssh -c specs
#
if [ "x$1" == "x--install" ]; then
  mv ~vagrant/specs /usr/local/bin/specs
  chmod 755 /usr/local/bin/specs
  sudo apt-get install -qqy git
  su vagrant -c 'git clone --depth 1 https://github.com/nickjj/rolespec'
  cd ~vagrant/rolespec && make install
  su vagrant -c 'rolespec -i ~/testdir'
  su vagrant -c "ln -s /vagrant/ ~/testdir/roles/$2"
  su vagrant -c "ln -s /vagrant/tests/$2/ ~/testdir/tests/"
  exit
fi

cd ~vagrant/testdir && rolespec -r $(ls roles)

{% endhighlight %}

Now, let's check this ! It might take a while if you don't already have the
vagrant image on your box:


    $ vagrant up
    Bringing machine 'nginx' up with 'virtualbox' provider...
    ==> nginx: Importing base box 'ubuntu/trusty64'...
    ==> nginx: Matching MAC address for NAT networking...
    ==> nginx: Checking if box 'ubuntu/trusty64' is up to date...
    ==> nginx: Setting the name of the VM: ansible-nginx_nginx_1426331325901_88232
    ...
    ==> nginx: Cloning into 'rolespec'...
    ==> nginx: Installing RoleSpec scripts in /usr/local/bin ...
    ==> nginx: Installing RoleSpec libs in /usr/local/lib/rolespec ...
    ==> nginx: Initialized new RoleSpec directory in /home/vagrant/testdir
    $


## Creating tests

We're almost done. Only two files left to create. First, we RoleSpec needs an inventory. Nothing fancy here, we just need to create an inventory file with a single host, `placeholder_fqdn`, RoleSpec will take care of the rest:

{% highlight bash %}

$ echo "placeholder_fqdn" > tests/ansible-nginx/inventory/hosts

{% endhighlight %}

And finally, we need a test file, where we can check if our playbook works. We can check the syntax, the idempotency, the resulting templates, etc...

This test file is simply a bash script, in whch we include some RoleSpec files to get ccess to its DSL.

Let's start with a simple one, and create `tests/ansible-nginx/test` with the followjng content:

{% highlight bash %}
#!/bin/bash
# -*- bash -*-

# This gives you access to the custom DSL
. "${ROLESPEC_LIB}/main"

# Install a specific version of Ansible
install_ansible "v1.8.3"

# Check syntax first, and then that the playbook runs
assert_playbook_runs

# Check that the playbook is idempotent
assert_playbook_idempotent

{% endhighlight %}

## Runing tests

Our simple tests are setup. To run them, we need to execute
`/usr/local/bin/specs` in the Vagrant host.

{% highlight bash %}
vagrant ssh -c 'specs'
{% endhighlight %}

RoleSpecs will then download Ansible (version 1.8.3 since this is what we
asked), install it, and run our test case.

<script type="text/javascript" src="https://asciinema.org/a/17711.js" id="asciicast-17711" async></script>

As you can see in the recording, RoleSpec:

- installs Ansible (`ROLESPEC: [Install Ansible - v1.8.3]`)
- executes the playbook with `assert_playbook_runs` (`TEST: [Run playbook syntax check]` and `TEST: [Run playbook]`)
- check that the playbook is idempotent with `assert_playbook_idempotent` ('TEST: [Re-run playbook]')

Pretty neat !

There is one downside though: it takes almost 3 minutes to run. However, you can
speed up subsequent runs as long as you don't have to change the Ansible
version: since Ansible is already installed, there is no need to install it
again every time. Using the `-p` option will run in _playbook mode_, which means
it will only run `assert_playbook_runs` test.

{% highlight bash %}
vagrant ssh -c 'specs'
{% endhighlight %}

<script type="text/javascript" src="https://asciinema.org/a/17712.js" id="asciicast-17712" async></script>

25 seconds only, we cut the runtime by twelve, not bad.

## Local continuous integration

Now that we have reasonable playbook test run time, we can add local continuous integration to our setup.
We will use [Guard](https://github.com/guard/guard) for this.

Assuming you have a ruby environment setup, just install `guard` and `guard-shell` gems.

{% highlight bash %}
gem install guard guard-shell --no-ri --no-rdoc
{% endhighlight %}

Then create a `Guardfile` in the roles top directory, with the following content:

{% highlight ruby %}
# -- -*- mode: ruby; -*-
guard :shell do
  watch(%r{^(?!tests).*/.*\.yml$}) do |m|
    puts "#{m[0]} changed - running tests"
    system('vagrant ssh -c "specs -p"')
  end
end
{% endhighlight %}

This file will ask `guard` to execute `vagrant ssh -c "specs -p"` everytime it
detects a change in a file ending with `.yml` in the project's subdirectories.
Note that we excluded the `tests` directory since it contains somewhere a
`test.yml` playbook file generated by RoleSpec at run time. If we don't exclude
it from the guard watch, the test will loop forever.

Now run `guard`, change a file (.e.g. `touch tasks/main.yml`), and see what happens.

In the next part, we will add TravicCI configuration so tests are run when we push
our role on GitHub.


