### Get version from Relax-and-Recover itself
name = rear
version = $(shell awk 'BEGIN { FS="=" } /^VERSION=/ { print $$2}' usr/sbin/rear)
gitdate = $(shell git log -n 1 --format="%ai")
date = $(shell date --date="$(gitdate)" +%Y%m%d%H%M)

### Get the branch information from git
git_ref = $(shell git symbolic-ref -q HEAD)
git_branch ?= $(lastword $(subst /, ,$(git_ref)))
git_branch ?= HEAD

prefix = /usr
sysconfdir = /etc
sbindir = $(prefix)/sbin
datadir = $(prefix)/share
mandir = $(datadir)/man
localstatedir = /var

DESTDIR=
OFFICIAL=

distversion=$(version)
rpmrelease=
ifeq ($(OFFICIAL),)
    distversion=$(version)-git$(date)
    rpmrelease=.git$(date)
endif


.PHONY: doc

all:
	@echo "Nothing to build. Use \`make help' for more information."

help:
	@echo -e "Relax-and-Recover make targets:\n\
\n\
  validate        - Check source code\n\
  install         - Install Relax-and-Recover to DESTDIR (may replace files)\n\
  uninstall       - Uninstall Relax-and-Recover from DESTDIR (may remove files)\n\
  dist            - Create tar file\n\
  deb             - Create DEB package\n\
  rpm             - Create RPM package\n\
\n\
Relax-and-Recover make variables (optional):\n\
\n\
  DESTDIR=        - Location to install/uninstall\n\
  OFFICIAL=       - Build an official release\n\
"

clean:

### You can call 'make validate' directly from your .git/hooks/pre-commit script
validate:
	@echo -e "\033[1m== Validating scripts and configuration ==\033[0;0m"
	find etc/ usr/share/rear/conf/ -name '*.conf' | xargs bash -n
	bash -n usr/sbin/rear
	find . -name '*.sh' | xargs bash -n
	find -L . -type l

man:
	make -C doc man

doc:
	make -C doc docs

install-config:
	@echo -e "\033[1m== Installing configuration ==\033[0;0m"
	install -d -m0755 $(DESTDIR)$(sysconfdir)/rear/
	-[[ ! -e $(DESTDIR)$(sysconfdir)/rear/local.conf ]] && \
		install -Dp -m0644 etc/rear/local.conf $(DESTDIR)$(sysconfdir)/rear/local.conf
	cp -a etc/rear/{mappings,templates} $(DESTDIR)$(sysconfdir)/rear/
	-find $(DESTDIR)$(sysconfdir)/rear/ -name '.gitignore' -exec rm -rf {} \; &>/dev/null

install-bin:
	@echo -e "\033[1m== Installing binary ==\033[0;0m"
	install -Dp -m0755 usr/sbin/rear $(DESTDIR)$(sbindir)/rear
	sed -i -e 's,^CONFIG_DIR=.*,CONFIG_DIR="$(sysconfdir)/rear",' \
		-e 's,^SHARE_DIR=.*,SHARE_DIR="$(datadir)/rear",' \
		-e 's,^VAR_DIR=.*,VAR_DIR="$(localstatedir)/lib/rear",' \
		$(DESTDIR)$(sbindir)/rear

install-data:
	@echo -e "\033[1m== Installing scripts ==\033[0;0m"
	install -d -m0755 $(DESTDIR)$(datadir)/rear/
	cp -a usr/share/rear/. $(DESTDIR)$(datadir)/rear/
	-find $(DESTDIR)$(datadir)/rear/ -name '.gitignore' -exec rm -rf {} \; &>/dev/null

install-var:
	@echo -e "\033[1m== Installing working directory ==\033[0;0m"
	install -d -m0755 $(DESTDIR)$(localstatedir)/lib/rear/
	install -d -m0755 $(DESTDIR)$(localstatedir)/log/rear/

install-doc:
	@echo -e "\033[1m== Installing documentation ==\033[0;0m"
	make -C doc install
	sed -i -e 's,/etc,$(sysconfdir),' \
		-e 's,/usr/sbin,$(sbindir),' \
		-e 's,/usr/share,$(datadir),' \
		-e 's,/usr/share/doc/packages,$(datadir)/doc,' \
		$(DESTDIR)$(mandir)/man8/rear.8

install: validate man install-config install-bin install-data install-var install-doc

uninstall:
	@echo -e "\033[1m== Uninstalling Rear ==\033[0;0m"
	-rm -v $(DESTDIR)$(sbindir)/rear
	-rm -v $(DESTDIR)$(mandir)/man8/rear.8
	-rm -rv $(DESTDIR)$(datadir)/rear/
#	rm -rv $(DESTDIR)$(sysconfdir)/rear/
#	rm -rv $(DESTDIR)$(localstatedir)/lib/rear/

dist: clean validate man
	@echo -e "\033[1m== Building archive $(name)-$(distversion) ==\033[0;0m"
	sed -i \
		-e 's#^Source:.*#Source: $(name)-$(distversion).tar.bz2#' \
		-e 's#^Version:.*#Version: $(version)#' \
		-e 's#^\(Release: *[0-9]\+\)#\1$(rpmrelease)#' \
		contrib/$(name).spec
	git ls-tree -r --name-only --full-tree $(git_branch) | \
		tar -cjf $(name)-$(distversion).tar.bz2 --transform='s,^,$(name)-$(version)/,S' --files-from=-
	git checkout contrib/$(name).spec

rpm: dist
	@echo -e "\033[1m== Building RPM package $(name)-$(distversion)==\033[0;0m"
	rpmbuild -tb --clean \
		--define "_rpmfilename %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
		--define "debug_package %{nil}" \
		--define "_rpmdir %(pwd)" $(name)-$(distversion).tar.bz2

obs: BUILD_DIR = /tmp/rear.$(distversion)
obs: obsrev = $(shell osc cat Archiving:Backup:Rear rear-snapshot rear.spec | grep Version | cut -d' ' -f2)
obs: dist
	@echo -e "\033[1m== Updating OBS $(name)-$(distversion)==\033[0;0m"
ifneq ($(obsrev),$(distversion))
	
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)
	
	cp $(name)-$(distversion).tar.bz2 $(BUILD_DIR)/
	
	osc co -c Archiving:Backup:Rear rear-snapshot -o $(BUILD_DIR)/rear-snapshot
	
	-osc del $(BUILD_DIR)/rear-snapshot/*.tar.bz2
	cp $(name)-$(distversion).tar.bz2 $(BUILD_DIR)/rear-snapshot/
	osc add $(BUILD_DIR)/rear-snapshot/$(name)-$(distversion).tar.bz2

	sed -i \
	-e 's#^Source:.*#Source: $(name)-$(distversion).tar.bz2#' \
	-e 's#^Version:.*#Version: $(version)#' \
	-e 's#^\(Release: *[0-9]\+\)#\1$(rpmrelease)#' \
	$(BUILD_DIR)/rear-snapshot/rear.spec
	cd $(BUILD_DIR) ; osc ci -m "Git -> OBS rev $REV" rear-snapshot
	
	rm -rf $(BUILD_DIR)
endif
