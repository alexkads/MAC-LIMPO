#!/bin/bash
#
# Monta e assina build/app/MAC-LIMPO.app a partir do build do SwiftPM.
#
# O SwiftPM produz apenas um executável solto, mas um app de menu bar precisa de
# um bundle de verdade com LSUIElement — então o bundle é montado aqui em vez de
# manter um .xcodeproj versionado no repositório.
#
# Rode como seu usuário normal: a assinatura usa a identidade do login keychain,
# que o root não enxerga.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MAC-LIMPO"
BUNDLE_ID="com.alexkads.${APP_NAME}"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_DIR=".build/${CONFIGURATION}"

# O bundle montado fica em build/app/, deliberadamente fora da raiz do repo: um
# .pkg instala em /Applications como root, e manter a cópia de desenvolvimento
# num caminho que nenhum instalador escreve evita builds futuros esbarrando em
# arquivos pertencentes ao root.
#
# Sobrescrevível: APP=build/Preview.app ./Scripts/bundle-app.sh
APP="${APP:-build/app/${APP_NAME}.app}"

# Fonte única de verdade da versão (SemVer). BUILD_NUMBER é o CFBundleVersion
# monotônico; sobrescreva ao cortar um build: BUILD_NUMBER=3 ./Scripts/bundle-app.sh
VERSION="$(tr -d ' \n' < VERSION 2>/dev/null || echo '1.3.3')"
BUILD_NUMBER="${BUILD_NUMBER:-7}"

if [ "$(id -u)" -eq 0 ]; then
    echo "error: rode como seu usuário normal, não com sudo." >&2
    echo "       a assinatura precisa da identidade do login keychain." >&2
    exit 1
fi

# ---------------------------------------------------------------- identidade

# Descoberta no keychain em vez de fixada no script, para que um clone compile
# na máquina de quem for. Developer ID vem primeiro porque é a única que pode
# ser notarizada; ad-hoc ("-") é o último recurso e mantém o comportamento
# histórico deste repositório.
#
# Sobrescreva com: IDENTITY="Developer ID Application: ..." ./Scripts/bundle-app.sh
if [ -z "${IDENTITY:-}" ]; then
    IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/Developer ID Application/ { print $2; exit }'
    )
fi
if [ -z "${IDENTITY:-}" ]; then
    IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/Apple Development/ { print $2; exit }'
    )
fi
if [ -z "${IDENTITY:-}" ]; then
    IDENTITY="-"
    echo "note: nenhuma identidade de assinatura no keychain — usando ad-hoc."
    echo "      um app ad-hoc instala e roda localmente, mas não pode ser notarizado."
fi

# ---------------------------------------------------------------- build

echo "==> Compilando ($CONFIGURATION)"
swift build -c "$CONFIGURATION" -Xswiftc -O --product "$APP_NAME"

if [ ! -f "$BUILD_DIR/$APP_NAME" ]; then
    echo "error: executável não encontrado em $BUILD_DIR/$APP_NAME" >&2
    exit 1
fi

# ---------------------------------------------------------------- bundle

echo "==> Montando $APP"

# Menciona a sobra da época em que o bundle era montado na raiz do repositório,
# mas nunca bloqueia por causa dela: nada mais lê aquele caminho, então é lixo
# antigo e não um erro que o usuário precise limpar antes de trabalhar.
LEGACY_APP="${APP_NAME}.app"
if [ -d "$LEGACY_APP" ]; then
    echo "note: ./$LEGACY_APP é sobra do bundling antigo e não é mais usado."
    echo "      remova quando for conveniente:  rm -rf $LEGACY_APP"
fi

if [ -d "$APP" ] && [ ! -w "$APP" ] 2>/dev/null; then
    echo "error: $APP não é gravável. remova com: sudo rm -rf $APP" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod 755 "$APP/Contents/MacOS/$APP_NAME"

# O Info.plist é sempre reescrito a partir daqui — nunca copiado de um arquivo
# existente, que pode estar com versão velha.
cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 alexkads. All rights reserved.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MAC-LIMPO needs permission to execute shell commands for cleaning operations.</string>
</dict>
</plist>
EOF

echo "APPL????" > "$APP/Contents/PkgInfo"

# ---------------------------------------------------------------- ícone

if [ -d "Assets.xcassets" ]; then
    echo "==> Compilando ícone"
    xcrun actool Assets.xcassets \
        --compile "$APP/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /tmp/assetcatalog_generated_info.plist > /dev/null || \
        echo "warning: compilação do ícone reportou problemas (seguindo sem ícone customizado)."
else
    echo "warning: Assets.xcassets não encontrado — seguindo sem ícone customizado."
fi

# ---------------------------------------------------------------- assinatura

echo "==> Assinando com: $IDENTITY"

# Quarentena precisa sair antes da assinatura: um xattr adicionado depois
# invalida o selo, e um adicionado antes vai junto para dentro do .pkg.
xattr -cr "$APP"

if [ "$IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP"
else
    codesign --force --options runtime --timestamp=none \
        --identifier "$BUNDLE_ID" \
        --sign "$IDENTITY" \
        "$APP"
fi

echo "==> Verificando assinatura"
codesign --verify --deep --strict "$APP" 2>/dev/null \
    || echo "warning: verificação reportou problemas (esperado para assinatura ad-hoc)."

TEAM=$(codesign -dv "$APP" 2>&1 | awk -F= '/TeamIdentifier/ {print $2}')

echo
echo "Built:  $APP  (v$VERSION build $BUILD_NUMBER)"
echo "Team:   ${TEAM:-<none>}"
echo
echo "Next:   make installer     # gera o .pkg"
echo "  ou:   make dmg           # gera o .dmg"
