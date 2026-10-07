#!/bin/sh
# Atualiza Localization/Localizable.xcstrings com os textos que o código usa.
#
# O compilador do Swift extrai todo texto localizável (literais de Text/Button/
# Label, String(localized:), LocalizedStringResource) em arquivos .stringsdata —
# o mesmo que o Xcode faz — e o xcstringstool os funde no catálogo: chaves
# novas entram sem tradução, as que sumiram do código ficam marcadas "stale".
# Depois de rodar, traduza as novas para pt-BR (o teste LocalizationTests acusa
# as que faltarem).
#
# Uso: ./Scripts/sync-strings.sh   (ou: make strings)

set -eu
cd "$(dirname "$0")/.."

CATALOG="Localization/Localizable.xcstrings"
# Build separado em .build/strings: as flags de extração invalidariam o cache do
# build normal a cada troca.
SCRATCH=".build/strings"
DATA="$PWD/$SCRATCH/stringsdata"  # absoluto: o swiftc roda em outra pasta

# Não apagar $DATA: num build incremental o swiftc só reescreve o .stringsdata
# dos arquivos que recompilou; os outros precisam continuar ali.
mkdir -p "$DATA"
swift build --scratch-path "$SCRATCH" \
    -Xswiftc -emit-localized-strings \
    -Xswiftc -emit-localized-strings-path -Xswiftc "$DATA" > "$SCRATCH/build.log" 2>&1 || {
    tail -20 "$SCRATCH/build.log" >&2
    exit 1
}

if [ ! -f "$CATALOG" ]; then
    printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}\n' > "$CATALOG"
fi

xcrun xcstringstool sync "$CATALOG" --stringsdata "$DATA"/*.stringsdata
echo "==> $CATALOG: $(xcrun xcstringstool print "$CATALOG" 2>/dev/null | grep -c . || true) chaves"
