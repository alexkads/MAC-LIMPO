#!/bin/bash

# Script para verificar arquivos do MAC-LIMPO
# Uso: chmod +x check_files.sh && ./check_files.sh

echo "🔍 Verificando arquivos do projeto MAC-LIMPO..."
echo ""

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Contadores
total=0
found=0
missing=0

# Função para verificar arquivo
check_file() {
    local file=$1
    local desc=$2
    total=$((total + 1))
    
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅${NC} $desc"
        found=$((found + 1))
    else
        echo -e "${RED}❌${NC} $desc ${RED}(FALTANDO)${NC}"
        missing=$((missing + 1))
    fi
}

echo "=== ARQUIVOS PRINCIPAIS ==="
check_file "MACLIMPOApp.swift" "MACLIMPOApp.swift"
check_file "MenuBarView.swift" "MenuBarView.swift"
echo ""

echo "=== MODELS ==="
check_file "CleaningCategory.swift" "CleaningCategory.swift"
check_file "CleaningResult.swift" "CleaningResult.swift"
check_file "CleaningService.swift" "CleaningService.swift"
echo ""

echo "=== SERVIÇOS ORIGINAIS ==="
check_file "DockerCleaningService.swift" "DockerCleaningService.swift"
check_file "DevPackagesCleaningService.swift" "DevPackagesCleaningService.swift"
check_file "TempFilesCleaningService.swift" "TempFilesCleaningService.swift"
check_file "LogsCleaningService.swift" "LogsCleaningService.swift"
check_file "AppCacheCleaningService.swift" "AppCacheCleaningService.swift"
echo ""

echo "=== NOVOS SERVIÇOS (11) ==="
check_file "XcodeCacheCleaningService.swift" "XcodeCacheCleaningService.swift"
check_file "IOSSimulatorsCleaningService.swift" "IOSSimulatorsCleaningService.swift"
check_file "DownloadsCleaningService.swift" "DownloadsCleaningService.swift"
check_file "TrashCleaningService.swift" "TrashCleaningService.swift"
check_file "BrowserCacheCleaningService.swift" "BrowserCacheCleaningService.swift"
check_file "SpotifyCacheCleaningService.swift" "SpotifyCacheCleaningService.swift"
check_file "SlackCacheCleaningService.swift" "SlackCacheCleaningService.swift"
check_file "LargeFilesCleaningService.swift" "LargeFilesCleaningService.swift"
check_file "DuplicateFilesCleaningService.swift" "DuplicateFilesCleaningService.swift"
check_file "MailAttachmentsCleaningService.swift" "MailAttachmentsCleaningService.swift"
check_file "MessagesAttachmentsCleaningService.swift" "MessagesAttachmentsCleaningService.swift"
echo ""

echo "=== UTILITIES ==="
check_file "FileSystemHelper.swift" "FileSystemHelper.swift"
check_file "ShellExecutor.swift" "ShellExecutor.swift"
check_file "LaunchAtLoginService.swift" "LaunchAtLoginService.swift"
echo ""

echo "=== VIEWS/COMPONENTS ==="
check_file "CleaningCategoryCard.swift" "CleaningCategoryCard.swift"
check_file "StorageStatsView.swift" "StorageStatsView.swift"
check_file "CleaningProgressView.swift" "CleaningProgressView.swift"
check_file "ResultsView.swift" "ResultsView.swift"
echo ""

echo "=== DOCUMENTAÇÃO ==="
check_file "README.md" "README.md"
check_file "XCODE_SETUP.md" "XCODE_SETUP.md"
check_file "PROBLEMAS_E_CORRECOES.md" "PROBLEMAS_E_CORRECOES.md"
check_file "NOVAS_CATEGORIAS.md" "NOVAS_CATEGORIAS.md"
check_file "GUIA_INSTALACAO.md" "GUIA_INSTALACAO.md"
check_file "IDEIAS_FUTURAS.md" "IDEIAS_FUTURAS.md"
check_file "CORRECAO_APLICADA.md" "CORRECAO_APLICADA.md"
echo ""

# Resumo
echo "========================================"
echo -e "${GREEN}✅ Encontrados: $found/$total${NC}"
if [ $missing -gt 0 ]; then
    echo -e "${RED}❌ Faltando: $missing/$total${NC}"
fi
echo "========================================"
echo ""

# Status
if [ $missing -eq 0 ]; then
    echo -e "${GREEN}🎉 Todos os arquivos estão presentes!${NC}"
    echo ""
    echo "Próximos passos:"
    echo "1. Abra o projeto no Xcode"
    echo "2. Adicione os 11 novos serviços ao target"
    echo "3. Descomente as linhas no MenuBarView.swift"
    echo "4. Compile (⌘B) e execute (⌘R)"
    echo ""
    echo "📖 Leia CORRECAO_APLICADA.md para instruções detalhadas"
else
    echo -e "${YELLOW}⚠️  Alguns arquivos estão faltando${NC}"
    echo ""
    echo "A aplicação vai compilar com os 5 serviços originais."
    echo "Para ter acesso às 16 categorias, você precisa de todos os arquivos."
    echo ""
    echo "📖 Leia CORRECAO_APLICADA.md para mais informações"
fi
echo ""

# Verifica se há arquivo .xcodeproj
echo "=== PROJETO XCODE ==="
if ls *.xcodeproj 1> /dev/null 2>&1; then
    proj=$(ls *.xcodeproj | head -n 1)
    echo -e "${GREEN}✅${NC} Encontrado: $proj"
    echo ""
    echo "Para abrir o projeto:"
    echo "  open $proj"
else
    echo -e "${RED}❌${NC} Nenhum arquivo .xcodeproj encontrado"
    echo ""
    echo "Você precisa criar o projeto no Xcode primeiro."
    echo "Leia XCODE_SETUP.md para instruções."
fi
echo ""
