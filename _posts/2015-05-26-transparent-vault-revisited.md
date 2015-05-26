---
layout: post
title: Transparent encryption with ansible vault revisited
excerpt: "Test your blog posts thoroughly next time"
tags: [ansible, ansible-vaut, git]
modified: 2015-05-25
comments: true
---

## Doing it the wrong way

[Last attempt]({% post_url 2015-05-25-ansible-transparent-vault %})
to make ansible vault encryption/decryption transparent wasn't quite
right. Decrypting files after commit wasn't a good idea as
[Raphael Campardou](https://github.com/ralovely) noticed.

In search for a better idea, I eventually realized that hooks where not
the right place to do it: yes, you can guard from commiting files that
should be encrypted, but hacking around hooks to build a crypt/decrypt
pipeline is doomed to failure.

## Doing it better

While looking for alternate ways, I remembered I hacked around with
git filters back in the days to see clear-text diffs for OpenOffice
files.

Git let's you apply `smudge`, `clean` and `textconv` filters to files
which are applied this way:

- filter/smudge: after checkout, reads blob from STDIN and outputs the
  workfile from STDOUT
- filter/clean: converts the worktree file to blob upon check in
- diff/textconv: applied before diffing files

So, for our needs, _smudge_ and _textconv_ are good places to decrypt,
while _clean_ is the place to encrypt.

## Implementation

The implementation requires to write the 3 filters (_smudge_, _clean_,
_textconv_) and configure your git repos to use the filters.

Those filters should be executable.

As we did in last post, we will use a `.vault_password` file in the
project root directory containing the vault key (don't forget to add it
to your `.gitignore` file !). The filters fail if the file is not
present.

### Smudge

The problem that came up to write the smudge & clean filters is that the
blob content is fed on STDIN, and `ansible-vault` can only
encrypt/decrypt files _in-place_.

So we have to write the blob in a temporary file. While this is not
really a problem for the smudge filter, it is for the clean filter since
the temporary file contains the clear-text version of the file. The temp
file is created with restricted permissions, but you've been warned.

Smudge's filter job is simple:
- write STDIN content to temp file
- decrypt the temp file and swallow the output in a variable (using
  `ansible-vault view` after setting the PAGER to `cat`)
- if the file was a vault encrypted file, display the variable, else,
  bail out.

    #!/bin/sh
    
    if [ ! -r '.vault_password' ]; then
      exit 1
    fi
    
    tmp=`mktemp`
    cat > $tmp
    
    export PAGER='cat'
    CONTENT=`ansible-vault view "$tmp" --vault-password-file=.vault_password 2> /dev/null`
    
    if echo $CONTENT | grep 'ERROR: data is not encrypted' > /dev/null; then
      echo "Looks like one file was commited clear text"
      echo "Please fix this before continuing !"
      exit 1
    else
      echo $CONTENT
    fi
    
    rm $tmp

As you guessed, `ansible-vault` does not output errors on STDERR but on
STDOUT.

### Clean

The clean filter works almost the same way:
- write STDIN to a temp file
- encrypt the temp file in place
- write the temp file to STDOUT

    #!/bin/sh
    
    if [ ! -r '.vault_password' ]; then
      exit 1
    fi
    
    tmp=`mktemp`
    cat > $tmp
    
    ansible-vault encrypt $tmp --vault-password-file=.vault_password > /dev/null 2>&1
    
    cat "$tmp"
    rm $tmp
    

This one was quite easy. We could also use modelines, by encrypting only if
"vault: true" is present in the 4 first lines. This way, we could apply
the filters to all the files. However I ditched the idea for performance
reasons (see below).

### Diff filter

The filter works like the smudge filter except that it uses the file
name passed as a parameter.

    #!/bin/sh
    
    if [ ! -r '.vault_password' ]; then
      exit 1
    fi
    
    export PAGER='cat'
    CONTENT=`ansible-vault view "$1" --vault-password-file=.vault_password 2> /dev/null`
    
    if echo "$CONTENT" | grep 'ERROR: data is not encrypted' > /dev/null; then
      cat "$1"
    else
      echo "$CONTENT"
    fi

### Git configuration

#### Attributes

Now that the various filters are out and chmoded +x, we need to set-up
out git repos to use them.

For this, we need to tell git on which files we want to apply the
filters, using a `.gitattributes` file in our project top directory.

The following `.gitattributes` file

    *_vault* filter=vault diff=vault

will run filters on repository blobs/files that match `*_vault*`.

I initially intended to run the filters on all files, using modelines.
However, performance was really bad, so I finally ended up removing a
full wildcard (`*`) and restrict filter selection to specific files.
You can repeat the lines ad nauseam if you want to catch multiple
fileglobs.

#### Gitconfig

I put my filters in `~/.bin/`, but the location doesn't matter. You can
event add them to the project and commit them, so everyone has them.

The following section needs to be added to the project's `.git/config`
file:

    [filter "vault"]
      smudge = ~/.bin/smudge_vault
      clean  = ~/.bin/clean_vault
    
    [diff "vault"]
      textconv = ~/.bin/diff_vault
    

### Test

Adding a file that matches a glob in `.gitattributes` should now trigger
transparent encryption.

Here is a sample transcript.

<script type="text/javascript" src="https://asciinema.org/a/7oaviuh8v2pi39zeojxrn8434.js" id="asciicast-7oaviuh8v2pi39zeojxrn8434" async></script>

### Big fat warning

The `git cat-file` part is not here for decoration. At least the first
time, ensure that encryption works.

### The filters

{% gist leucos/1bfcfc7252e8c262956e %}
