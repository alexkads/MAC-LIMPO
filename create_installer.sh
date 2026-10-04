#!/bin/bash
#
# Gera MAC-LIMPO.dmg — distribuição por arrastar-e-soltar.
#
# A montagem e a assinatura do .app ficam em Scripts/bundle-app.sh, que é o
# mesmo caminho usado pelo .pkg (Installer/build-installer.sh). Isso existe
# para que o app dentro do DMG e o app dentro do instalador sejam byte a byte
# o mesmo bundle — quando eram montados por dois scripts separados, divergiam
# em Info.plist e assinatura sem ninguém perceber.
#
# Para o instalador nativo (recomendado):  ./Installer/build-installer.sh

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MAC-LIMPO"
APP_BUNDLE="build/app/$APP_NAME.app"
VERSION="$(tr -d ' \n' < VERSION 2>/dev/null || echo '1.1.0')"
# Tudo que este script gera fica em build/ — já excluído no Package.swift, então
# o SPM não varre o symlink /Applications da staging nem avisa de excludes
# inexistentes quando o .dmg ainda não foi gerado.
OUT_DIR="build"
DMG_NAME="$OUT_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$OUT_DIR/dmg_staging"
TEMP_DMG="$OUT_DIR/pack.temp.dmg"

echo "🚀 Criando DMG do $APP_NAME v$VERSION..."

# 1. Monta e assina o app
./Scripts/bundle-app.sh

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ $APP_BUNDLE não existe após o build"
    exit 1
fi

# 2. Prepara a staging area
echo "💿 Criando DMG customizado..."
mkdir -p "$OUT_DIR"
rm -f "$DMG_NAME" "$TEMP_DMG"
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"

cp -R "$APP_BUNDLE" "$STAGING/"

BACKGROUND_FILE="Design/Installer/dmg-background.png"
if [ -f "$BACKGROUND_FILE" ]; then
    echo "🖼️  Adicionando imagem de fundo..."
    cp "$BACKGROUND_FILE" "$STAGING/.background/background.png"
else
    echo "⚠️ Fundo não encontrado em $BACKGROUND_FILE (o DMG usará o padrão)."
fi

ln -s /Applications "$STAGING/Applications"

# 3. DMG temporário gravável
echo "📀 Criando DMG temporário..."
hdiutil create -srcfolder "$STAGING" -volname "$APP_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 200m "$TEMP_DMG"

echo "🔗 Montando DMG..."
device=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | grep -E '^/dev/' | sed 1q | awk '{print $1}')
if [ -z "$device" ]; then
    echo "❌ Falha ao montar o DMG temporário"
    exit 1
fi
sleep 2

# 4. Estilo da janela (cosmético — nunca derruba o build)
echo "🎨 Estilizando a janela do DMG..."
osascript <<EOF || echo "⚠️ Estilização falhou (cosmético, seguindo)."
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 940, 500}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100

        try
            set background picture of theViewOptions to file "background.png" of folder ".background"
        end try

        set position of item "$APP_NAME" of container window to {160, 200}
        set position of item "Applications" of container window to {400, 200}

        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

sync
hdiutil detach "$device" || hdiutil detach "$device" -force

echo "📦 Comprimindo DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"

rm -f "$TEMP_DMG"
rm -rf "$STAGING"

echo "✅ DMG criado: $DMG_NAME (v$VERSION)"
