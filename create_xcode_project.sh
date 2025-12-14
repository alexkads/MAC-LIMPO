#!/bin/bash

# Script para criar o projeto Xcode do MAC-LIMPO

echo "Criando projeto Xcode MAC-LIMPO..."

# Verifica se Xcode está instalado
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode não está instalado. Por favor, instale o Xcode da App Store."
    exit 1
fi

# Cria novo projeto SwiftUI para macOS
mkdir -p MAC-LIMPO.xcodeproj

# Navega para o diretório do projeto
cd "$(dirname "$0")"

echo "✅ Estrutura do projeto criada!"
echo ""
echo "📋 Próximos passos:"
echo "1. Abra o Xcode"
echo "2. Crie um novo projeto (File > New > Project)"
echo "3. Escolha 'macOS' > 'App'"
echo "4. Configure:"
echo "   - Product Name: MAC-LIMPO"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo "   - Organization Identifier: com.maclimpo"
echo "5. Salve na pasta atual"
echo "6. Adicione todos os arquivos .swift ao projeto"
echo "7. Configure Info.plist (já criado)"
echo "8. Build e execute!"
echo ""
echo "📁 Arquivos criados:"
find . -name "*.swift" -o -name "*.plist" -o -name "README.md" | head -20

