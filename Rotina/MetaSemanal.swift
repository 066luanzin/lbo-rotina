import Foundation

/// Meta da semana: % dos blocos da agenda com check-in (segunda a domingo)
@MainActor
enum MetaSemanal {
    static var meta: Int { UserDefaults.standard.object(forKey: "metaSemanal") as? Int ?? 80 }
    /// XP extra por semana que bateu a meta
    static let xpBonus = 50

    static func inicioSemana(_ d: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d)
    }

    static func bateu(feitos: Int, total: Int) -> Bool {
        total > 0 && Double(feitos) / Double(total) * 100 >= Double(meta)
    }

    /// (feitos, total) da semana atual, até o fim de hoje
    static func semanaAtual(feitos ids: Set<String>) -> (feitos: Int, total: Int) {
        let cal = Calendar.current
        let fim = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        let blocos = Agenda.shared.blocos(de: inicioSemana(.now), ate: fim)
        return (blocos.filter { ids.contains($0.id) }.count, blocos.count)
    }

    /// Semanas fechadas (últimos 6 meses) que bateram a meta e a sequência atual de semanas seguidas
    static func historico(feitos ids: Set<String>) -> (batidas: Int, sequencia: Int) {
        let cal = Calendar.current
        let atual = inicioSemana(.now)
        guard let inicio = cal.date(byAdding: .day, value: -7 * 26, to: atual) else { return (0, 0) }
        let blocos = Agenda.shared.blocos(de: inicio, ate: atual)
        let porSemana = Dictionary(grouping: blocos) { inicioSemana($0.inicio) }
        var batidas = 0
        var sequencia = 0
        var contando = true
        for k in 1...26 {
            guard let semana = cal.date(byAdding: .day, value: -7 * k, to: atual) else { continue }
            let lista = porSemana[semana] ?? []
            if lista.isEmpty { contando = false; continue }
            if bateu(feitos: lista.filter { ids.contains($0.id) }.count, total: lista.count) {
                batidas += 1
                if contando { sequencia += 1 }
            } else {
                contando = false
            }
        }
        return (batidas, sequencia)
    }
}
