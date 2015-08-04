# SmartThings WebIDE Sync
In short:
Allows commandline access to the SmartThings WebIDE

## Long version
With stsync.sh and stwatch.sh you can download all your SmartApps and
DeviceTypes from the WebIDE. Once downloaded, if you do any changes
you can upload AND publish those using the same script.

The stwatch.sh is an automated version of stsync.sh which will monitor
the source directory for any changes and perform either an upload or
a publish (or both, which is probably more useful) of the changed file.

## Installation

You'll need the following tools installed on your OSX/Linux device (Cygwin in windows "may" work but is untested).

- brew (install using "ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)")
- perl (you should have it by default)
- cpanm (install using "brew install cpanm")
- json (install using "cpan install JSON")
- fswatch (install using "brew install fswatch")
- AnyEvent::WebSocket::Client (install using "cpan install AnyEvent::WebSocket::Client")
  (only needed if you want livelogging support)

Once all tools are installed, please create a new file in your home
directory called ".stsync". In this file you need to add the following
three lines:

```
USERNAME=<email address used for the smartthings.com WebIDE>
PASSWORD=<associated password for the account>
SOURCE=<a path for a directory to use for all the source>
```

Once you've done this, you're ready to go. 

Just issue "./stsync.sh -s" to create the initial repository
(also creates all the directories needed)

## Usage

### ./stsync.sh -s
Creates a new repo, will NOT overwrite existing files

### ./stsync.sh -S
Creates a new repo, WILL OVERWRITE EXISTING FILES! ANY CHANGES WILL BE LOST!

### ./stsync.sh
Shows any pending changes (ie, local changes which have not be uploaded and/or published)

### ./stsync.sh -u
Uploads any and all pending changes

### ./stsync.sh -p
Publishes any uploaded changes

### ./stsync.sh -pu
Upload and publish any local changes. If a upload fail due to compile errors, it will not be published.

### ./stsync.sh -f
Adding the -f option and a filename will cause the operations to only affect the file provided. It can be provided with or without path, but it MUST be a groovy file. No wildcards are allowed.

### ./stsync.sh -L
Live Logging support, prints out the messages in your console.

### ./stsync.sh -h
Shows all available options

### ./stsync.sh -d
Disables preprocessing

## Preprocessor directives

Currently, STSYNC only supports one:

```
#include "<file>"
```

This will include any file you want, the base directory for the file is the same as the groovy file that's being processed. It's recommended that you create a subfolder in the app and/or device folder for your includes and that you use git to track these files. Stsync is able to reconstruct these files if you uploaded them using the tool (yes, even re-creating the folder structure needed), but keep in-mind that if various apps/devices used different versions of the includes, you may end up with old code inside your includes, so git is highly recommended to make sure you have the latest includes.

The base-path for the #include directive is the same folder as the groovy-file that is using it. So for an app, that would be the app folder. You can ofcourse use includes from outside of the base folder by specifying "..", for example: #include "../device/include/some-include.groovy" but it's generally not recommended. If you need to use an include in both apps and devices, it's better to create an include folder on the same level as app and device folders. With that in mind, the directive would read #include "../include/some-include.groovy".

You can disable preprocessing by providing the "-d" options. You can also FORCE the system to overwrite includes when pulling down the repo by specifying "-o" (which is usually most useful if combined with "-S").

Lastly, you can have as many levels to your #include directives as you want, meaning an included file may in-turn include others.

## Automatic mode
It's possible to set it up so any changes are automatically processed. Simply call ./stwatch.sh instead. Please note that it only supports -u, -i and -p options. Please note that on start, it will LIST all files and any pending operations, BUT IT WILL NOT EXECUTE THEM. This is just to make sure you know what state you're in.

## Git support
By default, when creating a repo, the script will also place a .gitignore file in the source folder to allow you to use git for source code tracking. It automatically
ignores the raw/ directory which holds sync data. It may be a bit odd way of doing it, but it removes a lot of "crud" which you would be tracking as well which strictly speaking isn't needed.

### Restoring when using git
First, git clone your source directory. Next you run ./stsync.sh with -S (yes, it will overwrite, which is fine). Next you issue "git checkout -- ." in the source directory, this will remove all the changes caused by the overwrite. Now you're good to go.

## Limitations
Only runs on OSX/Linux for now, once you've downloaded the repository, you should avoid doing changes from the WebIDE since there is no sync from web other than overwrite. 

In theory, the scripts should work on Cygwin inside windows as well, but this is not tested.
