import Foundation
import SwiftData
import SwiftUI

enum TipoHabito: String, CaseIterable, Codable {
    /// "Ficar sem palavrão": contador de tempo sem deslize
    case abstinencia
    /// "Beber água 8x": toca pra somar até a meta do dia
    case contagem
    /// "Pausar e respirar 5 min": cronômetro
    case duracao

    var nome: String {
        switch self {
        case .abstinencia: return "Abstinência"
        case .contagem: return "Contagem"
        case .duracao: return "Duração"
        }
    }
}

enum Repeticao: String, CaseIterable, Codable {
    case nunca, diario, semanal
    var nome: String {
        switch self {
        case .nunca: return "Uma vez"
        case .diario: return "Todo dia"
        case .semanal: return "Toda semana"
        }
    }
}

@Model
final class Tarefa {
    var id: UUID = UUID()
    var titulo: String = ""
    /// Dia e hora do lembrete. Sem hora = tarefa do dia, sem alerta.
    var quando: Date?
    var temHora: Bool = false
    var repeticaoRaw: String = Repeticao.nunca.rawValue
    var concluidaEm: Date?
    var criadaEm: Date = Date.now

    init(titulo: String, quando: Date?, temHora: Bool, repeticao: Repeticao = .nunca) {
        self.titulo = titulo
        self.quando = quando
        self.temHora = temHora
        self.repeticaoRaw = repeticao.rawValue
    }

    var repeticao: Repeticao {
        get { Repeticao(rawValue: repeticaoRaw) ?? .nunca }
        set { repeticaoRaw = newValue.rawValue }
    }

    /// Tarefa que se repete conta como feita só no dia em que foi marcada
    func feita(em dia: Date = .now) -> Bool {
        guard let c = concluidaEm else { return false }
        return repeticao == .nunca || Calendar.current.isDate(c, inSameDayAs: dia)
    }

    func aparece(em dia: Date) -> Bool {
        let cal = Calendar.current
        guard let q = quando else {
            // Sem data: fica na lista até ser feita (e some no dia seguinte ao que foi feita)
            if let c = concluidaEm { return cal.isDate(c, inSameDayAs: dia) }
            return cal.startOfDay(for: criadaEm) <= cal.startOfDay(for: dia)
        }
        switch repeticao {
        case .nunca:
            if cal.isDate(q, inSameDayAs: dia) { return true }
            // Atrasada e não feita: continua aparecendo hoje
            return cal.isDateInToday(dia) && q < cal.startOfDay(for: dia) && concluidaEm == nil
        case .diario:
            return cal.startOfDay(for: q) <= cal.startOfDay(for: dia)
        case .semanal:
            return cal.startOfDay(for: q) <= cal.startOfDay(for: dia)
                && cal.component(.weekday, from: q) == cal.component(.weekday, from: dia)
        }
    }

    /// Horário que aparece na lista ("21:30")
    var horaTexto: String? {
        guard temHora, let q = quando else { return nil }
        return q.formatted(.dateTime.hour().minute())
    }
}

@Model
final class Habito {
    var id: UUID = UUID()
    var titulo: String = ""
    var descricao: String = ""
    var tipoRaw: String = TipoHabito.contagem.rawValue
    /// Quantas vezes por dia (contagem e duração)
    var meta: Int = 1
    /// Minutos do cronômetro (duração)
    var minutos: Int = 5
    var xp: Int = 10
    var icone: String = "sparkles"
    /// Nome do programa que gerou o hábito ("Parar de falar palavrão")
    var programa: String = ""
    /// Horários dos lembretes diários, "HH:mm"
    var lembretes: [String] = []
    /// Abstinência: desde quando está sem deslize
    var inicioContagem: Date = Date.now
    var recordeSegundos: Double = 0
    var criadoEm: Date = Date.now
    var ordem: Int = 0

    init(titulo: String, descricao: String, tipo: TipoHabito, meta: Int, minutos: Int, xp: Int,
         icone: String, programa: String, lembretes: [String]) {
        self.titulo = titulo
        self.descricao = descricao
        self.tipoRaw = tipo.rawValue
        self.meta = max(1, meta)
        self.minutos = max(1, minutos)
        self.xp = max(1, xp)
        self.icone = icone
        self.programa = programa
        self.lembretes = lembretes
    }

    var tipo: TipoHabito {
        get { TipoHabito(rawValue: tipoRaw) ?? .contagem }
        set { tipoRaw = newValue.rawValue }
    }

    var cor: Color {
        switch tipo {
        case .abstinencia: return Color(hex: 0x2FBF71)
        case .contagem: return .destaque
        case .duracao: return Color(hex: 0x3D8BFF)
        }
    }

    var frequenciaTexto: String {
        switch tipo {
        case .abstinencia: return "Diário"
        case .contagem, .duracao: return meta == 1 ? "1x por dia" : "\(meta)x por dia"
        }
    }
}

@Model
final class Registro {
    var id: UUID = UUID()
    var habitoID: UUID = UUID()
    var data: Date = Date.now
    /// true = "Escorreguei" num hábito de abstinência
    var deslize: Bool = false
    var xp: Int = 0

