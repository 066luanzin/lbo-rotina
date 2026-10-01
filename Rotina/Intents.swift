import AppIntents
import SwiftData

/// "E aí Siri, nota no LBO Rotina" → "Climax: subi o orçamento". Salva sem abrir o app.
struct NovaNotaIntent: AppIntent {
    static var title: LocalizedStringResource = "Nova nota de cliente"
    static var description = IntentDescription("Salva uma nota de cliente ou ideia de vídeo sem abrir o app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Nota", requestValueDialog: "Qual é a nota?")
    var texto: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Banco.container.mainContext
        Seeds.clientes(ctx)
        let clientes = ((try? ctx.fetch(FetchDescriptor<Cliente>())) ?? []).filter(\.ativo).map(\.info)
        let n = InterpretadorLocal.nota(texto, clientes: clientes)
        ctx.insert(Nota(texto: n.texto, cliente: n.cliente, tipo: n.tipo))
        try? ctx.save()
        let quem = n.tipo == "ideia" ? "Ideia de vídeo" : (n.cliente.isEmpty ? "Nota" : n.cliente)
        return .result(dialog: "Salvei. \(quem): \(n.texto)")
    }
}

/// "E aí Siri, lembrete no LBO Rotina" → "pagar o boleto amanhã às 10". Salva sem abrir o app.
struct NovaTarefaIntent: AppIntent {
    static var title: LocalizedStringResource = "Nova tarefa ou lembrete"
    static var description = IntentDescription("Cria uma tarefa com lembrete sem abrir o app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Tarefa", requestValueDialog: "O que eu te lembro?")
    var texto: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Banco.container.mainContext
        let r = InterpretadorLocal.interpretar(texto, modo: .tarefa)
        Aplicador.salvar(r, ctx: ctx)
        return .result(dialog: "\(r.resumo)")
    }
}

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
            intent: NovaNotaIntent(),
            phrases: [
                "Nota no \(.applicationName)",
                "Anotar no \(.applicationName)"
            ],
            shortTitle: "Nova nota",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: NovaTarefaIntent(),
            phrases: [
                "Lembrete no \(.applicationName)",
                "Me lembra no \(.applicationName)"
            ],
            shortTitle: "Novo lembrete",
            systemImageName: "bell"
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
