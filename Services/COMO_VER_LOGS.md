# 🔍 Como Ver Logs de Erro do MAC-LIMPO

## 📋 OPÇÃO 1: Console do Xcode (Mais Fácil)

### Durante Desenvolvimento
1. Execute a aplicação no Xcode (⌘R)
2. Abra o **Debug Navigator** (⌘7)
3. Veja os logs no painel inferior
4. Procure por mensagens com:
   - ❌ (erros)
   - ⚠️ (avisos)
   - 🔍 (scans)
   - 🧹 (limpezas)

### Filtrar Logs
No campo de busca do console, digite:
```
TempFiles
```
ou
```
❌
```

---

## 📋 OPÇÃO 2: Console.app (Aplicação Rodando)

### Passos
1. Abra **Console.app** (Spotlight: "Console")
2. Selecione **seu Mac** na barra lateral esquerda
3. No campo de busca, digite:
   ```
   process:MAC-LIMPO
   ```
   ou
   ```
   subsystem:com.maclimpo
   ```

4. Execute a aplicação MAC-LIMPO
5. Tente a operação que causa erro
6. Veja os logs em tempo real

### Filtros Úteis
```
# Ver apenas erros
process:MAC-LIMPO AND level:error

# Ver scans
process:MAC-LIMPO AND category:general AND 🔍

# Ver limpezas
process:MAC-LIMPO AND category:general AND 🧹

# Ver últimos 5 minutos
process:MAC-LIMPO last:5m
```

---

## 📋 OPÇÃO 3: Terminal (Linha de Comando)

### Ver Logs em Tempo Real
```bash
log stream --predicate 'process == "MAC-LIMPO"' --level debug
```

### Ver Logs Recentes
```bash
log show --predicate 'process CONTAINS "MAC-LIMPO"' --last 5m --info
```

### Salvar Logs em Arquivo
```bash
log show --predicate 'process CONTAINS "MAC-LIMPO"' --last 1h --info > ~/Desktop/maclimpo_logs.txt
```

### Script Pronto
```bash
chmod +x capture_errors.sh
./capture_errors.sh
```

---

## 🔍 O QUE PROCURAR NOS LOGS

### Mensagens de Sucesso ✅
```
✅ TempFiles cleanup complete: 1.2 GB, 45 files, 0 errors
✅ [TempFiles] Scan complete: 1.2 GB in 4 locations
```

### Mensagens de Erro ❌
```
❌ TempFiles cleanup failed with 5 errors
❌ Failed to remove item: Operation not permitted
❌ Cannot find type 'XcodeCacheCleaningService'
```

### Mensagens de Debug 🐛
```
🔍 [TempFiles] Starting scan
🔍 Scanning path: /tmp
🔍 Found: tmp - 500 MB
🧹 [TempFiles] Starting cleanup
🧹 Cleaning: ~/Library/Caches/CloudKit
```

### Avisos ⚠️
```
⚠️ Skipped item: Operation not permitted
⚠️ Path does not exist: ~/Library/Caches/com.apple.bird
```

---

## 🐛 ERROS COMUNS E SIGNIFICADOS

### 1. "Operation not permitted"
**Causa:** Falta de permissões (Full Disk Access)
**Solução:** System Settings > Privacy & Security > Full Disk Access > ✅ MAC-LIMPO

### 2. "Cannot find type..."
**Causa:** Arquivos não foram adicionados ao target do Xcode
**Solução:** Veja `CORRECAO_APLICADA.md`

### 3. "No such file or directory"
**Causa:** Caminho não existe (normal, não é erro crítico)
**Solução:** Ignorar (é esperado se o cache não existe)

### 4. "Resource busy"
**Causa:** Arquivo está em uso por outro app
**Solução:** Feche o app que está usando o arquivo

### 5. "Command timed out"
**Causa:** Operação demorou mais que o timeout
**Solução:** Aumente o timeout ou opere em menos arquivos

---

## 📊 EXEMPLO DE LOG COMPLETO

```
🔍 [TempFiles] Starting scan
🐛 Scanning path: ~/Library/Caches/com.apple.bird
🐛 Path does not exist: ~/Library/Caches/com.apple.bird
🐛 Scanning path: ~/Library/Caches/CloudKit
🐛 Found: CloudKit - 50 MB
🐛 Scanning path: /tmp
🐛 Found: tmp - 500 MB
✅ [TempFiles] Scan complete: 550 MB in 2 locations

🧹 [TempFiles] Starting cleanup
🐛 Cleaning /tmp directory
🐛 Found 150 items in /tmp
🐛 Removed from /tmp: build_output (10 MB)
🐛 Removed from /tmp: old_cache (20 MB)
ℹ️  /tmp cleanup: removed 45, skipped 105
🐛 Cleaning: ~/Library/Caches/CloudKit
🐛 Cleaning directory: ~/Library/Caches/CloudKit (3 items)
🐛 Removed: file1.cache (5 MB)
⚠️  Skipped file2.cache: Operation not permitted
ℹ️  Directory ~/Library/Caches/CloudKit: removed 2, skipped 1, errors 1
✅ TempFiles cleanup complete: 35 MB, 47 files, 1 errors
```

---

## 🎯 COMO REPORTAR ERROS

Se encontrar um erro e quiser ajuda, copie:

1. **Mensagens de erro** (linhas com ❌)
2. **Contexto** (linhas antes e depois)
3. **Qual operação** você estava fazendo
4. **Qual categoria** estava limpando

### Exemplo de Reporte
```
OPERAÇÃO: Limpeza de Temp Files
ERRO: ❌ TempFiles cleanup failed with 5 errors
LOGS:
🧹 [TempFiles] Starting cleanup
🐛 Cleaning: ~/Library/Caches/CloudKit
❌ Failed to remove item: Operation not permitted
❌ Failed to remove item: Resource busy
⚠️  Skipped file.cache: Operation not permitted
```

---

## 🔧 HABILITAR LOGS DETALHADOS

### No Código
Se quiser ainda mais detalhes, edite `Logger.swift` e mude o nível de log:

```swift
// Mais detalhes (desenvolvimento)
os_log(.debug, ...)  // Mostra tudo

// Normal (produção)
os_log(.info, ...)   // Mostra info e erros

// Apenas erros
os_log(.error, ...)  // Só mostra erros
```

### No Console.app
Mude o nível de log:
- **All Messages** - Tudo
- **Info and above** - Info, avisos, erros
- **Errors only** - Apenas erros

---

## 📖 PRÓXIMOS PASSOS

1. **Capture os logs** usando um dos métodos acima
2. **Identifique o erro** específico
3. **Leia o significado** na seção "Erros Comuns"
4. **Aplique a solução** ou me mostre os logs

---

**Os logs agora são muito mais detalhados! Tente executar novamente e me mostre o que aparece.** 🔍
