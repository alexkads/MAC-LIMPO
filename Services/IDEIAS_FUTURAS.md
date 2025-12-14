# 💡 Ideias para Futuras Expansões - MAC-LIMPO

## 🎮 **Gaming & Entertainment**

### Steam Cache
```
~/Library/Application Support/Steam/appcache
~/Library/Application Support/Steam/logs
~/Library/Application Support/Steam/steamapps/shadercache
```
**Impacto:** 5-20GB

### Epic Games
```
~/Library/Application Support/Epic/EpicGamesLauncher/Saved/webcache
~/Library/Caches/com.epicgames.EpicGamesLauncher
```
**Impacto:** 1-5GB

### Discord
```
~/Library/Application Support/discord/Cache
~/Library/Application Support/discord/Code Cache
~/Library/Application Support/discord/GPUCache
```
**Impacto:** 500MB-2GB

### Zoom
```
~/Library/Application Support/zoom.us
~/Library/Logs/zoom.us
~/Library/Caches/us.zoom.xos
```
**Impacto:** 500MB-3GB

---

## 🎨 **Creative Apps**

### Adobe Creative Cloud Cache
```
~/Library/Caches/Adobe/*
~/Library/Application Support/Adobe/Common/Media Cache Files
~/Library/Application Support/Adobe/Adobe Premiere Pro/*/Peak Files
~/Library/Application Support/Adobe/Adobe After Effects/*/Adobe After Effects Disk Cache
```
**Impacto:** 10-100GB+

### Final Cut Pro Cache
```
~/Movies/Final Cut Pro/Cache
~/Library/Caches/com.apple.FinalCut
```
**Impacto:** 5-50GB

### Logic Pro Cache
```
~/Music/Audio Music Apps/Cache
~/Library/Caches/com.apple.logic10
```
**Impacto:** 1-10GB

### Figma Desktop Cache
```
~/Library/Application Support/Figma/Cache
~/Library/Application Support/Figma/GPUCache
```
**Impacto:** 500MB-2GB

---

## 💼 **Productivity Apps**

### Microsoft Teams
```
~/Library/Application Support/Microsoft/Teams/Cache
~/Library/Application Support/Microsoft/Teams/Service Worker/CacheStorage
~/Library/Caches/com.microsoft.teams2
```
**Impacto:** 1-5GB

### OneDrive Cache
```
~/Library/Application Support/OneDrive/logs
~/Library/Logs/OneDrive
```
**Impacto:** 500MB-2GB

### Dropbox Cache
```
~/Dropbox/.dropbox.cache
~/.dropbox/cache
```
**Impacto:** 1-10GB

### Notion Cache
```
~/Library/Application Support/Notion/Cache
~/Library/Application Support/Notion/GPUCache
```
**Impacto:** 500MB-3GB

---

## 🖥️ **System & Development**

### Time Machine Local Snapshots
```bash
tmutil listlocalsnapshots /
tmutil deletelocalsnapshots <snapshot_date>
```
**Impacto:** 10-100GB+

### iOS Device Backups
```
~/Library/Application Support/MobileSync/Backup/
```
**Impacto:** 5-50GB por device

### Python Virtual Environments
```
~/.virtualenvs
~/venv
~/.pyenv/versions/*/lib/python*/site-packages
```
**Impacto:** 1-10GB

### Ruby Gems Cache
```
~/.gem
/Library/Ruby/Gems/*/cache
```
**Impacto:** 500MB-2GB

### Go Module Cache
```
~/go/pkg/mod/cache
```
**Impacto:** 1-5GB

### Rust Target Directories
```
find ~ -name "target" -type d -path "*/target"
```
**Impacto:** 5-50GB

---

## 📚 **Documentation & Books**

### Dash Docsets
```
~/Library/Application Support/Dash/DocSets
```
**Impacto:** 1-10GB

### Calibre Library
```
~/Calibre Library/.caltrash
```
**Impacto:** 500MB-5GB

---

## 🌐 **Web Development**

### Node Modules (Globais)
```
~/.npm/_cacache
~/.node-gyp
/usr/local/lib/node_modules
```
**Impacto:** 1-10GB

### Yarn Cache
```
~/Library/Caches/Yarn
~/.yarn/cache
```
**Impacto:** 500MB-5GB

### Webpack Cache
```
find ~ -name ".cache" -path "*/node_modules/.cache"
```
**Impacto:** 1-10GB

---

## 🗄️ **Databases**

### PostgreSQL Logs
```
/usr/local/var/postgres/pg_log
~/Library/Application Support/Postgres/var-*/pg_log
```
**Impacto:** 500MB-5GB

### MongoDB Logs
```
/usr/local/var/log/mongodb
```
**Impacto:** 100MB-2GB

### Redis Dump Files
```
/usr/local/var/db/redis/dump.rdb
```
**Impacto:** 100MB-10GB

---

## 🎓 **Education & Learning**

### Anki Media Cache
```
~/Library/Application Support/Anki2/User 1/collection.media
```
**Impacto:** 500MB-10GB

---

## 🔍 **Smart Cleaning Features**

