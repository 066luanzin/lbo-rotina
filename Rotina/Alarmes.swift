import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Alarme de verdade (iOS 26+): toca em tela cheia, com som, mesmo no silencioso, igual ao despertador.
enum Alarmes {
    static var ligado: Bool { UserDefaults.standard.object(forKey: "alarmeTarefas") as? Bool ?? true }

    static var disponivel: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    struct Pedido {
        let id: UUID
        let titulo: String
        let quando: Date
        let repeticao: Repeticao
        var dias: [Int] = []
    }

    /// true = autorizado
    @discardableResult
    static func pedirPermissao() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26, *) {
            let m = AlarmManager.shared
            switch m.authorizationState {
            case .authorized: return true
            case .denied: return false
            default: return (try? await m.requestAuthorization()) == .authorized
            }
        }
        #endif
        return false
    }

    static var autorizado: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26, *) { return AlarmManager.shared.authorizationState == .authorized }
        #endif
        return false
    }

    /// Apaga os alarmes do app e cria de novo a partir das tarefas
    static func reagendar(_ pedidos: [Pedido]) {
        #if canImport(AlarmKit)
        if #available(iOS 26, *) {
            Task { await reagendar26(pedidos) }
        }
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26, *)
    private static func reagendar26(_ pedidos: [Pedido]) async {
        let m = AlarmManager.shared
        for a in (try? m.alarms) ?? [] { try? m.cancel(id: a.id) }
        guard ligado, m.authorizationState == .authorized else { return }

        let cal = Calendar.current
        let semana: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        for p in pedidos.prefix(40) {
            let alerta = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: p.titulo),
                stopButton: AlarmButton(text: "Parar", textColor: .white, systemImageName: "stop.circle")
            )
            let atributos = AlarmAttributes<MetaAlarme>(presentation: AlarmPresentation(alert: alerta),
                                                       tintColor: Color.verde)
            let h = cal.component(.hour, from: p.quando)
            let mi = cal.component(.minute, from: p.quando)
            let agenda: Alarm.Schedule
            switch p.repeticao {
            case .nunca:
                guard p.quando > .now else { continue }
                agenda = .fixed(p.quando)
            case .diario:
                agenda = .relative(.init(time: .init(hour: h, minute: mi), repeats: .weekly(semana)))
            case .semanal:
                let dia = semana[cal.component(.weekday, from: p.quando) - 1]
                agenda = .relative(.init(time: .init(hour: h, minute: mi), repeats: .weekly([dia])))
            case .dias:
                guard !p.dias.isEmpty else { continue }
                agenda = .relative(.init(time: .init(hour: h, minute: mi), repeats: .weekly(p.dias.map { semana[$0 - 1] })))
            }
            let config = AlarmManager.AlarmConfiguration<MetaAlarme>(schedule: agenda, attributes: atributos)
            _ = try? await m.schedule(id: p.id, configuration: config)
        }
    }
    #endif
}

#if canImport(AlarmKit)
@available(iOS 26, *)
struct MetaAlarme: AlarmMetadata {}
#endif
