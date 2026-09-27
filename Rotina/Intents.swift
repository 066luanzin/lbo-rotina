import AppIntents

/// Abre o app já ouvindo: "Fale uma tarefa ou lembrete…"
/// Use no Atalhos → Central de Controle ou Tocar Atrás (2 toques)
struct CapturaRapidaIntent: AppIntent {
    static var title: LocalizedStringResource = "Captura rápida"
    static var description = IntentDescription("Abre o LBO Rotina ouvindo uma tarefa ou lembrete.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.captura = .tarefa
        return .result()
    }
}

/// Abre o app no "Me conta sua dificuldade" pra montar um programa de hábitos
struct MontarProgramaIntent: AppIntent {
    static var title: LocalizedStringResource = "Montar programa de hábitos"
    static var description = IntentDescription("Conte uma dificuldade e o LBO Rotina monta hábitos pra você.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.captura = .dificuldade
        return .result()
    }
}

struct RotinaAtalhos: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CapturaRapidaIntent(),
            phrases: [
                "Captura rápida no \(.applicationName)",
                "Nova tarefa no \(.applicationName)"
            ],
            shortTitle: "Captura rápida",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: MontarProgramaIntent(),
            phrases: [
                "Montar programa no \(.applicationName)"
            ],
            shortTitle: "Montar programa",
            systemImageName: "sparkles"
        )
    }
}
