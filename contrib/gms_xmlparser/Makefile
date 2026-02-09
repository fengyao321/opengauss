# contrib/gms_xmlparser/Makefile
MODULE_big = gms_xmlparser
OBJS = gms_xmlparser.o

EXTENSION = gms_xmlparser
DATA = gms_xmlparser--1.0.sql

exclude_option = -fPIE
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
override CPPFLAGS := -fstack-protector-strong $(filter-out $(exclude_option),$(CPPFLAGS)) -I$(LIBXML_INCLUDE_PATH)/libxml2
REGRESS = gms_xmlparser

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/gms_xmlparser
regress_home = $(top_builddir)/src/test/regress
REGRESS_OPTS = -c 0 -d 1 -r 1 -p 25633 --single_node -w --keep_last_data=false  \
               --regconf=$(regress_home)/regress.conf                           \
               --temp-config=$(regress_home)/make_fastcheck_postgresql.conf
include $(top_srcdir)/contrib/contrib-global.mk
endif
