## Makepkg Cross-Compiliation Helper Script
`makepkg-cross-helper.sh` is a way to automate some of the burden of making cross-compilation-compatible PKGBUILD files. It hooks into build(), package() and even a couple of internal functions of `makepkg` in order to make some mundane tasks for cross-compiling worry-free.

It does this through hacks, trickery, and general skulduggery. By that, I mean that it modifies several functions of the PKGBUILD and `makepkg` itself to get things done.

### Automatic prefixing of package names
This script will automatically prefix the package name with the prefix of your choice. It does this for the `pkgname` itself, and everything in `depends`, `makedepends`, `groups`, `optdepends`, `checkdepends`, `provides`, `conflicts`, and `replaces`. It also gracefully handles multi-package PKGBUILD files that override any of `arch`, `depends`, `groups`, `optdepends`, `provides`, `conflicts`, `replaces`.

Let's face it, Pacman is pretty simple. You can't go installing an armv7h version of zlib if there is a native one on your system: it probably won't work (but I don't advise trying it -- if it does, you're gonna have a bad time). By adding package prefixes, it helps segregate the non-native packages from the native ones.

### Automatic architecture support
It automatically adds the architecture to the list of supported architectures so you don't have to change it by hand.

### PATH fixing
This one probably requires a little bit of explaining. Some packages include Makefiles that "support cross-compilation" by hard-coding a compiler and/or flags into the Makefile with the expectation that the user will change it if they need to do cross-compilation (see zlib/contrib/minizip/Makefile). Initially, my solution to this problem was to use `sed` commands in the PKGBUILD to fix the hard-coded values to what I wanted. But, it's somewhat time-consuming to pour over the Makefiles and figure out what's wrong in order to correct it.

Turns out, there is a better way. What I ended up doing, was creating a directory `${srcdir}`/dummy-bin populated with files that are all the non-prefixed names of your cross-binutils or cross-compilers. The script will try to automatically detect your cross-binutils and cross-compiler and do one of two things:

1. If it's a compiler or `ld`/`lld`, it will create a short BASH script called, i.e. cc, c++, ld, etc. This script calls your cross-compiler with the appropriate flags as set in your makepkg.conf so that if the misbehaving Makefile overrides your `$CFLAGS`/`$CXXFLAGS`/`$LDFLAGS`, it won't matter since they're hard-coded into the script.
2. Otherwise, it simply symlinks the binary to `${srcdir}`/dummy-bin as the non-prefixed executable name.

Finally, it sets `PATH=${srcdir}/dummy-bin:$PATH` for build(), check(), and tidy_install(). tidy_install() is an internal `makepkg` function that handles stripping. Without giving it a new `$PATH`, it uses the native `strip` command, which won't work to strip cross-compiled binaries/libs.

### Clang support... probably?
OK, so this isn't really tested yet. Admittedly, I haven't gone down the rabbit hole that is cross-building Clang just yet. However, the script does have basic support for Clang. If, for some reason, it doesn't work as expected then hopefully manually setting `crosshelper[CC]=/usr/bin/cross-clang`, `crosshelper[CXX]=/usr/bin/cross-clang++` within the script or as `source` arguments (see below) should do the trick. If you run into issues with Clang, let me know by submitting an issue or pull request.

### What it doesn't do
1. While it may add the architecture automatically so that `makepkg` doesn't complain, it doesn't fix code that's not compatible with architecture X.
2. It does not fix checks. By default, your computer can't run cross-compiled binaries for testing purposes (of course). I've had good results using qemu linux-user emulation to run the checks transparently. Or, you could just use `makepkg --nocheck`, but I probably wouldn't advise it unless, for some reason, Qemu isn't working for you.
3. It doesn't fix install paths. Honestly, there are just way too many build systems and different ways of doing things, this script doesn't even bother. So, you're going to have to fix `configure`,`meson`, etc. in the PKGBUILD to suit your needs. You definitely can't *not* do this part.<sup>1</sup>
---
## Usage
Usage can be as simple as adding the following line to the end your PKGBUILD file:

    source /path/to/makepkg-cross-helper.sh

**Important:** The script should be sourced at the end of the PKGBUILD so that all of the variables above it have already been evaluated. Otherwise, it's likely not to work properly or not work at all.

There are tunable options in the script itself, but at the very least `crosshelper[PKG_PREFIX]` and `crosshelper[ARCH]` need to be set in the script.

Alternatively, you can simply provide any configurable variables as arguments to the `source` command like so:

    source /path/to/makepkg-cross-helper.sh ARCH=armv7h PKG_PREFIX=arm-linux-gnueabihf CC=/usr/bin/arm-linux-gnueabihf-clang

**Note:** While, internally, all variables are part of the `crossbuild` array, this is not expected or required when passing arguments to `source`. Use plain variable names.

For fine-tuning the script, have a look in the `Optional variables` section of the script.

### Argument precedence
There are a few ways to pass arguments to the script. From the highest precedence to the lowest, they are:
1. `makepkg` arguments: `makepkg CC=arm-linux-gnueabihf`
2. `source` arguments within the PKGBUILD file: `source /path/to/makepkg-cross-helper.sh CC=arm-linux-gnueabihf`
3. Alternative makepkg.conf file within the PKGBUILD file: `source /path/to/makepkg-cross-helper.sh CONFIG=/path/to/makepkg.conf`

This is important to remember, since variables can overwrite each other. For example, if your alternate makepkg.conf file with CFLAGS="configflags" is sourced via `source /path/to/makepkg-cross-helper.sh CONFIG=myaltconfig.conf`, but you also specified `makepkg CFLAGS="cmdflags"`, then, due to order of precedence, ultimately `CFLAGS="cmdflags"`.

---
## TODO
There isn't a lot on my "todo" list right now, other than maybe fixing the `backup` array. However, as I continue to use this script, I'm sure I'll run into more issues that it can solve!

<sup>1</sup> OK, so maybe there *might* be a configurable way to do this post-package(), but I'll probably only add this if I get really annoyed.
