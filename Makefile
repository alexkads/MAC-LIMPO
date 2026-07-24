.PHONY: build release test app installer dmg install uninstall format lint clean help

CONFIGURATION ?= release
VERSION := $(shell tr -d ' \n' < VERSION)

help:
	@echo "MAC-LIMPO — limpeza de disco para macOS  (v$(VERSION))"
	@echo
	@echo "  make build       Build de debug"
	@echo "  make release     Build de release"
	@echo "  make test        Roda os testes unitários"
	@echo "  make run         Compila e abre o app (ícone de lixeira na barra de menus)"
	@echo "  make app         Monta e assina build/app/MAC-LIMPO.app"
	@echo "  make installer   Gera build/MAC-LIMPO-$(VERSION).pkg"
	@echo "  make dmg         Gera MAC-LIMPO.dmg (distribuição por arrastar-e-soltar)"
	@echo "  make install     Gera e abre o .pkg (pede senha de administrador)"
	@echo "  make uninstall   Remove o que o instalador colocou (precisa de sudo)"
	@echo "  make format      swiftformat + swiftlint"
	@echo "  make clean       Remove .build/ e build/"

build:
	swift build

release:
	swift build -c release

test:
	swift test

run:
	swift run

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
	rm -rf .build build
