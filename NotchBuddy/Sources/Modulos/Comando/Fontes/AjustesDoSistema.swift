import Foundation

// As páginas dos Ajustes do Sistema, para abrir direto pelo nome. Os identificadores são os
// das extensões de ajuste do próprio macOS (conferidos neste Mac, em
// /System/Library/ExtensionKit/Extensions); o endereço é `x-apple.systempreferences:<id>`.

struct AjusteDoSistema: Sendable {
    let id: String
    let nome: String
    /// SF Symbol.
    let icone: String
    let palavras: [String]

    var url: URL? { URL(string: "x-apple.systempreferences:" + id) }

    static let todos: [AjusteDoSistema] = [
        .init(id: "com.apple.wifi-settings-extension", nome: "Wi-Fi", icone: "wifi", palavras: ["wifi", "rede sem fio", "internet"]),
        .init(id: "com.apple.BluetoothSettings", nome: "Bluetooth", icone: "dot.radiowaves.left.and.right", palavras: ["fone", "airpods"]),
        .init(id: "com.apple.Network-Settings.extension", nome: "Rede", icone: "network", palavras: ["network", "ethernet", "dns", "proxy", "internet"]),
        .init(id: "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", nome: "VPN", icone: "lock.shield", palavras: []),
        .init(id: "com.apple.Notifications-Settings.extension", nome: "Notificações", icone: "bell.badge", palavras: ["notifications", "avisos"]),
        .init(id: "com.apple.Sound-Settings.extension", nome: "Som", icone: "speaker.wave.2", palavras: ["sound", "audio", "volume", "saida", "entrada", "microfone"]),
        .init(id: "com.apple.Focus-Settings.extension", nome: "Foco", icone: "moon", palavras: ["focus", "nao perturbe"]),
        .init(id: "com.apple.Screen-Time-Settings.extension", nome: "Tempo de Uso", icone: "hourglass", palavras: ["screen time"]),
        .init(id: "com.apple.systempreferences.GeneralSettings", nome: "Geral", icone: "gear", palavras: ["general"]),
        .init(id: "com.apple.SystemProfiler.AboutExtension", nome: "Sobre este Mac", icone: "laptopcomputer", palavras: ["about", "versao do macos", "numero de serie"]),
        .init(id: "com.apple.Software-Update-Settings.extension", nome: "Atualização de Software", icone: "arrow.down.circle", palavras: ["software update", "atualizar macos"]),
        .init(id: "com.apple.settings.Storage", nome: "Armazenamento", icone: "internaldrive", palavras: ["storage", "espaco em disco"]),
        .init(id: "com.apple.AirDrop-Handoff-Settings.extension", nome: "AirDrop e Handoff", icone: "airplayaudio", palavras: ["airplay"]),
        .init(id: "com.apple.LoginItems-Settings.extension", nome: "Itens de Início", icone: "power", palavras: ["login items", "abrir ao iniciar", "itens de inicio e extensoes"]),
        .init(id: "com.apple.Localization-Settings.extension", nome: "Idioma e Região", icone: "globe", palavras: ["language", "region", "idiomas de traducao"]),
        .init(id: "com.apple.Date-Time-Settings.extension", nome: "Data e Hora", icone: "clock", palavras: ["date", "time", "fuso"]),
        .init(id: "com.apple.Sharing-Settings.extension", nome: "Compartilhamento", icone: "person.2.wave.2", palavras: ["sharing", "nome do computador", "acesso remoto"]),
        .init(id: "com.apple.Time-Machine-Settings.extension", nome: "Time Machine", icone: "clock.arrow.circlepath", palavras: ["backup"]),
        .init(id: "com.apple.Transfer-Reset-Settings.extension", nome: "Transferir ou Redefinir", icone: "arrow.triangle.2.circlepath", palavras: ["reset", "apagar mac"]),
        .init(id: "com.apple.Startup-Disk-Settings.extension", nome: "Disco de Inicialização", icone: "externaldrive", palavras: ["startup disk"]),
        .init(id: "com.apple.Appearance-Settings.extension", nome: "Aparência", icone: "circle.lefthalf.filled", palavras: ["appearance", "modo escuro", "modo claro", "tema"]),
        .init(id: "com.apple.Accessibility-Settings.extension", nome: "Acessibilidade", icone: "accessibility", palavras: ["accessibility", "zoom", "voiceover"]),
        .init(id: "com.apple.ControlCenter-Settings.extension", nome: "Central de Controle", icone: "switch.2", palavras: ["control center", "barra de menus"]),
        .init(id: "com.apple.Siri-Settings.extension", nome: "Siri", icone: "waveform.circle", palavras: ["apple intelligence"]),
        .init(id: "com.apple.Spotlight-Settings.extension", nome: "Spotlight", icone: "magnifyingglass", palavras: ["busca"]),
        .init(id: "com.apple.settings.PrivacySecurity.extension", nome: "Privacidade e Segurança", icone: "hand.raised", palavras: ["privacy", "security", "permissoes", "gravacao de tela", "acesso total ao disco"]),
        .init(id: "com.apple.Desktop-Settings.extension", nome: "Mesa e Dock", icone: "dock.rectangle", palavras: ["desktop", "dock", "stage manager", "mission control"]),
        .init(id: "com.apple.Displays-Settings.extension", nome: "Telas", icone: "display", palavras: ["displays", "monitor", "resolucao", "brilho", "night shift"]),
        .init(id: "com.apple.Wallpaper-Settings.extension", nome: "Imagem de Fundo", icone: "photo", palavras: ["wallpaper", "papel de parede"]),
        .init(id: "com.apple.Battery-Settings.extension", nome: "Bateria", icone: "battery.75percent", palavras: ["battery", "energia", "economia"]),
        .init(id: "com.apple.Lock-Screen-Settings.extension", nome: "Tela Bloqueada", icone: "lock.display", palavras: ["lock screen", "protetor de tela", "desligar tela"]),
        .init(id: "com.apple.Touch-ID-Settings.extension", nome: "Touch ID e Senha", icone: "touchid", palavras: ["password", "digital"]),
        .init(id: "com.apple.Users-Groups-Settings.extension", nome: "Usuários e Grupos", icone: "person.2", palavras: ["users", "contas do mac"]),
        .init(id: "com.apple.Internet-Accounts-Settings.extension", nome: "Contas de Internet", icone: "at", palavras: ["internet accounts", "email", "google"]),
        .init(id: "com.apple.systempreferences.AppleIDSettings", nome: "Conta Apple", icone: "person.crop.circle", palavras: ["apple id", "apple account", "icloud"]),
        .init(id: "com.apple.Keyboard-Settings.extension", nome: "Teclado", icone: "keyboard", palavras: ["keyboard", "atalhos de teclado", "ditado", "fontes de entrada"]),
        .init(id: "com.apple.Mouse-Settings.extension", nome: "Mouse", icone: "computermouse", palavras: []),
        .init(id: "com.apple.Trackpad-Settings.extension", nome: "Trackpad", icone: "rectangle.and.hand.point.up.left", palavras: ["gestos"]),
        .init(id: "com.apple.Print-Scan-Settings.extension", nome: "Impressoras e Scanners", icone: "printer", palavras: ["printers", "imprimir"]),
        .init(id: "com.apple.Game-Center-Settings.extension", nome: "Game Center", icone: "gamecontroller", palavras: []),
        .init(id: "com.apple.WalletSettingsExtension", nome: "Carteira e Apple Pay", icone: "creditcard", palavras: ["wallet"]),
    ]
}
