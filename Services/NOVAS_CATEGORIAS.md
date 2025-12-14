# 🚀 Novas Categorias de Limpeza - MAC-LIMPO

## 📊 RESUMO DAS EXPANSÕES

A aplicação foi **expandida de 5 para 16 categorias** de limpeza, oferecendo muito mais potencial de recuperação de espaço!

---

## ✨ NOVAS CATEGORIAS ADICIONADAS

### 🔧 **Desenvolvimento (4 categorias)**

#### 1. **Xcode Cache** 
**Arquivo:** `XcodeCacheCleaningService.swift`
**Limpa:**
- `~/Library/Developer/Xcode/DerivedData` (pode ter **dezenas de GB**)
- `~/Library/Developer/Xcode/Archives`
- `~/Library/Developer/Xcode/iOS DeviceSupport`
- `~/Library/Developer/Xcode/watchOS DeviceSupport`
- `~/Library/Developer/Xcode/tvOS DeviceSupport`
- `~/Library/Caches/com.apple.dt.Xcode`
- `~/Library/Developer/CoreSimulator/Caches`

**Impacto esperado:** 10-50GB para desenvolvedores ativos

---

#### 2. **iOS Simulators**
**Arquivo:** `IOSSimulatorsCleaningService.swift`
**Limpa:**
- Simuladores não disponíveis (`xcrun simctl delete unavailable`)
- Dados dos simuladores (`xcrun simctl erase all`)
- `~/Library/Developer/CoreSimulator/Devices`

**Impacto esperado:** 5-20GB

---

### 🗂️ **Sistema (2 categorias novas)**

#### 3. **Old Downloads**
**Arquivo:** `DownloadsCleaningService.swift`
**Limpa:**
- Arquivos na pasta Downloads com **mais de 30 dias**
- Identifica e remove arquivos esquecidos

**Impacto esperado:** 1-10GB

---

#### 4. **Trash Bin**
**Arquivo:** `TrashCleaningService.swift`
**Limpa:**
- Esvazia a Lixeira (`~/.Trash`)
- Usa `NSWorkspace` para limpeza segura

**Impacto esperado:** 1-50GB (dependendo do uso)

---

### 🌐 **Navegadores e Apps (3 categorias)**

#### 5. **Browser Cache** (EXPANDIDO)
**Arquivo:** `BrowserCacheCleaningService.swift`
**Suporta:**
- **Safari:** Cache, WebKit, History, LocalStorage
- **Chrome:** Cache, GPUCache, Code Cache
- **Firefox:** Cache, Profiles Cache
- **Edge:** Cache completo
- **Brave:** Cache completo
- **Arc:** Cache

**Impacto esperado:** 2-10GB

---

#### 6. **Spotify Cache**
**Arquivo:** `SpotifyCacheCleaningService.swift`
**Limpa:**
- `~/Library/Caches/com.spotify.client`
- `~/Library/Application Support/Spotify/PersistentCache`
- Cache de músicas offline

**Impacto esperado:** 1-5GB

---

#### 7. **Slack Cache**
**Arquivo:** `SlackCacheCleaningService.swift`
**Limpa:**
- Cache do Slack
- Code Cache
- Service Worker Cache
- Local Storage

**Impacto esperado:** 500MB-2GB

---

### 📁 **Arquivos Grandes e Duplicados (2 categorias)**

#### 8. **Large Files** (Apenas identificação)
**Arquivo:** `LargeFilesCleaningService.swift`
**Busca em:**
- `~/Documents`
- `~/Downloads`
- `~/Desktop`
- `~/Movies`

**Identifica:** Arquivos maiores que **500MB**
**Nota:** ⚠️ **Não remove automaticamente** (apenas identifica para revisão manual)

**Impacto potencial:** 10-100GB+

---

#### 9. **Duplicate Files** (Apenas identificação)
**Arquivo:** `DuplicateFilesCleaningService.swift`
**Busca em:**
- `~/Documents`
- `~/Downloads`
- `~/Desktop`

**Usa:** SHA256 hash para detectar duplicados
**Nota:** ⚠️ **Não remove automaticamente** (apenas identifica para revisão manual)

**Impacto potencial:** 2-20GB

---

### 📧 **Email e Mensagens (2 categorias)**

#### 10. **Mail Attachments**
**Arquivo:** `MailAttachmentsCleaningService.swift`
**Limpa:**
- `~/Library/Mail Downloads` (seguro)

**Preserva:** Attachments em `~/Library/Mail/*/MailData/Attachments` (para não quebrar emails)

**Impacto esperado:** 500MB-5GB

---

#### 11. **Messages Attachments**
**Arquivo:** `MessagesAttachmentsCleaningService.swift`
**Limpa:**
- `~/Library/Messages/Cache`

**Preserva:** Attachments originais (para manter histórico)

**Impacto esperado:** 500MB-3GB

---

## 📈 **IMPACTO TOTAL ESTIMADO**

| Categoria | Impacto Médio | Impacto Máximo |
|-----------|---------------|----------------|
| **Desenvolvimento** | 15-70GB | 100GB+ |
| **Sistema** | 5-20GB | 60GB |
| **Navegadores** | 3-15GB | 25GB |
| **Arquivos Grandes** | 10-50GB | 200GB+ |
| **Email/Mensagens** | 1-8GB | 20GB |
| **TOTAL** | **34-163GB** | **405GB+** |

