#!/bin/bash

# Script para capturar logs de erro do MAC-LIMPO
# Uso: ./capture_errors.sh

echo "🔍 Capturando logs de erro do MAC-LIMPO..."
echo ""
echo "Este script vai:"
echo "1. Limpar logs antigos"
echo "2. Executar a aplicação"
echo "3. Capturar erros em tempo real"
echo ""
echo "Pressione Ctrl+C para parar"
echo ""
echo "==================== LOGS ===================="
echo ""

# Limpa logs antigos
log stream --predicate 'process == "MAC-LIMPO"' --level debug --style compact

# OU use este comando alternativo:
# log show --predicate 'process CONTAINS "MAC-LIMPO"' --last 5m --info
