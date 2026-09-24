.PHONY: all build release test clean install uninstall

all: build

build:
	swift build

release:
	swift build -c release

test:
	swift test

install:
	./install.sh

clean:
	swift package clean
	rm -rf .build
