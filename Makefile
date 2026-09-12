# Raccourcis de développement. `make help` pour la liste.
.PHONY: help generate open test-core build-check clean

PROJECT := Scan3D.xcodeproj
SCHEME  := Scan3D

help:
	@echo "make generate    - régénère le projet Xcode depuis project.yml"
	@echo "make open        - génère puis ouvre le projet dans Xcode"
	@echo "make test-core   - lance les tests du paquet Scan3DCore (sur Mac)"
	@echo "make build-check - compile l'app iOS sans signature"
	@echo "make clean       - supprime le projet généré et les builds"

generate:
	xcodegen generate

open: generate
	open $(PROJECT)

test-core:
	cd Packages/Scan3DCore && swift test

build-check: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO -quiet build

clean:
	rm -rf $(PROJECT) build .build Packages/Scan3DCore/.build
