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
            var gatilhos: [UNCalendarNotificationTrigger] = []
            switch t.repeticao {
            case .nunca:
                guard q > .now, t.concluidaEm == nil else { continue }
                gatilhos = [UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: q), repeats: false)]
            case .diario:
                gatilhos = [UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.hour, .minute], from: q), repeats: true)]
            case .semanal:
                gatilhos = [UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.weekday, .hour, .minute], from: q), repeats: true)]
            case .dias:
                // Um aviso repetido pra cada dia escolhido (ex.: segunda a sexta)
                var comps = cal.dateComponents([.hour, .minute], from: q)
                for dia in t.dias {
                    comps.weekday = dia
                    gatilhos.append(UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
                }
            }
            for (i, gatilho) in gatilhos.enumerated() {
                let id = i == 0 ? "tarefa-\(t.id.uuidString)" : "tarefa-\(t.id.uuidString)-d\(i)"
                pedidos.append(UNNotificationRequest(identifier: id, content: c, trigger: gatilho))
            }

            // Insiste mais 2 vezes (+3 e +10 min) enquanto a tarefa não for marcada como feita
            if t.repeticao == .nunca {
                for (i, atraso) in [3, 10].enumerated() {
                    guard let depois = cal.date(byAdding: .minute, value: atraso, to: q) else { continue }
                    let n = UNMutableNotificationContent()
                    n.title = "⏰ \(t.titulo)"
                    n.body = "Ainda não marcou como feita. Toque pra abrir."
                    n.sound = .default
                    n.userInfo = ["tarefa": t.id.uuidString]
                    pedidos.append(UNNotificationRequest(
                        identifier: "tarefa-\(t.id.uuidString)-\(i)", content: n,
                        trigger: UNCalendarNotificationTrigger(
                            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: depois), repeats: false)))
                }
            }
        }

        // Blocos da agenda (Google Agenda) dos próximos 7 dias
        let agora = Date.now
        let blocos = Agenda.shared.blocos(de: agora, ate: cal.date(byAdding: .day, value: 7, to: agora) ?? agora)

        // Alarme de verdade (iOS 26) pras tarefas com horário ainda não feitas
        // e pros blocos marcados como importantes (ex.: Alinhamento SOF, Fechamento do dia)
        var alarmes: [Alarmes.Pedido] = tarefas.compactMap { t in
            guard t.temHora, let q = t.quando, !(t.repeticao == .nunca && t.concluidaEm != nil) else { return nil }
            return Alarmes.Pedido(id: t.id, titulo: t.titulo, quando: q, repeticao: t.repeticao, dias: t.dias)
        }
        alarmes += blocos.filter(Agenda.tocaAlarme).prefix(14).map {
            Alarmes.Pedido(id: UUID(texto: $0.id), titulo: $0.titulo, quando: $0.inicio, repeticao: .nunca)
        }
        Alarmes.reagendar(alarmes)

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

        // Lembrete de check-in, de segunda a sexta: "Faltam 4 blocos e 1 tarefa sem check-in"
        if UserDefaults.standard.object(forKey: "lembreteCheckin") as? Bool ?? true {
            let feitos = (try? ctx.fetch(FetchDescriptor<BlocoFeito>())) ?? []
            let idsFeitos = Set(feitos.map(\.blocoID))
            let placar = Placar(habitos: [], registros: [], tarefas: tarefas)
            let horarios = horasCheckin().compactMap { h -> [Int]? in
                let hm = h.split(separator: ":").compactMap { Int($0) }
                return hm.count == 2 ? hm : nil
            }
            for n in 0..<7 {
                for (i, hm) in horarios.enumerated() {
                guard let d = cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: agora)),
                      (2...6).contains(cal.component(.weekday, from: d)),
                      let quando = cal.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: d),
                      quando > agora else { continue }
                let c = UNMutableNotificationContent()
                c.title = "Check-in do dia ✅"
                c.sound = .default
                if n == 0 {
                    // Hoje dá pra contar o que falta de verdade
                    let blocosFaltando = Agenda.shared.blocos(do: d).filter { $0.inicio < quando && !idsFeitos.contains($0.id) }.count
                    let tarefasFaltando = placar.tarefas(em: d).filter { !$0.feita(em: d) }.count
                    if blocosFaltando + tarefasFaltando == 0 { continue }
                    var partes: [String] = []
                    if blocosFaltando > 0 { partes.append(blocosFaltando == 1 ? "1 bloco" : "\(blocosFaltando) blocos") }
                    if tarefasFaltando > 0 { partes.append(tarefasFaltando == 1 ? "1 tarefa" : "\(tarefasFaltando) tarefas") }
                    c.body = "Faltam \(partes.joined(separator: " e ")) sem check-in. Bora marcar o que você já fez?"
                } else {
                    c.body = "Já deu check-in nos blocos e tarefas de hoje? Marca o que você fez."
                }
                pedidos.append(UNNotificationRequest(
                    identifier: "checkin-\(n)-\(i)", content: c,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: quando), repeats: false)))
                }
            }
        }

        // Blocos da agenda: "Em 5 min: Operação" antes e "Terminou: Operação. Fez?" no fim (com botões).
        // O iPhone guarda no máximo 64 avisos, então entram os mais próximos primeiro.
        var avisosBlocos: [(quando: Date, pedido: UNNotificationRequest)] = []
        let jaFeitos = Set(((try? ctx.fetch(FetchDescriptor<BlocoFeito>())) ?? []).map(\.blocoID))
        for b in blocos {
            if Agenda.avisarAntes {
                let antes = Agenda.minutosAntes
                let quando = b.inicio.addingTimeInterval(TimeInterval(-antes * 60))
                if quando > agora {
                    let c = UNMutableNotificationContent()
                    c.title = antes == 0 ? "Agora: \(b.titulo)" : "Em \(antes) min: \(b.titulo)"
                    c.body = b.horario
                    c.sound = .default
                    avisosBlocos.append((quando, UNNotificationRequest(
                        identifier: "bloco-\(UUID(texto: b.id).uuidString)", content: c,
                        trigger: UNCalendarNotificationTrigger(
                            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: quando), repeats: false))))
                }
            }
            if Agenda.perguntarNoFim, b.fim > agora, !jaFeitos.contains(b.id) {
                let c = UNMutableNotificationContent()
                c.title = "Terminou: \(b.titulo)"
                c.body = "Fez? Segure a notificação pra marcar ✅ Feito."
                c.sound = .default
                c.categoryIdentifier = categoriaFimBloco
                c.userInfo = ["blocoID": b.id, "titulo": b.titulo, "inicio": b.inicio.timeIntervalSince1970]
                avisosBlocos.append((b.fim, UNNotificationRequest(
                    identifier: "fim-\(UUID(texto: b.id).uuidString)", content: c,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: b.fim), repeats: false))))
            }
        }
        for aviso in avisosBlocos.sorted(by: { $0.quando < $1.quando }) {
            guard pedidos.count < 60 else { break }
            pedidos.append(aviso.pedido)
        }

        // Apaga os antigos (menos o aviso do cronômetro) e só depois cria os novos
        let novos = Array(pedidos.prefix(60))
        center.getPendingNotificationRequests { pendentes in
            // Mantém o cronômetro e os "adiar 15 min" que ainda vão tocar
            let ids = pendentes.map(\.identifier).filter { $0 != "cronometro" && !$0.hasPrefix("adiado-") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            for p in novos { center.add(p) }
        }
    }

    // MARK: Botões da notificação de fim de bloco

    static let categoriaFimBloco = "fim-bloco"

    static func registrarCategorias() {
        let feito = UNNotificationAction(identifier: "feito", title: "✅ Feito", options: [])
        let adiar = UNNotificationAction(identifier: "adiar", title: "⏰ Adiar 15 min", options: [])
        let categoria = UNNotificationCategory(identifier: categoriaFimBloco, actions: [feito, adiar],
                                               intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([categoria])
    }

    /// "✅ Feito" na notificação: grava o check-in sem abrir o app
    @MainActor
    static func marcarBloco(blocoID: String, titulo: String, inicio: Date) {
        let ctx = Banco.container.mainContext
        let id = blocoID
        let existentes = (try? ctx.fetch(FetchDescriptor<BlocoFeito>(predicate: #Predicate { $0.blocoID == id }))) ?? []
        if existentes.isEmpty {
            ctx.insert(BlocoFeito(blocoID: blocoID, titulo: titulo, inicio: inicio))
            try? ctx.save()
        }
        reagendar(ctx)
    }

    /// "⏰ Adiar 15 min": pergunta de novo daqui a 15 minutos
    static func adiar(titulo: String, corpo: String, blocoID: String, tituloBloco: String, inicio: Date) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = corpo
        c.sound = .default
        c.categoryIdentifier = categoriaFimBloco
        c.userInfo = ["blocoID": blocoID, "titulo": tituloBloco, "inicio": inicio.timeIntervalSince1970]
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "adiado-\(UUID().uuidString)", content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)))
    }

    /// Horários do lembrete de check-in, ex.: ["12:00", "17:00"]
    static func horasCheckin() -> [String] {
        let d = UserDefaults.standard
        let lista = (d.string(forKey: "horasCheckin") ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lista.isEmpty ? [d.string(forKey: "horaCheckin") ?? "17:00"] : lista
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
            // "dias:2,3,4,5,6" = de segunda a sexta
            let ehDias = t.repeticao.hasPrefix("dias:")
            let nova = Tarefa(titulo: t.titulo, quando: quando, temHora: temHora,
                              repeticao: ehDias ? .dias : (Repeticao(rawValue: t.repeticao) ?? .nunca))
            if ehDias { nova.diasRaw = String(t.repeticao.dropFirst(5)) }
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
