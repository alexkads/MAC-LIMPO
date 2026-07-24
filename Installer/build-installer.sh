#!/bin/bash
#
# Gera build/MAC-LIMPO-<version>.pkg — um instalador nativo do macOS que coloca
# o app em /Applications e o desinstalador em /usr/local/bin.
#
#     ./Installer/build-installer.sh
#
# Rode como seu usuário normal: compilar precisa da identidade de assinatura no
# login keychain, que o root não alcança. Instalar o .pkg resultante é o que
# precisa de direitos administrativos, e o instalador os pede sozinho — que é
# exatamente o motivo de distribuir um .pkg em vez de um script de shell.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MAC-LIMPO"
VERSION="$(tr -d ' \n' < VERSION 2>/dev/null || echo '1.1.0')"
IDENTIFIER="com.alexkads.${APP_NAME}.pkg"
STAGING="build/pkgroot"
COMPONENT="build/component.pkg"
OUTPUT="build/${APP_NAME}-${VERSION}.pkg"

# Assinar um .pkg exige um certificado "Developer ID Installer", que um Personal
# Team gratuito não recebe. Defina isto se algum dia tiver um:
#     INSTALLER_IDENTITY="Developer ID Installer: ..." ./Installer/build-installer.sh
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-}"

if [ "$(id -u)" -eq 0 ]; then
    echo "error: rode como seu usuário normal, não com sudo." >&2
    exit 1
fi

# ---------------------------------------------------------------- build

echo "==> Compilando e assinando o app"
./Scripts/bundle-app.sh >/dev/null

if [ ! -d "build/app/${APP_NAME}.app" ]; then
    echo "error: build/app/${APP_NAME}.app não existe após o build" >&2
    exit 1
fi

# ---------------------------------------------------------------- stage

echo "==> Montando o payload"
rm -rf "$STAGING" "$COMPONENT" "$OUTPUT"
mkdir -p "$STAGING/Applications"
mkdir -p "$STAGING/usr/local/bin"

cp -R "build/app/${APP_NAME}.app" "$STAGING/Applications/${APP_NAME}.app"
cp Installer/uninstall-mac-limpo "$STAGING/usr/local/bin/mac-limpo-uninstall"

# Os modos são gravados no pacote a partir da staging area, então são definidos
# aqui e não no postinstall.
chmod 755 "$STAGING/usr/local/bin/mac-limpo-uninstall"
chmod +x Installer/Scripts/preinstall Installer/Scripts/postinstall

# ---------------------------------------------------------------- package

# O pkgbuild emite um bloco <relocate> para todo app bundle que encontra, o que
# faz o instalador procurar no Spotlight uma cópia existente daquele bundle
# identifier e instalar *lá* em vez do caminho do pacote. Com um build de
# desenvolvimento em ./build, isso silenciosamente desvia a instalação de
# /Applications e sobrescreve a cópia de trabalho como root. Desligue.
echo "==> Desativando relocation de bundle"
COMPONENT_PLIST="build/component.plist"
pkgbuild --analyze --root "$STAGING" "$COMPONENT_PLIST" >/dev/null
BUNDLE_COUNT=$(/usr/libexec/PlistBuddy -c "Print" "$COMPONENT_PLIST" | grep -c "BundleIsRelocatable" || true)
for ((i = 0; i < BUNDLE_COUNT; i++)); do
    plutil -replace "${i}.BundleIsRelocatable" -bool NO "$COMPONENT_PLIST"
done
echo "    relocation desativada para $BUNDLE_COUNT bundle(s)"

echo "==> Construindo o component package"
pkgbuild \
    --root "$STAGING" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --scripts Installer/Scripts \
    --component-plist "$COMPONENT_PLIST" \
    --ownership recommended \
    --install-location / \
    "$COMPONENT" >/dev/null

echo "==> Construindo o product archive"
PRODUCTBUILD_ARGS=(
    --distribution Installer/Distribution.xml
    --resources Installer/Resources
    --package-path build
)
if [ -n "$INSTALLER_IDENTITY" ]; then
    echo "    assinando com: $INSTALLER_IDENTITY"
    PRODUCTBUILD_ARGS+=(--sign "$INSTALLER_IDENTITY")
fi
productbuild "${PRODUCTBUILD_ARGS[@]}" "$OUTPUT" >/dev/null

rm -rf "$STAGING" "$COMPONENT" "$COMPONENT_PLIST"

# ---------------------------------------------------------------- verify

echo
echo "==> Verificando"
EXPANDED=$(mktemp -d)
pkgutil --expand "$OUTPUT" "$EXPANDED/pkg"

# Protege a correção do relocation: se um bloco <relocate> voltar, a instalação
# cai silenciosamente em outro lugar que não /Applications, o que é bem difícil
# de diagnosticar pelo sintoma.
if grep -q "<relocate>" "$EXPANDED/pkg/component.pkg/PackageInfo"; then
    echo "error: o pacote ainda contém um bloco <relocate> — a instalação seria" >&2
    echo "       redirecionada para qualquer cópia encontrada pelo Spotlight." >&2
    rm -rf "$EXPANDED"
    exit 1
fi
echo "    sem relocation de bundle ✓"

echo "    payload:"
# As entradas ._* são AppleDouble: o pkgbuild guarda assim os extended
# attributes de cada arquivo. O macOS coloca com.apple.provenance em tudo que
# ele grava e não deixa removê-lo, então elas sempre aparecem. São metadados
# reaplicados na instalação, não arquivos que sobram no disco — omitidas aqui
# só para a listagem ficar legível.
lsbom -p MUGf "$EXPANDED/pkg/component.pkg/Bom" 2>/dev/null \
    | grep -vE '\._[^/]*$' \
    | grep -vE '^\S+\s+\S+\s+\S+\s+\.($|/(Applications|usr)?(/local)?(/bin)?$)' \
    | sed 's/^/      /'
rm -rf "$EXPANDED"

SIZE=$(du -h "$OUTPUT" | cut -f1)
echo
echo "Built:  $OUTPUT  ($SIZE)"
if [ -z "$INSTALLER_IDENTITY" ]; then
    echo "Signed: não — precisa de um certificado 'Developer ID Installer'."
    echo "        Um .pkg construído localmente instala normalmente. Um que tenha"
    echo "        sido baixado ou recebido por AirDrop fica em quarentena, e o"
    echo "        macOS o recusa até você clicar com o botão direito e escolher Abrir."
fi
echo
echo "Instalar:    open $OUTPUT"
echo "Desinstalar: sudo mac-limpo-uninstall"
