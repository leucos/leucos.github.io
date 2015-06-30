---
layout: post
title: Making dynamic inventory usable with Ansible and Digital Ocean
excerpt: "Let's face it, dynamic inventory sucks. Let's fix that."
tags: [ansible, digital ocean]
categories: articles
modified: 2015-05-11
comments: true
---

## The problem

You've been there too. Spinning up droplets on DigitalOcean with Ansible
and using a dynamic inventory script is quite a pain.

Most approaches use the `digital_ocean` ansible module in
playbooks to spin up droplets, along with the `digital_ocean.py` dynamic
inventory script, using this kind of workflow:

- define your droplets in a YAML file (eventually with size, region,
  etc...)
- create a playbook that will loop over droplet list (`with_items` or
  equivalent) and spin up the droplet
- dynamically add started droplets to inventory

This approach has many drawbacks, and, to be honest, is not really usable.

### Slooooooow

First, it is damn slow. Droplet creation is serialized. Since
`digital_ocean` waits for the droplet to come up, and since DO itself
advertizes 'Start your droplet in 55 seconds !', you can do the math.
Starting a single droplet is quite long, so spinning up your multi-tier,
fault-tolerant, distributed architecture will take ages.

You probably can use `async` + `poll` to spin up the droplets. I didn't
try and don't know where this would lead. But you'd still face the other
issues.

### Naming

You droplets won't have real names. They will be known by their IPs.
Sure, if you use the `name` parameter during creation, you might be able
to use it, but at best, this will be a group name.

You could also use `add_host` in your bootstrapping script, but this is
a run time hack, so forget about setting variables in `host_vars`.

Since droplets are mostly nameless, grouping them is hard. Sure, you can
do it at run time with `add_host` too, but you won't leverage
`group_vars` usage.

Anyway, all those run-time naming hacks will force you to loop over all
your droplets definitions, hit DO API to make sure they're alive, then
loop over API responses to add hosts and groups EVERY time you execute a
playbook.

### localhost is forced in

Spinning up instances on DO will require to run the `digital_ocean`
module as a `local_action` or using `delegate_to: localhost`. This means
that you are bound to declare localhost in your inventory. This is a
real pain, since it makes the `all` group mostly unusable, unless you
change all your playbook hosts definitions from `hosts: all` to `hosts:
all:!localhost`. Pretty bad for readability.


Let's stop here, there are already enough reasons to find an alternate
way. There are probably other cons, and certainly pros too for the
dynamic approach, but I fell that this way of doing it is barely usable
for serious, repeatable stuff.

## Alternate aproach

In the end, we would like to work as we do with on-prem hardware: have a
static inventory.

The idea is to create this static inventory first, and then use a
bootstrapping script that will use this inventory as a contract to apply
on DigitalOcean.

The script will list all hosts in your inventory (using `ansible
--list-hosts`), and parallelize droplet creation on digital ocean.

When all droplets are created, it will create a complementary inventory
file in your inventory directory containing hosts with their respective
IPs.

At this point, you have a perfectly static inventory, and can run your
ansible playbook normally, without hitting external APIs (serialized),
without naming problems, ... Things are just _normal_, fast and
reliable, without edge cases introduced by dynamic inventories.

Using this approach on a 8 droplets setup, the time to set-up instances
went from 9'33" down to 1'56". And the time to destroy instances went
from 0'55" down to 0'3" (see demo below). Of course, more droplets, 
more gain.

And these are just create/destroy gains. You also benefit from static
inventory for all your lifecycle playbook runs, since you never hit DO API and
don't have to build inventory at run time, which is always slower despite the
inventory cache.

### Example

Assuming you have an inventory directory in `inventories/devel/`,
containing a `hosts` file, you can spin up your droplets like this:

{% highlight bash %}
do_boot.sh inventories/devel/
{% endhighlight %}

When you're finished with your infrastructure, call the same command with
the `deleted` parameter:

{% highlight bash %}
do_boot.sh inventories/devel/ deleted
{% endhighlight %}

That's all.

The script has defaults regarding droplet size, region, image and ssh
key. You can change the defaults in the script to something that suits you, and
override these defaults per droplet in your inventory:

{% highlight yaml %}
[www]
www1
www2
www3 do_region=2

[database]
db1 do_size=62 do_image=12345

[redis]
redis1

[elastic]
elastic1 do_size=60
{% endhighlight %}

###Spinning up and down 8 droplets in 2'15"

<script type="text/javascript" src="https://asciinema.org/a/19479.js" id="asciicast-19479" async></script>

## Script

