.PHONY: build test clean

build:
	./scripts/build.sh

test: build
	/usr/bin/ruby Tests/relay_integration_test.rb

clean:
	rm -rf .build dist
