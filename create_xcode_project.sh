#!/bin/bash

# Script para criar o projeto Xcode do MAC-LIMPO

echo "Criando projeto Xcode MAC-LIMPO..."

# Verifica se Xcode está instalado
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode não está instalado. Por favor, instale o Xcode da App Store."
    exit 1
fi

# Navega para o diretório do projeto
cd "$(dirname "$0")"

echo "✅ Xcode encontrado: $(xcodebuild -version | head -n 1)"
echo ""
echo "📋 Próximos passos:"
echo "1. Abra Package.swift no Xcode 27 (o projeto usa Swift Package Manager)"
echo "2. Selecione o produto executável MAC-LIMPO"
echo "3. Confirme macOS 27.0 como deployment target"
echo "4. Confirme a arquitetura arm64 para o build de distribuição"
echo "5. Build e execute"
echo ""
echo "📁 O Package.swift já inclui Models, Services, Views, Utilities e Intents."
