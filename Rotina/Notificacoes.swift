import Foundation
import SwiftData
import UserNotifications

enum Notificacoes {
    static func pedirPermissao() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func agora(_ titulo: String, _ corpo: String, depoisDe segundos: TimeInterval? = nil, id: String = UUID().uuidString) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = corpo
        c.sound = .default
        let gatilho = segundos.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: gatilho))
    }

    static func cancelar(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Refaz todos os alertas: tarefas com hora e lembretes dos hábitos (o iPhone guarda no máximo 64)
    @MainActor
    static func reagendar(_ ctx: ModelContext) {
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        var pedidos: [UNNotificationRequest] = []

        let tarefas = (try? ctx.fetch(FetchDescriptor<Tarefa>())) ?? []
        for t in tarefas where t.temHora {
            guard let q = t.quando else { continue }
            let c = UNMutableNotificationContent()
            c.title = t.titulo
            c.body = "Lembrete do LBO Rotina"
            c.sound = .default
            c.userInfo = ["tarefa": t.id.uuidString]
            let gatilho: UNCalendarNotificationTrigger
            switch t.repeticao {
            case .nunca:
                guard q > .now, t.concluidaEm == nil else { continue }
                gatilho = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: q), repeats: false)
            case .diario:
                gatilho = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.hour, .minute], from: q), repeats: true)
            case .semanal:
                gatilho = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.weekday, .hour, .minute], from: q), repeats: true)
            }
            pedidos.append(UNNotificationRequest(identifier: "tarefa-\(t.id.uuidString)", content: c, trigger: gatilho))
        }

        let habitos = (try? ctx.fetch(FetchDescriptor<Habito>())) ?? []
        for h in habitos {
            for (i, texto) in h.lembretes.enumerated() {
                let partes = texto.split(separator: ":").compactMap { Int($0) }
                guard partes.count == 2 else { continue }
                let c = UNMutableNotificationContent()
                c.title = h.titulo
                c.body = frase(h)
                c.sound = .default
                c.userInfo = ["habito": h.id.uuidString]
                let gatilho = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: partes[0], minute: partes[1]),
                                                            repeats: true)
                pedidos.append(UNNotificationRequest(identifier: "habito-\(h.id.uuidString)-\(i)", content: c, trigger: gatilho))
            }
        }

        // Apaga os antigos (menos o aviso do cronômetro) e só depois cria os novos
        let novos = Array(pedidos.prefix(60))
        center.getPendingNotificationRequests { pendentes in
            let ids = pendentes.map(\.identifier).filter { $0 != "cronometro" }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            for p in novos { center.add(p) }
        }
    }

    private static func frase(_ h: Habito) -> String {
        switch h.tipo {
        case .abstinencia: return "Você tá indo bem. Segue firme hoje."
        case .contagem: return h.meta > 1 ? "Bora registrar? Meta de hoje: \(h.meta)x." : "Hora de fazer e registrar."
        case .duracao: return "Tira \(h.minutos) min pra isso agora."
        }
    }
}

/// Transforma o que a IA devolveu em tarefas e hábitos salvos
enum Aplicador {
    @MainActor
    @discardableResult
    static func salvar(_ r: Interpretacao, ctx: ModelContext) -> (tarefas: [Tarefa], habitos: [Habito]) {
        let cal = Calendar.current
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"

        var novasTarefas: [Tarefa] = []
        for t in r.tarefas where !t.titulo.trimmingCharacters(in: .whitespaces).isEmpty {
            var quando: Date? = iso.date(from: t.data)
            var temHora = false
            let hm = t.hora.split(separator: ":").compactMap { Int($0) }
            if hm.count == 2 {
                let base = quando ?? .now
                quando = cal.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: base)
                temHora = true
                if t.data.isEmpty, let q = quando, q < .now { quando = cal.date(byAdding: .day, value: 1, to: q) }
            }
            let nova = Tarefa(titulo: t.titulo, quando: quando, temHora: temHora,
                              repeticao: Repeticao(rawValue: t.repeticao) ?? .nunca)
            ctx.insert(nova)
            novasTarefas.append(nova)
        }

        let ordemBase = ((try? ctx.fetch(FetchDescriptor<Habito>()))?.map(\.ordem).max() ?? 0) + 1
        var novosHabitos: [Habito] = []
        for (i, h) in r.habitos.enumerated() where !h.titulo.isEmpty {
            let novo = Habito(titulo: h.titulo, descricao: h.descricao,
                              tipo: TipoHabito(rawValue: h.tipo) ?? .contagem,
                              meta: h.meta, minutos: h.minutos, xp: h.xp,
                              icone: IA.icones.contains(h.icone) ? h.icone : "sparkles",
                              programa: r.programa,
                              lembretes: h.lembretes.filter { $0.contains(":") })
            novo.ordem = ordemBase + i
            ctx.insert(novo)
            novosHabitos.append(novo)
        }
        try? ctx.save()
        reagendar(ctx)
        return (novasTarefas, novosHabitos)
    }

    @MainActor
    static func reagendar(_ ctx: ModelContext) { Notificacoes.reagendar(ctx) }
}
