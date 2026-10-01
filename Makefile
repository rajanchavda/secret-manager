.PHONY: all build release test clean install uninstall app run-app runapp

all: build

build:
	swift build

release:
	swift build -c release

app:
	./scripts/build-app.sh

run-app: app
	pkill -x SecApp 2>/dev/null || true
	open build/SecApp.app

runapp: run-app

test:
	swift test

install:
	./install.sh

clean:
	swift package clean
	rm -rf .build build