### 1. **Old Application Support Files**
Detectar apps que foram desinstalados mas deixaram dados:
```
~/Library/Application Support/*
~/Library/Preferences/*
~/Library/Caches/*
```
Compara com `/Applications` para encontrar "órfãos"

### 2. **Large Email Attachments**
```sql
SELECT message_id, file_size FROM attachment 
WHERE file_size > 10485760 
ORDER BY file_size DESC;
```
(Query no banco do Mail.app)

### 3. **Old iOS Backups**
Identifica backups mais antigos que X dias

### 4. **Unused Fonts**
```
~/Library/Fonts/*
/Library/Fonts/*
```
Compara com lista de fontes em uso

### 5. **Old Screenshots**
```
~/Desktop/Screen Shot*.png
~/Desktop/Screenshot*.png
```
Identifica screenshots com mais de X dias

---

## 🤖 **Automação Inteligente**

### Smart Scan
- Detecta automaticamente quais apps estão instalados
- Só mostra categorias relevantes
- Exemplo: Só mostra "Docker" se Docker estiver instalado

### Aggressive Mode
- Remove arquivos com 7 dias (em vez de 30)
- Limpa também logs recentes
- Remove backups locais do Time Machine

### Safe Mode (Padrão)
- Apenas remove caches regeneráveis
- Preserva logs recentes
- Pergunta confirmação para cada categoria

---

## 📊 **Analytics & Insights**

### Space Usage Breakdown
Gráfico mostrando:
- Quanto espaço cada categoria ocupa
- Tendência de crescimento
- Recomendações personalizadas

### Cleaning History
```swift
struct CleaningHistory {
    let date: Date
    let category: CleaningCategory
    let bytesRemoved: Int64
}
```

### Predictive Cleaning
"Você tende a acumular 2GB de cache por semana. Limpe agora?"

---

## 🎨 **UI Improvements**

### 1. **Category Groups**
```swift
enum CategoryGroup {
    case development
    case system
    case apps
    case browsers
    case communication
    case analysis
}
```

### 2. **Search/Filter**
```
[Search bar] "docker" → mostra só Docker e Dev Packages
```

### 3. **Favorite Categories**
⭐ Marcar categorias mais usadas para acesso rápido

### 4. **Schedule Cleaning**
```
🕐 Clean every Monday at 9 AM
📅 Clean when disk is 90% full
```

---

## 🔐 **Security & Privacy**

### 1. **Clear Browser History**
- Safari history
- Chrome history
- Firefox history

### 2. **Clear Cookies**
- All browsers
- Specific sites only

### 3. **Clear Recent Files**
- Finder recent files
- Preview recent
- Quick Look cache

### 4. **Secure Delete**
- Overwrite files 7 times (DOD standard)
- Option for sensitive data

---

## 🌟 **Premium Features Ideas**

### 1. **Real-time Monitoring**
Menu bar mostra espaço livre em tempo real

### 2. **Smart Alerts**
"Você pode limpar 10GB de cache do Xcode!"

### 3. **Cloud Integration**
Backup de configurações via iCloud

### 4. **Multiple Profiles**
- Developer profile (foca em dev tools)
- Designer profile (foca em creative apps)
- Gamer profile (foca em gaming)

---

## 🚀 **Performance Optimizations**

### 1. **Parallel Scanning**
Escaneia múltiplas categorias simultaneamente

### 2. **Incremental Scan**
Só re-escaneia o que mudou desde último scan

### 3. **Background Cleaning**
Limpa em background sem travar UI

### 4. **Smart Caching**
Guarda resultados de scan por X minutos

---

## 📱 **iOS Companion App**

### Features:
- Limpa cache do iPhone/iPad remotamente
- Mostra estatísticas do Mac
- Triggers limpeza no Mac via Handoff

---

## 🎯 **Quick Wins (Implementação Rápida)**

1. ✅ **Steam Cache** - 30 minutos
2. ✅ **Discord Cache** - 20 minutos
3. ✅ **Zoom Cache** - 20 minutos
4. ✅ **Teams Cache** - 25 minutos
5. ✅ **iOS Backups** - 40 minutos
6. ✅ **Time Machine Snapshots** - 60 minutos
7. ✅ **Old Screenshots** - 30 minutos

**Total:** ~4 horas para adicionar 7 categorias novas!

---

## 📈 **Impacto Potencial Total**

Com **TODAS** as expansões:
- **Categorias:** 35+
- **Espaço recuperável:** 100-500GB+
- **Apps suportados:** 30+

---

## 🏆 **Prioridade de Implementação**

### Alta Prioridade (Quick Wins)
1. ✅ Steam, Discord, Zoom, Teams
2. ✅ iOS Backups
3. ✅ Time Machine Snapshots
4. ✅ Category Groups na UI

### Média Prioridade
1. Adobe Creative Cloud
2. Smart Scan (detecta apps instalados)
3. Schedule Cleaning
4. Cleaning History

### Baixa Prioridade (Complexo)
1. Secure Delete
2. iOS Companion App
3. Cloud Integration
4. Predictive Cleaning

---

**Nota:** Este documento é uma lista de ideias. Implemente conforme a necessidade e prioridade do seu caso de uso!

**Quer implementar alguma dessas ideias? Só avisar!** 🚀
