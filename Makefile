.PHONY: all build release test clean install uninstall app run-app runapp dmg tag

all: build

build:
	swift build

release:
	swift build -c release

app:
	./scripts/build-app.sh

dmg:
	./scripts/build-release-dmg.sh

tag:
	./scripts/tag.sh $(TAG)

run-app: app
	pkill -x "Secret Manager" 2>/dev/null || pkill -x SecApp 2>/dev/null || true
	open "build/Secret Manager.app"

runapp: run-app

test:
	swift test

install:
	./install.sh

uninstall:
	./uninstall.sh

clean:
	swift package clean
	rm -rf .build build