You can grab the script in this [gist](https://gist.github.com/leucos/6f8d93de3493431acd29).

__UPDATE:__ if you run Ansible v2.0+, use [this script
instead](https://gist.github.com/leucos/2c361f7d4767f8aea6dd). It will
use the new digital Ocean API (v2.0 too). You just need to set
`DO_API_TOKEN`.

{% highlight bash %}
#!/bin/bash
#
# Change defaults below
# ---------------------
#
# Digital Ocean default values
# You can override them using do_something in your inventory file
# Example:
# 
# [www]
# www1 do_size=62 do_image=12345
# ...
#
# If you don't override in your inventory, the defaults below will apply
DEFAULT_SIZE=66       # 512mb (override with do_size)
DEFAULT_REGION=5      # ams2 (override with do_region)
DEFAULT_IMAGE=9801950 # Ubuntu 14.04 x64 (override with do_image)
DEFAULT_KEY=785648    # SSH key, change this ! (override with do_key)

# localhost entry for temporary inventory
# This is a temp inventory generated to start the DO droplets
# You might want to change ansible_python_interpreter
LOCALHOST_ENTRY="localhost ansible_python_interpreter=/usr/bin/python2" 

# Set state to present by default
STATE=${2:-"present"}

# digital_ocean module command to use
# name, size, region, image and key will be filled automatically
COMMAND="state=$STATE command=droplet private_networking=yes unique_name=yes"
# ---------------------

function bail_out {
  echo $1
  echo -e "Usage: $0 <inventory_directory> [present|deleted]\n"
  echo -e "\tinventory_directory: the directory containing the inventory goal (compulsory)"
  echo -e "\tpresent: the droplet will be created if it doesn't exist (default)"
  echo -e "\tdeleted: the droplet will be destroyed if it exists"
  exit 1
}

# Check that inventory is a directory
# We need this since we generate a complementary inventory with IP addresses for hosts
INVENTORY=$1
[[ ! -d "$INVENTORY" ]]  && bail_out "Inventory does not exist, is not a
directory, or is not set"
[[ ! -e $DO_CLIENT_ID ]] || bail_out "DO_CLIENT_ID not set"
[[ ! -e $DO_API_KEY ]]   || bail_out "DO_API_KEY not set"

# Get a list of hosts from inventory dir
HOSTS=$(ansible -i $1 --list-hosts all | awk '{ print $1 }' | tr '\n' ' ')

# Clean up previously generated inventory
rm $INVENTORY/generated

# Creating temporary inventory with only localhost in it
TEMP_INVENTORY=$(mktemp)
echo Creating temporary inventory in $TEMP_INVENTORY
echo $LOCALHOST > $TEMP_INVENTORY

# Create droplets in //
for i in $HOSTS; do 
  SIZE=$(grep $i $1/hosts | grep do_size | sed -e 's/.*do_size=\(\d*\)/\1/')
  REGION=$(grep $i $1/hosts | grep do_region | sed -e 's/.*do_region=\(\d*\)/\1/')
  IMAGE=$(grep $i $1/hosts | grep do_image | sed -e 's/.*do_image=\(\d*\)/\1/')
  KEY=$(grep $i $1/hosts | grep do_key | sed -e 's/.*do_key=\(\d*\)/\1/')

  SIZE=${SIZE:-$DEFAULT_SIZE}
  REGION=${REGION:-$DEFAULT_REGION}
  IMAGE=${IMAGE:-$DEFAULT_IMAGE}
  KEY=${KEY:-$DEFAULT_KEY}

  if [ "${STATE}" == "present" ]; then
    echo "Creating $i of size $SIZE using image $IMAGE in region $REGION with key $KEY"
  else
    echo "Deleting $i"
  fi
  # echo " => $COMMAND name=$i size_id=$SIZE image_id=$IMAGE region_id=$REGION ssh_key_ids=$KEY"
  ansible localhost -c local -i $TEMP_INVENTORY -m digital_ocean \
    -a "$COMMAND name=$i size_id=$SIZE image_id=$IMAGE region_id=$REGION ssh_key_ids=$KEY" &
done

wait

# Now do it again to fill up complementary inventory
if [ "${STATE}" == "present" ]; then
  for i in $HOSTS; do 
    echo Checking droplet $i
    IP=$(ansible localhost -c local -i $TEMP_INVENTORY -m digital_ocean -a "state=present command=droplet unique_name=yes name=$i" | grep "\"ip_address" | awk '{ print $2 }' | cut -f2 -d'"')
    echo "$i ansible_ssh_host=$IP" >> $INVENTORY/generated
  done
fi

echo "All done !"
{% endhighlight %}










