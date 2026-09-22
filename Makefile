# Nikamat - kaannos, .app-paketointi ja asennus.
#
#   make            kaanna ja paketoi dist/Nikamat.app
#   make install    asenna ~/Applications-hakemistoon
#   make run        kaanna, paketoi ja kaynnista
#   make test       aja yksikkotestit
#   make autostart  kaynnista jatkossa kirjautumisen yhteydessa
#   make clean      poista kaannostuotokset

APP_NAME    := Nikamat
BUNDLE_ID   := fi.esapalosaari.nikamat
VERSION     := 1.0.0
CONFIG      ?= release

BUILD_DIR   := .build/$(CONFIG)
APP_BUNDLE  := dist/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app
AGENT_PLIST := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist

.PHONY: all build app install run test autostart unautostart uninstall clean

all: app

build:
	swift build -c $(CONFIG)

test:
	swift test

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	sed -e 's/@APP_NAME@/$(APP_NAME)/g' \
	    -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' \
	    -e 's/@VERSION@/$(VERSION)/g' \
	    Resources/Info.plist.in > $(APP_BUNDLE)/Contents/Info.plist
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	# Ad-hoc allekirjoitus: ilman kehittajasertifikaattia tama on se mita
	# saadaan, ja se riittaa paikalliseen kayttoon.
	codesign --force --sign - --timestamp=none $(APP_BUNDLE)
	@echo "Valmis: $(APP_BUNDLE)"

install: app
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALLED)
	cp -R $(APP_BUNDLE) $(INSTALLED)
	@echo "Asennettu: $(INSTALLED)"

run: app
	-pkill -x $(APP_NAME) || true
	open $(APP_BUNDLE)

autostart: install
	mkdir -p $(HOME)/Library/LaunchAgents
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>Label</key><string>$(BUNDLE_ID)</string>' \
	  '  <key>ProgramArguments</key>' \
	  '  <array><string>/usr/bin/open</string><string>-a</string><string>$(INSTALLED)</string></array>' \
	  '  <key>RunAtLoad</key><true/>' \
	  '</dict></plist>' > $(AGENT_PLIST)
	-launchctl unload $(AGENT_PLIST) 2>/dev/null || true
	launchctl load $(AGENT_PLIST)
	@echo "Kaynnistyy jatkossa kirjautumisen yhteydessa."

unautostart:
	-launchctl unload $(AGENT_PLIST) 2>/dev/null || true
	rm -f $(AGENT_PLIST)
	@echo "Automaattikaynnistys poistettu."

uninstall: unautostart
	-pkill -x $(APP_NAME) || true
	rm -rf $(INSTALLED)

clean:
	rm -rf .build dist