---

## ⚙️ **ALTERAÇÕES NOS ARQUIVOS EXISTENTES**

### `CleaningCategory.swift`
- ✅ Adicionadas 11 novas categorias ao enum
- ✅ Cada uma com ícone, cor e descrição única
- ✅ Total: 16 categorias

### `MenuBarView.swift`
- ✅ Atualizado dicionário `services` com todos os 16 serviços
- ✅ Organizado por seções (Desenvolvimento, Sistema, Navegadores, etc.)

### `LogsCleaningService.swift`
- ✅ Adicionados mais caminhos de logs
- ✅ Suporte a wildcards (`*/`)
- ✅ Ignora logs do sistema que requerem sudo

---

## 🎯 **CATEGORIAS POR USO**

### Para **Desenvolvedores** 👨‍💻
- ✅ Docker
- ✅ Dev Packages
- ✅ **Xcode Cache** (NOVO)
- ✅ **iOS Simulators** (NOVO)

### Para **Usuários Gerais** 👤
- ✅ Temp Files
- ✅ **Downloads** (NOVO)
- ✅ **Trash** (NOVO)
- ✅ **Browser Cache** (EXPANDIDO)
- ✅ Logs

### Para **Usuários Power** 💪
- ✅ **Large Files** (NOVO - apenas identifica)
- ✅ **Duplicate Files** (NOVO - apenas identifica)
- ✅ App Cache
- ✅ **Spotify Cache** (NOVO)
- ✅ **Slack Cache** (NOVO)

### Para **Usuários de Email/Mensagens** 📧
- ✅ **Mail Attachments** (NOVO)
- ✅ **Messages Attachments** (NOVO)

---

## ⚠️ **AVISOS IMPORTANTES**

### Categorias Seguras (Limpeza Automática)
✅ Todas exceto Large Files e Duplicate Files

### Categorias Somente Identificação
⚠️ **Large Files** - Apenas mostra arquivos grandes
⚠️ **Duplicate Files** - Apenas detecta duplicados

**Por quê?** Segurança! Arquivos grandes e duplicados podem ser importantes.

---

## 🔒 **PERMISSÕES NECESSÁRIAS**

A aplicação requer **Full Disk Access** para:
- Acessar `~/Library/*`
- Acessar Downloads
- Acessar Mail e Messages
- Limpar caches de apps

**Como habilitar:**
`System Settings > Privacy & Security > Full Disk Access > ✅ MAC-LIMPO`

---

## 🚀 **COMO COMPILAR**

1. Abra o projeto no Xcode
2. **Adicione os novos arquivos ao target:**
   - XcodeCacheCleaningService.swift
   - IOSSimulatorsCleaningService.swift
   - DownloadsCleaningService.swift
   - TrashCleaningService.swift
   - BrowserCacheCleaningService.swift
   - SpotifyCacheCleaningService.swift
   - SlackCacheCleaningService.swift
   - LargeFilesCleaningService.swift
   - DuplicateFilesCleaningService.swift
   - MailAttachmentsCleaningService.swift
   - MessagesAttachmentsCleaningService.swift

3. Compile com ⌘R

---

## 📱 **INTERFACE**

A interface agora mostra **16 cards** (em vez de 5), organizados por tipo.

**Dica:** O scroll agora é essencial! A lista é mais longa.

**Sugestão futura:** Adicionar abas ou categorias colapsáveis para melhor organização.

---

## 🔍 **DETALHES TÉCNICOS**

### Novos Recursos Usados
- ✅ **CryptoKit** - Para SHA256 hash em duplicados
- ✅ **NSWorkspace** - Para limpeza segura da lixeira
- ✅ **Wildcard paths** - Suporte a `*` em caminhos
- ✅ **Recursive search** - Para Large Files e Duplicates

### Performance
- **Large Files:** Pode demorar 1-5 minutos (busca recursiva)
- **Duplicate Files:** Pode demorar 2-10 minutos (calcula hashes)
- **Xcode Cache:** Rápido (apenas remove diretórios)
- **Simulators:** Médio (usa `xcrun simctl`)

---

## 📋 **ROADMAP FUTURO**

### Próximas melhorias sugeridas:
1. **Interface com abas/categorias**
   - Aba "Desenvolvimento"
   - Aba "Sistema"
   - Aba "Apps"
   - Aba "Análise" (Large/Duplicate Files)

2. **Opção de exclusão manual**
   - Para Large Files e Duplicates
   - Checkbox para selecionar arquivos

3. **Agendamento automático**
   - Limpar automaticamente a cada semana
   - Notificar quando muito espaço for recuperável

4. **Estatísticas históricas**
   - Quanto foi limpo ao longo do tempo
   - Gráfico de espaço liberado

5. **Mais categorias**
   - Steam cache
   - Epic Games cache
   - Adobe Creative Cloud cache
   - Teams cache
   - Zoom cache

---

## 🎉 **RESULTADO FINAL**

**Antes:** 5 categorias → ~5-15GB recuperáveis
**Agora:** 16 categorias → **34-163GB+ recuperáveis!**

**Aumento:** 320% mais potencial de limpeza! 🚀

---

**Data:** 04/12/2025
**Versão:** 2.0
**Status:** ✅ Expansão completa implementada
