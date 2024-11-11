#!/usr/bin/make -f

## Copyright (C) 2012 - 2021 ENCRYPTED SUPPORT LP <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

# Environment variables (set in builder.conf) that should be made available to
# template build scripts
TEMPLATE_ENV_WHITELIST += DERIVATIVE_APT_REPOSITORY_OPTS WHONIX_ENABLE_TOR \
    WHONIX_DIR WHONIX_TBB_VERSION

# set APPMENUS_DIR only when building a kicksecure template
ifeq (1,$(TEMPLATE_BUILDER))
ifneq (,$(findstring kicksecure, $(TEMPLATE_FLAVOR)))
APPMENUS_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
endif
endif
