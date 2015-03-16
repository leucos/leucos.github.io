---
layout: post
title: "Restoring Arch bootloader for the future self"
excerpt: "Quick note on restoring the bootloaded on Asus UX51VZA"
tags: [uefi, arch]
comments: true
---

- Grab latest Arch, create a bootable key (do this before you're doomed)[^1]. 

- Press F2 at boot, change the boot order to start on the key in __UEFI__ mode

- Boot on Arch, then

{% gist leucos/3f63c07d8326309d7fb1 %}

- Cross fingers...

[^1]: Multisystem is pretty handy for this. You can put several OSes on the key, and choose what to boot. <http://liveusb.info/dotclear/>
