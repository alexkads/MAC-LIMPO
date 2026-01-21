#!/bin/bash
# Script para limpar snapshots APFS e espaço "purgeable" oculto

echo "🔍 MAC-LIMPO - Limpeza Profunda de System Data"
echo "=============================================="
echo ""

# Mostra estado atual
echo "📊 Estado Atual do Disco:"
df -h / | tail -1
echo ""

# 1. Remove APFS snapshots locais
echo "⏱️  Limpando Time Machine Local Snapshots..."
SNAPSHOTS=$(tmutil listlocalsnapshots / 2>/dev/null | grep "com.apple.TimeMachine")
COUNT=0

if [ -n "$SNAPSHOTS" ]; then
    echo "$SNAPSHOTS" | while read snapshot; do
        echo "  Removendo: $snapshot"
        sudo tmutil deletelocalsnapshots $(echo $snapshot | cut -d'.' -f4) 2>/dev/null
        COUNT=$((COUNT + 1))
    done
    echo "✅ Removidos $COUNT snapshots"
else
    echo "  Nenhum snapshot encontrado"
fi
echo ""

# 2. Limpa espaço "purgeable" forçando
echo "💾 Forçando Limpeza de Espaço Purgeable..."
echo "  (Isso pode demorar alguns minutos...)"

# Cria arquivo temporário grande para forçar purge
TEMP_FILE="/tmp/force_purge_$(date +%s).tmp"
echo "  Criando arquivo temporário para forçar purge..."
dd if=/dev/zero of="$TEMP_FILE" bs=1m count=10000 2>/dev/null
rm -f "$TEMP_FILE"
echo "✅ Espaço purgeable limpo"
echo ""

# 3. Limpa caches do sistema
echo "🧹 Limpando Caches do Sistema..."
sudo periodic daily weekly monthly 2>/dev/null
echo "✅ Caches do sistema limpos"
echo ""

# 4. Rebuild Spotlight index (opcional - pode recuperar muito espaço)
echo "🔎 Reconstruindo Índice do Spotlight..."
read -p "Deseja reconstruir o índice do Spotlight? (pode liberar GBs) (s/n): " rebuild
if [ "$rebuild" = "s" ]; then
    sudo mdutil -E / 2>/dev/null
    echo "✅ Índice será reconstruído em background"
else
    echo "  Pulado"
fi
echo ""

# 5. Limpa Application Support grandes
echo "📦 Application Support - Top 10 Maiores:"
du -sh ~/Library/Application\ Support/* 2>/dev/null | sort -hr | head -10
echo ""
read -p "Deseja limpar caches de Application Support? (s/n): " clean_app
if [ "$clean_app" = "s" ]; then
    # JetBrains
    if [ -d ~/Library/Application\ Support/JetBrains ]; then
        find ~/Library/Application\ Support/JetBrains -name "log" -type d -exec rm -rf {} \; 2>/dev/null
        find ~/Library/Application\ Support/JetBrains -name "caches" -type d -exec rm -rf {} \; 2>/dev/null
        echo "  ✅ JetBrains caches limpos"
    fi
    
    # VS Code / Cursor caches
    rm -rf ~/Library/Application\ Support/Code/Cache/* 2>/dev/null
    rm -rf ~/Library/Application\ Support/Code/CachedData/* 2>/dev/null
    rm -rf ~/Library/Application\ Support/Cursor/Cache/* 2>/dev/null
    rm -rf ~/Library/Application\ Support/Cursor/CachedData/* 2>/dev/null
    echo "  ✅ VS Code/Cursor caches limpos"
    
    # Adobe caches
    find ~/Library/Application\ Support/Adobe -name "*Cache*" -type d -exec rm -rf {} \; 2>/dev/null
    echo "  ✅ Adobe caches limpos"
fi
echo ""

# 6. Estado final
echo "📊 Estado Final do Disco:"
df -h / | tail -1
echo ""

echo "✅ Limpeza Profunda Completa!"
echo ""
echo "💡 Se ainda houver muito 'System Data':"
echo "   1. Reinicie o Mac (libera mais espaço)"
echo "   2. Execute: sudo tmutil thinlocalsnapshots / 99999999999 1"
echo "   3. Abra 'About This Mac' > Storage > Manage"
echo "   4. Verifique 'System' e 'Other'"