    init(habitoID: UUID, data: Date = .now, deslize: Bool = false, xp: Int) {
        self.habitoID = habitoID
        self.data = data
        self.deslize = deslize
        self.xp = xp
    }
}

// MARK: - Contas do dia, XP e níveis

enum Nivel: Int, CaseIterable {
    case bronze, prata, ouro, icone

    var nome: String {
        switch self {
        case .bronze: return "Bronze"
        case .prata: return "Prata"
        case .ouro: return "Ouro"
        case .icone: return "Ícone"
        }
    }

    var cor: Color {
        switch self {
        case .bronze: return Color(hex: 0xD08A55)
        case .prata: return Color(hex: 0xC9D2E3)
        case .ouro: return Color(hex: 0xF5C84C)
        case .icone: return Color.verde
        }
    }

    var xpMinimo: Int {
        switch self {
        case .bronze: return 0
        case .prata: return 300
        case .ouro: return 1000
        case .icone: return 3000
        }
    }

    static func de(_ xp: Int) -> Nivel {
        allCases.last(where: { xp >= $0.xpMinimo }) ?? .bronze
    }

    var proximo: Nivel? { Nivel(rawValue: rawValue + 1) }
}

/// XP por concluir uma tarefa
let xpTarefa = 5

struct Placar {
    let habitos: [Habito]
    let registros: [Registro]
    let tarefas: [Tarefa]

    func doDia(_ h: Habito, em dia: Date = .now) -> [Registro] {
        registros.filter { $0.habitoID == h.id && Calendar.current.isDate($0.data, inSameDayAs: dia) }
    }

    func feitosHoje(_ h: Habito, em dia: Date = .now) -> Int {
        doDia(h, em: dia).filter { !$0.deslize }.count
    }

    func completo(_ h: Habito, em dia: Date = .now) -> Bool {
        switch h.tipo {
        case .abstinencia:
            // Conta como cumprido se não escorregou no dia (e o hábito já existia)
            let cal = Calendar.current
            guard cal.startOfDay(for: h.criadoEm) <= cal.startOfDay(for: dia) else { return false }
            return !doDia(h, em: dia).contains { $0.deslize }
        case .contagem, .duracao:
            return feitosHoje(h, em: dia) >= h.meta
        }
    }

    func tarefas(em dia: Date) -> [Tarefa] {
        tarefas.filter { $0.aparece(em: dia) }
            .sorted { ($0.quando ?? .distantFuture) < ($1.quando ?? .distantFuture) }
    }

    /// (feitos, total) do dia: hábitos + tarefas
    func progresso(em dia: Date = .now) -> (Int, Int) {
        let hs = habitos.filter { Calendar.current.startOfDay(for: $0.criadoEm) <= Calendar.current.startOfDay(for: dia) }
        let ts = tarefas(em: dia)
        let feitos = hs.filter { completo($0, em: dia) }.count + ts.filter { $0.feita(em: dia) }.count
        return (feitos, hs.count + ts.count)
    }

    /// Placar de 0 a 100 dos últimos 7 dias (o anel "70" do vídeo)
    var pontuacao: Int {
        let cal = Calendar.current
        var soma = 0.0
        var dias = 0.0
        for i in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -i, to: .now) else { continue }
            let (f, t) = progresso(em: d)
            if t > 0 { soma += Double(f) / Double(t); dias += 1 }
        }
        return dias == 0 ? 0 : Int((soma / dias * 100).rounded())
    }

    var xpTotal: Int {
        registros.reduce(0) { $0 + $1.xp }
            + tarefas.filter { $0.concluidaEm != nil }.count * xpTarefa
    }

    /// Dias seguidos com pelo menos um registro ou tarefa feita
    var sequencia: Int {
        let cal = Calendar.current
        var n = 0
        var dia = Date.now
        if !teveAtividade(dia) { dia = cal.date(byAdding: .day, value: -1, to: dia) ?? dia }
        while teveAtividade(dia) {
            n += 1
            guard let d = cal.date(byAdding: .day, value: -1, to: dia) else { break }
            dia = d
        }
        return n
    }

    private func teveAtividade(_ dia: Date) -> Bool {
        let cal = Calendar.current
        return registros.contains { !$0.deslize && cal.isDate($0.data, inSameDayAs: dia) }
            || tarefas.contains { t in t.concluidaEm.map { cal.isDate($0, inSameDayAs: dia) } ?? false }
    }
}

extension TimeInterval {
    /// 0d 03h 12m 09s
    var contador: (d: Int, h: Int, m: Int, s: Int) {
        let t = Int(max(0, self))
        return (t / 86400, t % 86400 / 3600, t % 3600 / 60, t % 60)
    }

    var duracaoCurta: String {
        let c = contador
        if c.d > 0 { return "\(c.d)d \(c.h)h" }
        if c.h > 0 { return "\(c.h)h \(c.m)m" }
        return "\(c.m)m \(c.s)s"
    }
}
