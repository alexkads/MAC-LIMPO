# 🔍 Análise de Problemas e Correções - MAC-LIMPO

## ✅ PROBLEMAS CORRIGIDOS

### 1. ❌ Comando sudo sem permissão (CRÍTICO)
**Arquivo:** `LogsCleaningService.swift`
**Problema:** A linha `sudo log erase --all` falharia porque a aplicação não pode solicitar senha.
**Correção:** Removido o comando sudo e adicionado comentário explicativo sobre como implementar corretamente usando SMJobBless.

### 2. ❌ Race condition em cleanAll() (CRÍTICO)
**Arquivo:** `MenuBarView.swift` - `MenuBarViewModel.cleanAll()`
**Problema:** Criava múltiplas Tasks concorrentes que competiam para atualizar `showProgress`, causando comportamento imprevisível.
**Correção:** Refatorado para executar limpezas **sequencialmente** (uma por vez) com await adequado.

### 3. ❌ Wildcard incorreto no AppCacheCleaningService
**Arquivo:** `AppCacheCleaningService.swift`
**Problema:** Padrão `"com.adobe.*"` não funcionava porque o ponto antes do asterisco causava problemas.
**Correção:** Alterado para `"com.adobe*"` (sem o ponto).

### 4. ❌ Falta de timeout em comandos shell (CRÍTICO)
**Arquivo:** `ShellExecutor.swift`
**Problema:** Comandos como `docker system prune` poderiam travar indefinidamente.
**Correção:** 
- Adicionado parâmetro `timeout` com padrão de 60 segundos
- Implementado verificação de timeout e terminação forçada se necessário
- Docker agora tem timeout de 5 minutos

### 5. ❌ Memory leak potencial com DispatchQueue
**Arquivo:** `LaunchAtLoginService.swift`
**Problema:** Uso de `DispatchQueue.main.async` poderia causar retain cycles.
**Correção:** Substituído por `Task { @MainActor in }` que é mais seguro.

---

## ⚠️ AVISOS IMPORTANTES

### 1. Permissões do macOS
A aplicação **REQUER Full Disk Access** para funcionar corretamente:
- **Como ativar:** System Settings > Privacy & Security > Full Disk Access > Adicione MAC-LIMPO

**Diretórios que requerem permissão:**
- `~/Library/Caches`
- `~/Library/Logs`
- `/tmp` (alguns arquivos)
- Cache de aplicativos

### 2. Docker precisa estar rodando
O `DockerCleaningService` só funciona se:
- Docker Desktop estiver instalado
- Docker daemon estiver rodando
- Usuário tiver permissões para executar comandos docker

### 3. Comandos podem demorar
Algumas operações podem levar vários minutos:
- Docker cleanup: até 5 minutos
- Xcode DerivedData: pode ter dezenas de GB
- Cache de navegadores

---

## 🐛 PROBLEMAS CONHECIDOS (NÃO CORRIGIDOS)

### 1. Falta feedback de permissões
**Impacto:** Médio
**Descrição:** Quando a aplicação não tem Full Disk Access, ela falha silenciosamente ao tentar acessar alguns diretórios.
**Solução futura:** Adicionar verificação de permissões e mostrar alerta ao usuário.

### 2. Não há botão "Cancel" funcional
**Impacto:** Baixo
**Descrição:** O botão "Cancel" na view de progresso apenas fecha a UI, mas não para a operação em andamento.
**Solução futura:** Implementar Task cancellation com `Task.checkCancellation()`.

### 3. Estimativa de tamanho pode ser imprecisa
**Impacto:** Baixo
**Descrição:** O scan apenas estima o tamanho, e a limpeza real pode remover mais ou menos.
**Motivo:** Alguns comandos (como `docker system prune`) não reportam tamanho exato antes da execução.

### 4. Xcode DerivedData pode estar em uso
**Impacto:** Médio
**Descrição:** Se Xcode estiver aberto, a limpeza de DerivedData pode falhar parcialmente.
**Solução:** Usuário deve fechar Xcode antes de limpar.

---

## 📋 CHECKLIST PARA TESTE

Antes de usar a aplicação, verifique:

- [ ] Xcode está fechado (para limpar DerivedData)
- [ ] Docker Desktop está rodando (se for limpar Docker)
- [ ] Full Disk Access está habilitado para MAC-LIMPO
- [ ] Fez backup de dados importantes
- [ ] Não há processos críticos rodando

---

## 🚀 PRÓXIMOS PASSOS RECOMENDADOS

### Alta Prioridade
1. **Adicionar verificação de permissões**
   - Verificar Full Disk Access antes de iniciar scan
   - Mostrar alerta com instruções se não tiver permissão

2. **Implementar cancelamento real**
   - Usar `Task.isCancelled` nos serviços de limpeza
   - Parar operações em andamento quando usuário clicar em Cancel

3. **Melhorar tratamento de erros**
   - Diferenciar entre "sem permissão" e "erro real"
   - Mostrar mensagens mais amigáveis

### Média Prioridade
4. **Adicionar logs de debug**
   - Usar `os_log` para debugging
   - Ajudar a diagnosticar problemas

5. **Implementar dry-run mode**
   - Mostrar o que seria removido sem realmente remover
   - Dar mais confiança ao usuário

6. **Adicionar confirmação para ações perigosas**
   - Alert antes de limpar Docker (pode remover imagens importantes)
   - Alert antes de limpar logs do sistema

### Baixa Prioridade
7. **Adicionar estatísticas históricas**
   - Guardar quanto espaço foi limpo ao longo do tempo
   - Mostrar gráfico de tendências

8. **Suporte a agendamento**
   - Limpar automaticamente uma vez por semana
   - Notificar usuário quando muito espaço for liberado

---

## 🔧 COMO COMPILAR E EXECUTAR

1. Abra o projeto no Xcode
2. Selecione o target "My Mac"
3. Pressione ⌘R para compilar e executar
4. Procure o ícone na barra de menu (canto superior direito)
5. Habilite Full Disk Access se solicitado

---

## 📞 TROUBLESHOOTING

### Aplicação não aparece na barra de menu
- Verifique se `LSUIElement` está configurado no Info.plist
- Verifique console para erros de inicialização

### Scan mostra "0 bytes" para tudo
- Você provavelmente não tem Full Disk Access
- Vá em System Settings > Privacy & Security > Full Disk Access

### Docker cleanup falha
- Verifique se Docker Desktop está rodando
- Execute `docker ps` no Terminal para testar
- Verifique se tem permissão para executar comandos docker

### Aplicação trava durante limpeza
- Isso pode acontecer com operações muito grandes
- O timeout de 5 minutos deve prevenir travamentos permanentes
- Se travar, force quit e reporte o problema

---

## 📝 NOTAS DE DESENVOLVIMENTO

### Arquitetura
- **SwiftUI** para toda a interface
- **Swift Concurrency** (async/await) para operações assíncronas
- **Protocol-based services** para cada categoria de limpeza
- **MVVM pattern** com `@StateObject` e `@Published`

### Dependências
- Sem dependências externas (apenas frameworks do sistema)
- `ServiceManagement` para Launch at Login
- `AppKit` para menu bar integration

### Compatibilidade
- **macOS 27.0+**
- Swift 6.4 em modo Swift 6
- Requer Xcode 27 para compilar

---

**Data da última análise:** 23/09/2026
**Versão do código:** 1.3.7
**Status:** ✅ Problemas críticos corrigidos
