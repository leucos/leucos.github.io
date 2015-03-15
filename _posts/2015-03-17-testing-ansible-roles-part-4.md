---
layout: post
title: Testing Ansible roles, part 4
excerpt: "Testing Ansible roles, TDD style, with rolespec, Vagrant and Guard"
tags: [ansible, tdd, rolespec, guard, vagrant]
modified: 
comments: true
---

In the [previous]({% post_url 2015-03-16-testing-ansible-roles-part-3 %}) post, we added more tests to the `test` file.

We will now add TravisCI support, so we can test our role when it is pushed on GitHub.

## Travis file

