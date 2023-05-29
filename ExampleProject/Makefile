.PHONY : swiftshield

swiftshield:
	cd ../ && make build && make package
	../.build/apple/Products/Release/_PRODUCT/bin/swiftshield obfuscate -p ./ExampleProject.xcodeproj -s ExampleProject -v -i RswiftResources
	open ./ExampleProject.xcodeproj
	open ./swiftshield-output