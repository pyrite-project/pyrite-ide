#!/bin/sh
# Xcode 27 beta's ld64 emits dylibs that dyld refuses to load ("mis-aligned
# LINKEDIT string pool") whenever chained fixups are enabled, which happens
# for any deployment target >= 12.0. cargo drops rustflags for proc-macro
# host units when --target is passed, so the linker flag has to be appended
# here instead. See the post_install hook in the Podfile.
exec rustc "$@" -C link-arg=-Wl,-no_fixup_chains
