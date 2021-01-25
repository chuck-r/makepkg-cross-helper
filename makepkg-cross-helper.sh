#!/bin/bash
#^ This script doesn't need to be executed, this is mostly
#for syntax highlighting support

###############################################################################
#
# Copyright 2021 Chuck-R <github@chuck.cloud>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
###############################################################################
#
# makepkg-cross-helper.sh
#
# Purpose: The intent of this script is to automate some of the tasks that I
#          have had to do by hand up until now when cross-compiling Arch
#          packages.
#
#          1. It adds the architecture triplet (as defined by
#             crossarch[PKG_PREFIX] below) to the beginning of the package name
#             so that cross-built packages are not confused with native
#             packages.
#          2. It adds the architecture to the list of supported architectures
#             automatically so that makepkg doesn't complain.
#          3. Some Makefiles leave it as an exercise for the user to modify
#             the Makefile to suit cross-building. So, this script brute-forces
#             the problem by creating a directory within ${srcdir} that
#             contains references to all of the cross-build files as their
#             non-prefixed names (i.e, cc, gcc, c++, ld, ar, etc.). It
#             contains:
#             a) Bash scripts for cc/gcc/clang/clang++/c++/g++ that call the
#                real cross-compiler bin with the desired
#                CFLAGS/CXXFLAGS/LDFLAGS
#             b) Simple symlinks for everything else
#
#          For some packages, even all of this isn't enough. For some packages
#          that use basic Makefile and such, accommodations will have to be made
#
# Usage: Add the line `source /path/to/makepkg-cross-helper.sh' at the end of
#        your PKGBUILD file.
###############################################################################

declare -A crosshelper

###############################################################################
# Required veriables
###############################################################################
# This can be overridden by via arguments to `source`
# For example:
# source /path/to/makepkg-cross-helper.sh ARCH=armv7l PKG_PREFIX=arm-linux-gnueabi
###############################################################################

#Package architecture
crosshelper[ARCH]=armv7h

# Package prefix (without trailing hypen).
# This is a pretty important variable, as crosshelper[BIN_PREFIX] defaults to
# this value. The script will look for compilers prefixed with this string if
# crosshelper[BIN_PREFIX] isn't explicitly set. crosshelper[BIN_PREFIX] is used
# to guess which compilers are installed. The script will emit a warning when a
# compiler is "guessed" in this way. If the script's guesses are not correct,
# set crosshelper[BIN_PREFIX] below

crosshelper[PKG_PREFIX]=arm-linux-gnueabihf

###############################################################################
# Optional variables
###############################################################################
# For fine-tuning the behavior of the script
###############################################################################

# These variables are for fine-tuning this script

# Prefix of compiler programs (if not set, defaults to crossarch[PKG_PREFIX])
# This is necessary because some programs do the build in individual
# steps, without relying on, i.e. GCC running all the steps from one
# command. This is just a convenience variable, if you use makepkg like
# `makepkg --config alt-config.conf CC=arm-linux-gnueabihf-gcc', for example,
# then this script should be able to set CC/CXX/LD/AR/RANLIB appropriately.
# Though, it may give you a warning.

# crosshelper[BIN_PREFIX]=arm-linux-gnueabihf

# These are sometimes required for certain Makefiles to work properly in a
# cross-build environment. For an example, see zlib's conrib/minizip/Makefile.
# These makefiles will set "sane" defaults for the below variables without
# taking into conderation as to whether they're already set. This means that
# rather than using the cross-build compiler they are hard-coding the native
# compiler -- which will cause things to either appear to work correctly
# (but actually build native binaries) or just fail spectacularly for no
# obvious reason. If these variables aren't set, this script will give a
# warning, but in many cases it can just be ignored. However, I would
# recommend setting these to the values of your cross-compiler binaries as
# it won't hurt build systems that actually check.

#crosshelper[CC]=arm-linux-gnueabihf-gcc
#crosshelper[CXX]=arm-linux-gnueabihf-g++
#crosshelper[LD]=arm-linux-gnueabihf-ld

