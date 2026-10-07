.PHONY: build release test strings app installer dmg install uninstall format lint clean help docs docs-serve docs-deploy

CONFIGURATION ?= release
VERSION := $(shell tr -d ' \n' < VERSION)

help:
	@echo "MAC-LIMPO — limpeza de disco para macOS  (v$(VERSION))"
	@echo
	@echo "  make build       Build de debug"
	@echo "  make release     Build de release"
	@echo "  make test        Roda os testes unitários"
	@echo "  make run         Compila e abre o app (ícone de lixeira na barra de menus)"
	@echo "  make strings     Atualiza o catálogo de traduções (Localization/Localizable.xcstrings)"
	@echo "  make app         Monta e assina build/app/MAC-LIMPO.app"
	@echo "  make installer   Gera build/MAC-LIMPO-$(VERSION).pkg"
	@echo "  make docs        Gera o site (MkDocs) em build/site/"
	@echo "  make docs-serve  Pré-visualiza o site em http://127.0.0.1:8000"
	@echo "  make docs-deploy Publica o site no GitHub Pages (branch gh-pages)"
	@echo "  make dmg         Gera build/MAC-LIMPO-$(VERSION).dmg (arrastar-e-soltar)"
	@echo "  make install     Gera e abre o .pkg (pede senha de administrador)"
	@echo "  make uninstall   Remove o que o instalador colocou (precisa de sudo)"
	@echo "  make format      swiftformat + swiftlint"
	@echo "  make clean       Limpa .build/ e build/ (mantém build/.gitkeep)"

build:
	swift build

release:
	swift build -c release

test:
	swift test

run:
	swift run

strings:
	./Scripts/sync-strings.sh

app:
	./Scripts/bundle-app.sh

installer:
	./Installer/build-installer.sh

dmg:
	./create_installer.sh

install: installer
	open build/MAC-LIMPO-$(VERSION).pkg

uninstall:
	sudo /usr/local/bin/mac-limpo-uninstall

format:
	swiftformat . && swiftlint

clean:
	rm -rf .build
	find build -mindepth 1 ! -name .gitkeep -delete

# ---------------------------------------------------------------- site (MkDocs)
DOCS_VENV ?= .venv

$(DOCS_VENV)/bin/mkdocs: requirements-docs.txt
	python3 -m venv $(DOCS_VENV)
	$(DOCS_VENV)/bin/pip install -q -r requirements-docs.txt

docs: $(DOCS_VENV)/bin/mkdocs
	$(DOCS_VENV)/bin/mkdocs build --strict

docs-serve: $(DOCS_VENV)/bin/mkdocs
	$(DOCS_VENV)/bin/mkdocs serve

# Publica o site na branch gh-pages (o GitHub Pages serve essa branch).
docs-deploy: $(DOCS_VENV)/bin/mkdocs
	$(DOCS_VENV)/bin/mkdocs gh-deploy --strict --force --message "docs: publica o site ({sha})"
