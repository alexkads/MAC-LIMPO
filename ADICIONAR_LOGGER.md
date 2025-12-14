# 🚀 Como Adicionar Logger.swift ao Projeto

## ⚡ PASSOS RÁPIDOS (2 minutos)

### 1. Abra o Xcode
- Já deve estar aberto com seu projeto

### 2. Adicione o Arquivo
1. No **Project Navigator** (barra lateral esquerda, ⌘1)
2. Clique com **botão direito** no grupo do projeto
3. Selecione **"Add Files to 'MAC-LIMPO'..."**
4. Navegue até a pasta do projeto
5. Selecione **`Logger.swift`**
6. ✅ Marque **"Copy items if needed"**
7. ✅ Marque **"Add to targets: MAC-LIMPO"**
8. Clique em **"Add"**

### 3. Compile
```
⌘B - Build
```

### 4. Execute
```
⌘R - Run
```

---

## ✅ PRONTO!

Agora o código já está usando `Logger` em vez de `print()` e você verá logs muito mais organizados!

---

## 📊 DIFERENÇA

### Antes (com print)
```
Scanning path: /tmp
Found: tmp - 500 MB
```

### Depois (com Logger)
```
🔍 [TempFiles] Starting scan
  Scanning path: /tmp
  Found: tmp - 500 MB
✅ [TempFiles] Scan complete: 500 MB in 1 locations
```

---

## 🔍 COMO VER OS LOGS

### Console do Xcode
- Painel inferior durante execução
- Veja todos os logs automaticamente

### Console.app (Mais Poder)
1. Abra **Console.app**
2. Busque: `process:MAC-LIMPO`
3. Filtre por:
   - `level:error` - Só erros
   - `🔍` - Só scans
   - `🧹` - Só limpezas

### Terminal
```bash
log stream --predicate 'process == "MAC-LIMPO"' --level debug
```

---

## 🎯 BENEFÍCIOS DO LOGGER

1. ✅ **Performance** - Logs de debug desabilitados em Release
2. ✅ **Filtragem** - Pode filtrar por nível, categoria, etc.
3. ✅ **Metadados** - Arquivo, linha, timestamp automáticos
4. ✅ **Integração** - Funciona com Console.app, Instruments
5. ✅ **Níveis** - debug, info, warning, error, success
6. ✅ **Emojis** - 🔍 🧹 ✅ ❌ ⚠️ para fácil identificação

---

**Adicione o arquivo e compile! Vai funcionar perfeitamente.** 🎉
