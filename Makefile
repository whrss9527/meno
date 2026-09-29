APP_NAME := Meno
CONFIG ?= release

.PHONY: all build app run test install zip clean

all: app

## Compile the Swift package.
build:
	swift build -c $(CONFIG)

## Assemble and sign build/Meno.app.
app:
	CONFIG=$(CONFIG) ./scripts/build-app.sh

## Build and launch the app bundle.
run: app
	open build/$(APP_NAME).app

## Run the unit tests.
test:
	swift test

## Copy the app into /Applications.
install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "build/$(APP_NAME).app" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

## Create a distributable zip next to the app bundle.
zip: app
	cd build && rm -f $(APP_NAME).zip && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME).zip
	@echo "Created build/$(APP_NAME).zip"

clean:
	rm -rf .build build