# End of optional variables

###############################################################################
# Get environment variables that we care about from makepkg
# arguments/environment
###############################################################################
for envvar in {ARCH,PKG_PREFIX,BIN_PREFIX,CC,CXX,CFLAGS,CXXFLAGS,LDFLAGS,CONFIG}; do
  if [ "x${!envvar}" != "x" ]; then
    crosshelper[${envvar}]=${!envvar}
  fi
done

###############################################################################
# Process arguments, should all be VAR=VALUE
###############################################################################

while [ $# -gt 0 ]; do
  crosshelper[envvar]=${1%%=*}
  crosshelper[value]=${1#*=}
  crosshelper[${crosshelper[envvar]}]=${crosshelper[value]}
  if [ "x${crosshelper[CONFIG]}" != "x" ]; then
    crosshelper[originalconfig]=$(cat /etc/makepkg.conf)
    #Config file set as argument to `source`
    if [ -e "${crosshelper[CONFIG]}" ]; then
      # Prefix all variables from the config file as MAKEPKG_CONFIG_
      # The awk script just prints all lines with MAKEPKG_CONFIG and then
      # compacts all multi-line arrays into a single line
      crosshelper[config]=$(cat "${crosshelper[CONFIG]}" | sed -r 's|^(\w+)?([A-z_]([0-9A-z_]+)?)=|MAKEPKG_CONFIG_\1\2=|' | \
                awk 'BEGIN{openparen=0;};/MAKEPKG_CONFIG_/{test=$0;if(sub("\\(","",test) && !sub("\\)","", test)){openparen=1;};if(!openparen){print $0;};};openparen == 1{test=$0;if(sub("\\)","",test)){openparen=0; print $0}else{printf("%s", $0);};}' | \
                sed 's/MAKEPKG_CONFIG_//')
      # `source` without a file`
      eval ${crosshelper[config]}
      # `env` won't find the variables imported above. Good thing we saved them.
      # Read all imported vars
      crosshelper[debug]=0
      while read -d$'\n' envvar; do
        crosshelper[newenv]=${envvar%%=*}
        crosshelper[newval]=${envvar#*=}
        #Remove quotes for matching
        crosshelper[newvalstripped]="$(echo ${crosshelper[newval]} | sed -r -e 's/^("|'\'')//' -e 's/("|'\'')$//')"
        # Skip arrays, since BASH doesn't support multi-dimensional arrays...
        # and I don't think that any of them are particularly helpful
        # The array variables in a makepkg.conf are:
        # DLAGENTS
        # VCSCLIENTS
        # INTEGRITY_CHECKS
        # MAN_DIRS
        # DOC_DIRS
        # PURGE_TARGETS
        # COMPRESS{GZ,BZ2,XZ,ZST,LRZ,LZO,Z,LZ4,LZ}
        # PKGEXT
        # SRCEXT
        if [ "${crosshelper[newval]#(}" != "${crosshelper[newval]}" ]; then
          # I do need to know if the passed config specifies default debugging
          # so that I can update CFLAGS/CXXFLAGS/LDFLAGS accordingly.
          if [ "${crosshelper[newenv]}" == "OPTIONS" ]; then
            eval CROSSHELPER_OPTIONS=${crosshelper[newval]}
            for option in ${CROSSHELPER_OPTIONS[@]}; do
              if [ "$option" == "debug" ]; then
                debug=1;
                crosshelper[DEBUG]=1;
                break
              fi
            done
            unset CROSSHELPER_OPTIONS[@]
          fi
          continue
        fi
        if [ "x${crosshelper[${crosshelper[newenv]}]}" != "x" ]; then
          # The environment variable is already defined. Let's see if it's the
          # same value as what's stored in /etc/makepkg.conf. If it is, it's
          # safe to override it. Otherwise, it was probably explicitly set.
          crosshelper[originalval]=$(echo "${crosshelper[originalconfig]}" | grep "^${crosshelper[newenv]}=" | sed -r -e 's/[[:digit:]]?[[:alnum:]_]+=//' -e 's/^"//' -e 's/"$//')
          if [ "${crosshelper[${crosshelper[newenv]}]}" == "${crosshelper[originalval]}" ]; then
            # I have a bit of a unique situation with my alternate config file:
            # I use variable substitution in order to type a long path once and
            # use it multiple times. So, I have to eval the values to make sure
            # that the values get expanded. This is also the reason for the
            # export below it -- the config file uses plain names, not the
            # crosshelper array. The export doesn't hurt anything since makepkg
            # cleasr the environment after this script is run anyway (as far as
            # I can tell)
            crosshelper[${crosshelper[newenv]}]="$(eval echo ${crosshelper[newvalstripped]})"
            eval "export ${crosshelper[newenv]}=\"${crosshelper[newvalstripped]}\""
          fi
          unset crosshelper[originalval]
        else
          # The environment variable isn't defined yet, go ahead and set it.
          crosshelper[${crosshelper[newenv]}]="$(eval echo ${crosshelper[newvalstripped]})"
          eval "export ${crosshelper[newenv]}=\"${crosshelper[newvalstripped]}\""
        fi
      done <<<$(echo "${crosshelper[config]}") #Avoid a subshell
      unset crosshelper[config]
      unset crosshelper[newenv]
      unset crosshelper[newval]
      unset crosshelper[newvalstripped]
      unset crosshelper[debug]
      unset crosshelper[originalconfig]
    else
      echo "cross-helper: ERROR: CONFIG=${crosshelper[value]} passed as an argument, but it doesn't appear to be a file."
      continue
    fi
  fi
  shift
done
unset crosshelper[envvar]
unset crosshelper[value]

###############################################################################
# Replicate `makepkg` and append debug flags
###############################################################################
if [ "x${crosshelper[DEBUG]}" == "" ]; then
  # I already checked for debugging if an external config was passed, but I
  # haven't yet checked the options array.
  for val in ${options[@]}; do
    if [ "$val" == "debug" ]; then
      crosshelper[DEBUG]=1
      break
    fi
  done
fi
# After potentially two checks now, if we are debugging, make sure to append
# debug flags
if [ "x${crosshelper[DEBUG]}" != "x" ]; then
  for var in {DEBUG_CFLAGS,DEBUG_CXXFLAGS,DEBUG_LDFLAGS}; do
    if [ "x${crosshelper[$var]}" != "x" ]; then
      eval "crosshelper[${var#DEBUG_}]+=\" ${crosshelper[$var]}\""
    fi
  done
fi

###############################################################################
#Try to set the needed variables to sane defults
###############################################################################
setup_env()
{
  for envvar in {CC,CXX,LD,CFLAGS,CXXFLAGS,LDFLAGS}; do
    : ${crosshelper[$envvar]:=${!envvar}}
  done
  : ${crosshelper[BIN_PREFIX]:=${crosshelper[PKG_PREFIX]}}

  #Maybe one of the environment variables has a prefix? Check all of the
  #environment variables we care about to see if one of them has a prefix
  crosshelper[guess_prefix]=""
  for envvar in {CC,CXX}; do
    if [ "x${!envvar%-*}" != "x${!envvar}" ]; then
      crosshelper[guess_prefix]=${!envvar%-*}
      break
    fi
  done
  if [ "x${crosshelper[guess_prefix]}" == "x" ] && [ "${crosshelper[PKG_PREFIX]}" != "${crosshelper[BIN_PREFIX]}" ]; then
    #Didn't get a guess from the environment variables, try crosshelper[BIN_PREFIX]-{cc,c++,gcc,g++,clang,clang++}?
    for bin in {cc,c++,gcc,g++,clang,clang++}; do
      guessfile=$(which "${crosshelper[BIN_PREFIX]}-$bin" 2>/dev/null || /bin/true)
      if [ "x$guessfile" != "x" ]; then
        crosshelper[guess_prefix]=${crosshelper[BIN_PREFIX]}
        break
      fi
    done
  fi
  if [ "x${crosshelper[guess_prefix]}" == "x" ]; then
    #Still nothing? Try package prefix? I'm out of ideas here.
    for bin in {cc,c++,gcc,g++,clang,clang++}; do
      guessfile=$(which "${crosshelper[PKG_PREFIX]}-$bin" 2>/dev/null || /bin/true)
      if [ "x$guessfile" != "x" ]; then
        crosshelper[guess_prefix]=${crosshelper[PKG_PREFIX]}
        break
      fi
    done
  fi

  declare -a envtobin=("CC" "cc" "CXX" "c++" "LD" "ld")
  for i in ${!envtobin[@]}; do
    if [ $(($i % 2)) -eq 0 ]; then
      if [ "x${crosshelper[${envtobin[$i]}]}" == "x" ]; then
        # crosshelper{$envtobin[$i]} (crosshelper[CC],crosshelper[CXX],
        # crosshelper[LD]) doesn't exist
        if [ "x${crosshelper[BIN_PREFIX]}" == "x" ]; then
          # crosshelper[BIN_PREFIX] isn't set
          if [ "x${crosshelper[guess_prefix]}" != "x" ]; then
            # I was able to find a binary prefix in any of the usual envvars
            # (CC, CXX, LD)
            if [ "${envtobin[$i]}" == "CC" ] && [ ! -x "$(which ${crosshelper[guess_prefix]}-cc 2>/dev/null || /bin/true)" ]; then
              if [ -x "$(which ${crosshelper[guess_prefix]}-gcc 2>/dev/null || /bin/true)" ]; then
                #Default to gcc
                echo crosshelper[${envtobin[$i]}]=${crosshelper[guess_prefix]}-gcc
                crosshelper[${envtobin[$i]}]=${crosshelper[guess_prefix]}-gcc
              fi
            else
              crosshelper[${envtobin[$i]}]=${crosshelper[guess_prefix]}-${envtobin[$(($i + 1))]}
            fi
            echo "cross-helper: Since ${envtobin[$i]} isn't set, I'm going to guess that"
            echo "${envtobin[$i]}=${crosshelper[${envtobin[$i]}]}."
            echo "If this isn't correct, set it explictly in the script or pass it as"
            echo "an argument to the sourcing of the script."
          else
            # No crosshelper[$envvar] set, no crosshelper[BIN_PREFIX] and I
            # wasn't able to find a prefixed binary in any of the usual candidate
            # environment variables. I give up; I can only make this so easy.
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            echo "!! cross-helper: Can't assume a sane default for ${envtobin[$i]}"
            echo "!!               Maybe set crosshelper[\"BIN_PREFIX\"] in the script?"
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            return 1
          fi
        else
          foundbin=""
          # We want to make sure that the compiler actually exists. In my installation, arm-linux-gnueabihf-cc
          # does not exist.
          if [ ! -x "$(which "${crosshelper[BIN_PREFIX]}-${envtobin[$(($i + 1))]}" 2>/dev/null || echo "this-is-a-dummy")" ]; then
            # Try to find crosshelper[BIN_PREFIX]-{gcc,clang} or crosshelper[BIN_PREFIX]-{g++,clang++}
            declare -A binmap=([CC]="gcc clang" [CXX]="g++ clang++")
            for bin in ${binmap[${envtobin[$i]}]}; do
              trybin="$(which "${crosshelper[BIN_PREFIX]}-${bin}" 2>/dev/null || echo "this-is-a-dummy")"
              if [ -x "$trybin" ]; then
                foundbin="${trybin}"
                break
              fi
            done
            unset binmap[@]
          else
            foundbin="$(which "${crosshelper[BIN_PREFIX]}-${envtobin[$(($i + 1))]}")"
          fi
          if [ "x${foundbin}" == "x" ]; then
            echo "cross-helper: ERROR: Could not find a compiler for ${envtobin[$i]} with prefix"
            echo "                     ${crosshelper[BIN_PREFIX]}."
            declare -A binmap=([CC]="gcc clang" [CXX]="g++ clang++")
            echo "              Tried: "
            for bin in ${binmap[${envtobin[$i]}]}; do
              echo "                     ${crosshelper[BIN_PREFIX]}-${bin}"
            done
            unset binmap[@]
            echo "              Maybe try setting it explicitly via"
            echo "              1) source makepkg-cross-helper.sh [...] CC=[compiler]"
            echo "              2) makepkg [...] CC=[compiler]"
            echo "              3) Setting crossprefix[CC] in makepkg-cross-helper.sh"
            return 1;
          fi
          echo "cross-helper: Warning: Using ${foundbin}"
          echo "              If this is not correct, set the ${envtobin[$i]} environment variable, set"
          echo "              crosshelper[\"BIN_PREFIX\"] in the script, or use:"
          echo "              source /path/to/makepkg-cross-helper.sh ${envtobin[$i]}=value"
          crosshelper[${envtobin[$i]}]=${foundbin}
        fi
      fi
    fi
  done

  unset envtobin[@]
  unset crosshelper[guess_prefix]
  unset crosshelper[var_error]
}

###############################################################################
# Create a directory that contains scripts and symlinks to our real compile
# binaries using the generic names. For example, cc -> arm-linux-gnueabihf-cc.
# The scripts will embed LDFLAGS, CFLAGS and CXXFLAGS as necessary and the rest
# will be symlinked. This directory will be added to the beginning of PATH when
# running our build() and check() functions in order to hopefully make some
# misbehaving Makefile work. These Makefiles embed generic "sane" values into
# the Makefile such as "CC=cc." For hopefully obvious reasons, this doesn't
# work. Using this dummy path, we should be able to force it to load the proper
# cross-compiling binaries.
###############################################################################
create_dummy_path()
{
  if [ ! -d "${srcdir}/dummy-bin" ]; then
    mkdir ${srcdir}/dummy-bin
  fi

  for envvar in {CC,CXX,LD}; do
    if [ "x${crosshelper[$envvar]}" != "x" ]; then
      local binname=${crosshelper[$envvar]##*/}
      binname=${binname##*-}
      local flags=""
      if [ "$envvar" == "CC" ];
      then
        #CC doesn't use CCFLAGS, it uses CFLAGS
        flags=${crosshelper[CFLAGS]}
      else
        flags=${crosshelper[${envvar}FLAGS]}
      fi
      if [ "x${binname}" != "x" ]; then
        #It's possible for binname to be blank
        cat <<EOF >"${srcdir}/dummy-bin/${binname}"
#!/bin/bash
$(which ${crosshelper[$envvar]}) $flags "\$@"
EOF
        chmod +x "${srcdir}/dummy-bin/${binname}"
      fi
      if [ "$envvar" == "CC" ]; then
        #Create scripts for gcc/cc/clang
        if [ ! -e "${srcdir}/dummy-bin/cc" ]; then
          if [ -x "${crosshelper[CC]%-*}-cc" ]; then
            cat <<EOF >"${srcdir}/dummy-bin/cc"
#!/bin/bash
$(which ${crosshelper[CC]}) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/cc"
          else
            #Link cc to $CC
            cat <<EOF >"${srcdir}/dummy-bin/cc"
#!/bin/bash
$(which ${crosshelper[CC]}) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/cc"
          fi
        fi
        if [ ! -e "${srcdir}/dummy-bin/gcc" ]; then
          if [ -x "${crosshelper[CC]%-*}-gcc" ]; then
            #ln -s "${crosshelper[$envvar]%-*}-gcc" ${srcdir}/dummy-bin/gcc
            cat <<EOF >"${srcdir}/dummy-bin/gcc"
#!/bin/bash
$(which ${crosshelper[CC]%-*}-gcc) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/gcc"
          fi
        fi
        if [ ! -e "${srcdir}/dummy-bin/clang" ]; then
          if [ -x "${crosshelper[CC]%-*}-clang" ]; then
            #ln -s "${crosshelper[$envvar]%-*}-clang" ${srcdir}/dummy-bin/clang
            cat <<EOF >"${srcdir}/dummy-bin/clang"
#!/bin/bash
$(which ${crosshelper[CC]%-*}-clang) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/clang"
          fi
        fi
      elif [ "$envvar" == "CXX" ]; then
        #Create scripts for c++,g++,clang++
        if [ ! -e "${srcdir}/dummy-bin/c++" ]; then
          #The c++ script doesn't exist, check for which compiler we have
          if [ -x "${crosshelper[CXX]%-*}-c++" ]; then
            cat <<EOF >"${srcdir}/dummy-bin/c++"
#!/bin/bash
$(which ${crosshelper[CXX]%-*}-c++) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/cc"
          else
            #Link CXX to c++
            cat <<EOF >"${srcdir}/dummy-bin/c++"
#!/bin/bash
$(which ${crosshelper[CXX]}) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/c++"
          fi
        fi
        if [ ! -e "${srcdir}/dummy-bin/g++" ]; then
          if [ -x "${crosshelper[CXX]%-*}-g++" ]; then
            cat <<EOF >"${srcdir}/dummy-bin/g++"
#!/bin/bash
$(which ${crosshelper[CXX]%-*}-g++) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/g++"
          fi
        fi
        if [ ! -e "${srcdir}/dummy-bin/clang++" ]; then
          if [ -x "${crosshelper[CXX]%-*}-clang++" ]; then
            cat <<EOF >"${srcdir}/dummy-bin/clang++"
#!/bin/bash
$(which ${crosshelper[CXX]%-*}-clang++) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/clang++"
          fi
        fi
      elif [ "$envvar" == "LD" ]; then
        if [ ! -e "${srcdir}/dummy-bin/ld" ]; then
          if [ -x "${crosshelper[LD]%-*}-ld" ]; then
            cat <<EOF >"${srcdir}/dummy-bin/ld"
#!/bin/bash
$(which ${crosshelper[LD]%-*}-ld) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/ld"
          else
            #Link crosshelper[LD] to ld
            cat <<EOF >"${srcdir}/dummy-bin/ld"
#!/bin/bash
$(which ${crosshelper[LD]}) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/ld"
          fi
        fi
        if [ ! -e "${srcdir}/dummy-bin/lld" ]; then
          if [ -x "${crosshelper[LD]%-*}-lld" ]; then
            cat <<EOF >"${srcdir}/dummy-bin/lld"
#!/bin/bash
$(which ${crosshelper[LD]%-*}-lld) $flags "\$@"
EOF
            chmod +x "${srcdir}/dummy-bin/lld"
          fi
        fi
      fi
    fi
  done
  for bin in /usr/${crosshelper[BIN_PREFIX]}/bin/*; do
    shortbin="$(basename $bin)"
    if [ ! -e "${srcdir}/dummy-bin/${shortbin}" ]; then
      ln -s "$bin" "${srcdir}/dummy-bin/${shortbin}"
    fi
  done
}

remove_dummy_path()
{
  rm -R ${srcdir}/dummy-bin
}

###############################################################################
# This function is called as part of our new package() function. Packages have
# the ability to override certain variables as part of their package()
# function. We have to make sure to fix the overrides to be compliant with our
# expectations for cross-building packages.
###############################################################################
fix_overrides()
{
  #arch, groups, depends, optdepends, provides, conflicts, replaces, backup
  #Fix arch() to include our arch (if it doesn't already)
  if [ "${arch[*]}/any/" == "${arch[*]}" ] && [ "${arch[*]/${crosshelper[ARCH]}/}" == "${arch[*]}" ]; then
    arch[${#arch[@]}]=${crosshelper[ARCH]}
  fi

  add_prefixes groups depends optdepends provides conflicts replaces

  #Fix backup array to point to ${CROSSHELPER_PREFIX}/[backup]
  for i in ${!backup[@]}; do
    backup[$i]=${crosshelper[PKG_PREFIX]}/${backup[$i]}
  done
}

###############################################################################
# Add $crosshelper[PKG_PREFIX] to the beginning of all array elements
#
# Args:
#  $1: Array
###############################################################################
add_prefixes()
{
  while [ $# -ge 1 ]; do
    declare -n arr=$1
    for i in ${!arr[@]}; do
      if [ "${arr[$i]/${crosshelper[PKG_PREFIX]}/}" == "${arr[$i]}" ]; then
        arr[$i]=${crosshelper[PKG_PREFIX]}-${arr[$i]}
      fi
    done
    unset -n arr
    shift
  done
}

###############################################################################
# Make sure some critical environment variables are set
###############################################################################

crosshelper[var_error]=0
if [ "x${crosshelper[PKG_PREFIX]}" == "x" ]; then
  echo "To use the makepkg-cross-helper script, you must define the PKG_PREFIX variable"
  echo "to makepkg or when sourcing this script. Alternatively, set the value of"
  echo "crosshelper[\"PKG_PREFIX\"] in the script itself."
  echo
  echo "For example: makepkg [...] PKG_PREFIX=arm-linux-gnueabifh"
  echo "             source /path/to/makepkg-cross-helper.sh PREFIX=arm-linux-gnueabihf"
  echo
  echo "This variable is expanded out to form the prefix of the package name."
  crosshelper[var_error]=1
fi

if [ "x${crosshelper[ARCH]}" == "x" ]; then
  if [ ${crosshelper[var_error]} -eq 0 ]; then
    echo "To use the makepkg-cross-helper script, you must define the ARCH variable"
    echo "to makepkg or when sourcing this script. Alternatively, set the value of"
    echo "crosshelper[ARCH] in the script itself."
    echo
    echo "For example: makepkg [...] ARCH=armv7l"
    echo "             source /path/to/makepkg-cross-helper.sh ARCH=armvl7"
  else
    echo "ARCH is also missing. You must specify it as an argument to makepkg as"
    echo "well."
  fi
  echo
  echo "The ARCH variable is the architecture of the package to build. This might be"
  echo "something like armv7l, sparc, mips, etc. If cross-building for ARM, make sure to"
  echo "know specifically which arm arch you are targeting. For example, armv6h and"
  echo "armv7l are two entirely different architectures."
  crosshelper[var_error]=1
fi

if [ ${crosshelper[var_error]} -eq 1 ]; then
  if [ "${0/makepkg/}" != "$0" ]; then
    unset crosshelper[var_error]
    exit 1
  fi
fi
unset crosshelper[var_error]

setup_env

###############################################################################
# Explicitly set $pkgbase if it isn't already, we don't necessarily want it
# using our new package names.
##############################################################################

if [ "$pkgbase" == "" ]; then
  pkgbase=$pkgname
fi

###############################################################################
# Change all packages in $pkgname array to ${triplet}-pkgname
###############################################################################

declare -a original_pkgname=("${pkgname[@]}")

add_prefixes pkgname

echo -n "cross-helper: Configuring package names... "
if [ ${#original_pkgname[@]} -gt 1 ]; then
  #If there is more than one package in $pkgname, then we have to add
  #functions for package_${new-packagename}() that point to the original
  #packinging functions
  for i in ${!original_pkgname[@]}; do
    eval "package_${crosshelper[PKG_PREFIX]}-${original_pkgname[$i]}() { declare -A crosshelper; load_settings; setup_env; export crosshelper; package_${original_pkgname[$i]}; fix_overrides; }"
  done
else
  #Rename package() to original_package()
  eval "$(echo "original_package()"; declare -f package | tail -n +2)"
  #Add a call to fix_overrides (see below)
  eval "package(){ declare -A crosshelper; load_settings; setup_env; export crosshelper; original_package; fix_overrides; }"
fi

##############################################################################
# Update depends, makedepends, optdepends, checkdepends, provides, replaces,
# and groups to reflect triplet
##############################################################################

add_prefixes depends makedepends optdepends checkdepends provides conflicts replaces groups
echo "Done."

###############################################################################
# Automatic addition of architecture to arch=() array
###############################################################################

echo -n "cross-helper: Adding architecture... "
if [ "${arch[@]/any}" == "${arch[@]}" ] && [ "${arch[@]/${crosshelper[ARCH]}/}" == "${arch[@]}" ]; then
  arch[${#arch[@]}]=${crosshelper[ARCH]}
fi
echo "Done."

###############################################################################
# Override the build() function to set aliases for hard-coded common binary
# names
###############################################################################

echo -n "cross-helper: Hooking check() and build()..."

#Credit to Evan Broder @ StackOverflow
#https://stackoverflow.com/questions/1203583/how-do-i-rename-a-bash-function/1369211#1369211

#Rename build() to original_build()
eval "$(echo "original_build()"; declare -f build | tail -n +2)"

eval "$(echo "original_check()"; declare -f check | tail -n +2)"

check()
{
  declare -A crosshelper
  load_settings
  setup_env
  export crosshelper
  PATH="${srcdir}/dummy-bin:$PATH" original_check
  ret=$?
  return $ret
}

#Define a new build() function that sets aliases for 'cc', 'gcc', 'ld', 'ar',
#and 'ranlib' to their cross-compiling counterparts, call original_build()
#and then unset the aliases.
build()
{
  declare -A crosshelper
  load_settings
  setup_env
  #We're going to create a dummy path, but leave it until makepkg is done
  #packaging.
  create_dummy_path
  export crosshelper
  # Call the original build function
  PATH="${srcdir}/dummy-bin:$PATH" original_build
  #Don't remove the dummy path just yet. We want to make sure tidy_install can
  #find it.
  ret=$?
  return $ret
}
echo "Done."

###############################################################################
# makepkg erases the environment in between calls to build(), check(), etc.
# So, this function stores the initial computed values of various crosshelper
# variables so that they can be easily re-loaded later.
###############################################################################
settingslist=""
for key in ${!crosshelper[@]}; do
  settingslist+="crosshelper[$key]=\"${crosshelper[$key]}\""$'\n'
done
eval "$(cat <<EOF
load_settings()
{
  $settingslist
}
EOF
)"

###############################################################################
# If you're squeemish, look away now. I'm going to do some really shady shit to
# get options=(strip) to work. I'm going to modify makepkg's own tidy_install()
# function to give it a new PATH variable that points to ${srcdir}/dummy-bin --
# that contains all of our cross-compile binaries (including strip).
###############################################################################
eval "$(echo "original_tidy_install()"; declare -f tidy_install | tail -n +2)"
tidy_install()
{
  PATH=${srcdir}/dummy-bin:$PATH original_tidy_install
}

###############################################################################
# In multi-package PKGBUILD files, we can't tear down our dummy-bin
# immediately. It's best to remove it after leaving fakeroot
###############################################################################
if [ ${#pkgname[@]} -gt 0 ]; then
  eval "$(echo "original_run_split_packaging()"; declare -f run_split_packaging | tail -n +2)"
run_split_packaging()
{
  declare -A crosshelper
  load_settings
  setup_env
  export crosshelper
  original_run_split_packaging
  remove_dummy_path
}
else
  eval "$(echo "original_run_single_packaging()"; declare -f run_single_packaging | tail -n +2)"
run_single_packaging()
{
  declare -A crosshelper
  load_settings
  setup_env
  export crosshelper
  original_run_single_packaging
  remove_dummy_path
}
fi
