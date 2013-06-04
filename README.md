oc_bifrost
========

Bifrost?
=========

`oc_bifrost` is the Opscode Authorization API server.  It is named
after [Bifrost][], the burning rainbow bridge to Asgard in Norse mythology.

`oc_bifrost` is a complete rewrite and replacement of the old
[opscode-authz][] API server.

[Bifrost]:http://en.wikipedia.org/wiki/Bifrost
[opscode-authz]:https://github.com/opscode/opscode-authz

Testing and Development
=======================

We're using [Berkshelf][] to make things easy.

First, you'll need to configure Berkshelf to talk to our preprod Chef
Server.  Create or add to a `~/.berkshelf/config.json` file the
following information:

``` javascript

{
    "chef": {
      "chef_server_url": "https://opsmaster-api.opscode.us/organizations/preprod",
      "node_name": <YOUR_OPSMASTER_ACCOUNT_NAME>,
      "client_key": <PATH_TO_YOUR_OPSMASTER_SSH_KEY>
    },
    "ssl": {
      "verify": false
      }
    }
}
```

The `ssl` directive is important!

Also, while we still have a monolithic [chef repo][], we'll need to
refer to our platform roles and data bags in order to replicate our
production environment as much as possible in a local Vagrant setting.
The easiest way to make this work is to set an environment variable
that points to a local checkout of the platform cookbooks repo, which
the [Vagrantfile](Vagrantfile) then uses.

```
export OPSCODE_PLATFORM_REPO=/path/to/local/checkout/of/repo
```

The following environmental variable is used for locating local cookbooks
(however, even if no local cookbooks are used and the variable is empty or
pointing at an empty directory, it's still required):

    export OPSCODE_COOKBOOKS=/path/to/working/cookbooks

Also, the following environmental variable must point to all the opscode
cookbooks being worked on (i.e., oc_bifrost, etc. which are mounted into
the VM):

    export OPSCODE_SRC=/path/to/src/oc/

Now you're ready to grab all the dependencies.  We're installing
binary stubs into `bin` to ensure everything is as self-contained as
possible.

Our `Vagrantfile` is geared for the latest installer-based versions.
If you do not already have this, please download the latest from
http://downloads.vagrantup.com.  Note that it __will not work__ with
earlier gem-based versions of Vagrant!

If you used earlier versions of this process with `bundle install
--binstubs`, go ahead and delete the `bin` directory now; you will not
need it anymore, and it will probably just confuse things and bring
you much woe and heartache.  Nobody needs that.

If you still have old gem-based vagrant on your system, and you
use RBEnv, you may have some shims around.  Since `opscode-dev-vm` is
still using the old Vagrant, you probably don't want to remove your
vagrant gem and nuke your shim just yet (you could do a `bundle
install --binstubs` in `opscode-dev-vm` if you wanted to, but I
digress).  To ensure you're using the installer-based Vagrant, you can
invoke it directly using `/usr/bin/vagrant` and remove all doubt.

Due to incompatibilities between the on-disk representation of
Vagrant boxes for the gem-based and installer-based Vagrant, you may
run into issues if you need to continue to use both versions of
Vagrant.  The first time you run the installer-based Vagrant, it will
notify you that it will update the format of your existing boxes.  If
you accept this, these boxes will no longer work with the gem-based
Vagrant.  However, there is an environment variable (`VAGRANT_HOME`)
that you can set which will enable you to use different directories
for the different Vagrants.  If you update your boxes for
installer-based Vagrant (recommended), you'll need to set
`VAGRANT_HOME` to point to somewhere other than `~/.vagrant.d` when
using gem-based Vagrant in the future; if you don't update the boxes,
you'll need to set `VAGRANT_HOME` when running the installer-based
Vagrant.  The choice is yours.

You'll need to set up the Berkshelf plugin for Vagrant:

    /usr/bin/vagrant plugin install vagrant-berkshelf

Now, to fire up and provision all the VMs:

```
/usr/bin/vagrant up
```

We currently have 3 VMs:

- `db`: the database server
- `api`: the API server
- `metrics`: an estatsd / graphite / gdash server, useful for
  developing graphs for Bifrost.

Remember: you can interact with each VM individually by providing its name, e.g.:

    /usr/bin/vagrant up db

Go muck around on a specific machine now:

```
bin/vagrant ssh db
```

To re-run `chef-client` on your test machine:

```
bin/vagrant provision db
```

If you screw something up horribly, just destroy the machine and start
again:

```
bin/vagrant destroy db
```

Eventually, we'll be adding Test Kitchen support for running
[oc-bifrost-pedant][] and our pgTAP database schema tests.

Cookbook Hacking
================

If you want to hack on the [opscode-bifrost][] cookbook, you'll need to
make a minor tweak to the Berksfile.

First, perform a local checkout of the cookbook.  Then, modify the
dependency line in `Berksfile`.

Change this:

``` ruby
cookbook "opscode-bifrost, git: "git@github.com:opscode-cookbooks/opscode-bifrost"
```

to this:

``` ruby
cookbook "opscode-bifrost", path: "/path/to/local/checkout/of/opscode-bifrost"
```

Re-provision your machine and you'll be running off the local version
of the cookbook.

[Berkshelf]:http://berkshelf.com
[oc-bifrost-pedant]:https://github.com/opscode/oc-bifrost-pedant
[opscode-bifrost]:https://github.com/opscode-cookbooks/opscode-bifrost
[chef repo]:https://github.com/opscode/opscode-platform-cookbooks

Cutting A Release
=================

To cut a proper release, we're using the [rebar_lock_deps_plugin][].
The executive summary is this:

```
BUMP=patch make prepare_release && rebar commit-release && rebar tag-release
```

Substitute `minor` or `major` for `BUMP` as necessary.  Note that the
presence of the `USE_REBAR_LOCKED` on `master` will cause all
subsequent builds to use the locked dependencies.

[rebar_lock_deps_plugin]:https://github.com/seth/rebar_lock_deps_plugin
