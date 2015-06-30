---
layout: post
title: Transparent encryption/decryption with ansible vault
excerpt: "Never type ansible-vault again."
tags: [ansible, ansible-vaut, git]
categories: articles
modified: 2015-05-25
comments: true
---

# Big Fat Warning

**THIS FILE IS LEFT HERE FOR REFERENCE**

However, the method described here is WRONG. Check out 
[next post]({% post_url articles/2015-05-26-transparent-vault-revisited %}) instead !

## Pain points

`ansible-vault` is handy. You can crypt your stuff before commiting it so your
private stuff (AWS/DigitalOcean/... keys, passwords, ...) don't end up
world-readable on GitHub.

However, it is too easy to decrypt your stuff, forget about it, and commit it 
without encrypting it back. It is also quite tedious to ansible-vault
encrypt/decrypt all day long.

## Solution

[Raphael Campardou](https://github.com/ralovely) proposed a [nice
solution](https://gist.github.com/ralovely/9367737) to prevent commiting
ansible vault files.

In his solution, you have to name your files `*_vault.yml` so they get busted
by a pre-commit hook if they are not currently encrypted.

This is nice: by naming your files appropriately, you can not commit them unless
they are ansible-vault crypted beforehand.

I extended his idea so it can apply to any file in an Ansible repository, with
very little configuration, and added a post-commit hook so files gets
transparently decrypted after being commited.

## Transparent encryption/decryption

The goal is simple: automagically encrypt the proper files before commit,
commit them, then decrypt them afterwards so we can hack again without
any manual intervention. All this with minimal configuration.

### Marking file for encryption

The center trick is to find a way to mark a file for encryption. Modelines
(a.k.a. emacs local variable lines) to the rescue.

To tell git hooks that a file requires encryption, we'll add this line to
the top of the file (or on line 2 if the file already has a shebang
line) :

    # -*- vault: true; -*-

Any file having `vault: true` in a modeline is set to __require encryption before
commit__.

The icing on the cake is that you can use this modeline to set the filetype
too[1], and help your editor to find out the proper file content, which is
quite handy with some files not ending in `yml`:

    # -*- mode: yaml; vault: true; -*-

This is supported out of the box by vim and Emacs. If you use SublimeText,
you can use the [STEmacsModelines](https://github.com/kvs/STEmacsModelines)
package.

### Using the hooks

The pre-commit hook will encrypt files marked with `vault: true`. If a
`.vault_password_hooks` file is present in the project root directory, it will be
used as the password.

If this file doesn't exist, you'll be promted for an encryption password and
this password will be saved in `.vault_password_hooks`, in your project's root.

If `.vault_password_hooks` is listed in `.gitignore`, this file will persist and you
won't be asked for a password anymore for encryption as well as for decryption.
Otherwise, `.vault_password_hooks` will be erased after encryption to avoid commiting
the file.

After commiting the files, the post-commit hook will use the same password to
decrypt the previously encrypted files.

**TL;DR:** add `.vault_password_hooks` to your `.gitignore`, add `# -*-
vault: true; -*-` to files that requires encryption and you're set.

You end up with a workflow where your files are transparently encrypted before
commit and decrypted after.

## Hooks

Put the hooks in `.git/hooks/` and don't forget to `chmod +x
{pre,post}-commit` them.

{% gist leucos/405b406b9d6bde0c3d39 %}

