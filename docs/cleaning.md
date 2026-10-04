# Cleaning categories

MAC-LIMPO ships **46 cleaning categories**. Each one is scanned first — the popover shows how much it would free — and only cleaned when you click it (or *Clean All*), after a confirmation.

!!! tip "Aggressive mode"
    Some categories hold back large caches that are expensive to rebuild (local AI models, all unused Docker images, old simulator runtimes). Turn on **Aggressive cleaning** in the popover settings to include them.

## Development

| Category | What it cleans |
|---|---|
| **.NET SDKs** | Remove superseded .NET SDK and runtime patches (keeps newest of each line; asks admin password) |
| **AI Models** | Remove local AI model caches (Ollama/LM Studio models need aggressive mode) |
| **AI Tools** | Clear AI tools cache (Claude, Gemini, Cursor, Copilot) |
| **Android SDK** | Clean Gradle cache and old Android SDK data |
| **API Tools** | Clean Postman, Insomnia, Bruno caches and logs |
| **Azure Tools** | Remove downloaded Azure Functions Core Tools versions |
| **Bun Cache** | Clear Bun's global install cache |
| **Cargo/Rust** | Clean Rust/Cargo build cache and registry |
| **Cypress** | Clean Cypress test data and browser binary cache |
| **Dev Packages** | Clear npm, pip, brew, and cargo caches |
| **Docker** | Remove unused containers, images, and volumes |
| **Expo Cache** | Clear Expo Go, APK, and simulator app caches |
| **Go Cache** | Clean Go module cache, build cache, and gopls |
| **Homebrew** | Clear Homebrew package download cache |
| **IDE Cache** | Clean JetBrains, VS Code, Cursor caches |
| **iOS Simulators** | Remove old iOS Simulator devices and data |
| **Node Versions** | Remove old nvm Node versions (keeps default and newest per major) |
| **NuGet Cache** | Clear the global NuGet package cache (restored on dotnet build) |
| **Playwright** | Remove Playwright browser caches |
| **pnpm Store** | Clean pnpm package store and dlx/metadata caches |
| **Project Builds** | Clean node_modules and build artifacts from projects |
| **pub Cache** | Clear downloaded Dart/Flutter pub packages (re-fetched on pub get) |
| **Rust Targets** | Remove Cargo target/ build directories from Rust projects |
| **Terminal Logs** | Remove old terminal log files |
| **Xcode Cache** | Clean DerivedData, Archives, and build caches |
| **Zed Cache** | Remove Zed's downloaded runtimes, language servers, and logs |

## System

| Category | What it cleans |
|---|---|
| **App Leftovers** | Remove data from uninstalled apps (JetBrains, Trae, etc) |
| **Logs** | Clean up old system and app logs (30+ days) |
| **System Data** | Deep clean system caches and temporary data |
| **Temp Files** | Delete temporary files and caches |
| **Trash Bin** | Empty Trash and recover space |
| **Var Folders** | Clean /var/folders temp caches (Chrome, Metal, clang) |

## Apps & Browsers

| Category | What it cleans |
|---|---|
| **Adobe Cache** | Clear Adobe apps cache and media files |
| **App Cache** | Clear application caches |
| **Browser Cache** | Clear Safari, Chrome, Firefox cache |
| **Creative Apps** | Clean Canva, Affinity, Figma caches |
| **Google Cache** | Clear Chrome regenerable profile caches and old Google Updater versions |
| **Notion Cache** | Remove Notion asset cache and GPU caches |
| **Old Downloads** | Remove downloads older than 30 days |

## Communication

| Category | What it cleans |
|---|---|
| **Mail Attachments** | Clean old Mail app attachments |
| **Messages Attachments** | Remove old Messages attachments |
| **Messaging Apps** | Clean WhatsApp, Teams, Discord caches |
| **Slack Cache** | Clear Slack cache and temp files |

Something missing? [Suggest a category](https://github.com/alexkads/MAC-LIMPO/issues/new?template=feature_request.yml) or [add one yourself](development.md#adding-a-cleaning-category).
