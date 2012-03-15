# Makefile - for rebox2
#

##----------------------------------------------------------------------
##  YOU MUST EDIT THE FOLLOWING LINES
##----------------------------------------------------------------------

# Name of your emacs binary
EMACS=emacs

# Where local software is found
prefix=/usr/local

# Where local lisp files go.
lispdir=$(prefix)/share/emacs/site-lisp

##----------------------------------------------------------------------
## YOU MAY NEED TO EDIT THESE
##----------------------------------------------------------------------

# Using emacs in batch mode.

BATCH=$(EMACS) -batch -q -no-site-file -eval                             			\
  "(setq load-path (cons \".\" (cons \"$(lispdir)\" load-path)))"

# Specify the byte-compiler for compiling org-mode files
ELC= $(BATCH) -f batch-byte-compile

# How to copy the lisp files and elc files to their distination.
CP = install -m 644

##----------------------------------------------------------------------
##  BELOW THIS LINE ON YOUR OWN RISK!
##----------------------------------------------------------------------

# The following variables need to be defined by the maintainer
LISPFILES   = 	rebox2.el	 	\

ELCFILES    = $(LISPFILES:.el=.elc)

default: $(ELCFILES)

install: install-lisp

install-lisp: $(LISPFILES) $(ELCFILES)
	install -d -m 755 $(DESTDIR)$(lispdir)
	$(CP) $(LISPFILES) $(DESTDIR)$(lispdir)
	$(CP) $(ELCFILES) $(DESTDIR)$(lispdir)

clean: cleanelc
cleanelc:
	rm -f $(ELCFILES)

.el.elc:
	$(ELC) $<