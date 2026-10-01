import Foundation

// Este arquivo só usa Foundation, pra poder ser testado fora do iPhone (Testes/TesteInterpretador.swift).

/// O que foi entendido da fala (pelo interpretador local ou pela IA)
struct Interpretacao: Codable {
    struct TarefaIA: Codable {
        var titulo: String
        var data: String       // "AAAA-MM-DD" ou ""
        var hora: String       // "HH:mm" ou ""
        var repeticao: String  // nunca | diario | semanal
        /// false = só notificação; true = toca alarme; nil = padrão (toca)
        var alarme: Bool?
    }
    struct HabitoIA: Codable {
        var titulo: String
        var descricao: String
        var tipo: String       // abstinencia | contagem | duracao
        var meta: Int
        var minutos: Int
        var xp: Int
        var icone: String
        var lembretes: [String]
    }
    var resumo: String
    var programa: String
    var tarefas: [TarefaIA]
    var habitos: [HabitoIA]
}

enum ModoCaptura: String, Identifiable {
    /// "Fale uma tarefa ou lembrete"
    case tarefa
    /// "JA Climatização: pausei a campanha…" / "ideia de vídeo: …"
    case nota
    /// "Me conta sua dificuldade" → programa de hábitos
    case dificuldade
    var id: String { rawValue }
}

/// Entende a fala sem internet e sem custo: datas, horários, repetição e o título da tarefa
enum InterpretadorLocal {
    static func interpretar(_ fala: String, modo: ModoCaptura, agora: Date = Date()) -> Interpretacao {
        switch modo {
        case .tarefa, .nota: return tarefa(fala, agora: agora)
        case .dificuldade: return Programas.montar(fala)
        }
    }

    // MARK: - Leitor: acha um trecho, devolve os grupos e apaga o trecho do texto

    final class Leitor {
        var texto: String
        init(_ t: String) { texto = t }

        func tirar(_ padrao: String) -> [String?]? {
            guard let re = try? NSRegularExpression(pattern: padrao, options: [.caseInsensitive]) else { return nil }
            let ns = texto as NSString
            guard let m = re.firstMatch(in: texto, range: NSRange(location: 0, length: ns.length)) else { return nil }
            var grupos: [String?] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                grupos.append(r.location == NSNotFound ? nil : ns.substring(with: r))
            }
            texto = ns.replacingCharacters(in: m.range, with: " ")
            return grupos
        }
    }

    static func dobrar(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
    }

    static let meses = "janeiro|fevereiro|mar[çc]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro"
    static let diasSemana = "segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo"

    static func mes(_ s: String) -> Int? {
        if let n = Int(s) { return (1...12).contains(n) ? n : nil }
        let nomes = ["janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho", "agosto",
                     "setembro", "outubro", "novembro", "dezembro"]
        return nomes.firstIndex(of: dobrar(s)).map { $0 + 1 }
    }

    /// Dia da semana no padrão do Calendar (1 = domingo)
    static func diaSemana(_ s: String) -> Int? {
        let d = dobrar(s)
        let ordem = ["domingo", "segunda", "terca", "quarta", "quinta", "sexta", "sabado"]
        return ordem.firstIndex(where: { d.hasPrefix($0) }).map { $0 + 1 }
    }

    static func numero(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let d = dobrar(s)
        let palavras = ["uma": 1, "um": 1, "duas": 2, "dois": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
                        "sete": 7, "oito": 8, "nove": 9, "dez": 10, "onze": 11, "doze": 12, "quinze": 15,
                        "vinte": 20, "trinta": 30, "quarenta": 40, "meia": 30, "primeiro": 1]
        return palavras[d]
    }

    static func minutos(_ extra: String?) -> Int {
        guard let e = extra.map(dobrar) else { return 0 }
        if e == "meia" { return 30 }
        if e == "quinze" { return 15 }
        if e.hasPrefix("quarenta") { return 45 }
        return Int(e) ?? 0
    }

    // MARK: - Tarefa

    static func tarefa(_ fala: String, agora: Date) -> Interpretacao {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let hoje = cal.startOfDay(for: agora)
        func dia(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: hoje)! }
        func em(_ d: Date, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: d)! }
        func proximo(_ semana: Int, incluindoHoje: Bool) -> Date {
            var diff = (semana - cal.component(.weekday, from: hoje) + 7) % 7
            if diff == 0 && !incluindoHoje { diff = 7 }
            return dia(diff)
        }

        // Limpeza: acentos no formato padrão (o reconhecimento de voz às vezes manda "a" + "~" separados),
        // "p.m." → pm, "1º" → 1, pontuação vira espaço
        var s = fala.precomposedStringWithCanonicalMapping
        s = s.replacingOccurrences(of: "p.m.", with: " pm", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "a.m.", with: " am", options: .caseInsensitive)
        for c in ["º", "°", "ª"] { s = s.replacingOccurrences(of: c, with: "") }
        s = s.replacingOccurrences(of: #"[,;!?]|(?<!\d)\.|\.(?!\d)"#, with: " ", options: .regularExpression)
        let pedeLembrete = dobrar(s).range(of: #"lembr|avis|alarm|desperta|notific"#, options: .regularExpression) != nil
        let L = Leitor(s)

        // Padrão do app: só notificação. Alarme (barulho) só quando pedir:
        // "cria um alarme…", "coloca o alarme com barulho", "me acorda…", "despertador"
        var alarme: Bool?
        if L.tirar(#"\b(?:sem\s+(?:o\s+)?(?:alarme|despertador|despertar|tocar|barulho)|s[óo]\s+(?:a\s+|com\s+)?notifica[çc][ãa]o|s[óo]\s+(?:o\s+)?(?:lembrete|aviso)|no\s+silencioso)\b"#) != nil {
            alarme = false
        } else {
            let pedidosAlarme = [
                #"\b(?:cria|crie|criar|faz|fa[çc]a|marca|marque|programa|programe|coloca|coloque|bota|bote|p[õo]e|ponha|liga|ligue)\s+(?:(?:pra|para)\s+mim\s+)?(?:o\s+|um\s+)?(?:alarme|despertador)(?:\s+(?:pra|para)\s+mim)?(?:\s+com\s+barulho)?\b"#,
                #"\b(?:com|e)\s+(?:o\s+)?(?:alarme|despertador|barulho)(?:\s+com\s+barulho)?\b"#,
                #"\b(?:tocando|toca(?:r)?)\s+(?:o\s+)?alarme\b"#,
                #"\bme\s+acord[ae]\b"#,
                // "alarme" solto, mas não "testar o alarme"
                #"\b(?<![oa]\s)(?:um\s+)?(?:alarme|despertador)\b"#,
            ]
            for p in pedidosAlarme {
                while L.tirar(p) != nil { alarme = true }
            }
        }

        var quandoExato: Date?
        var data: Date?
        var disseHoje = false
        var repeticao = "nunca"
        var semanaRep: Int?
        var periodo: String?
        var hora: Int?
        var minuto = 0
        var ampm: String?

        // "daqui a 20 minutos", "em meia hora", "daqui a 2 horas"
        if let g = L.tirar(#"\b(?:daqui\s+a|daqui|em|dentro\s+de)\s+(\d{1,3}|meia|uma|um|duas|dois|tr[êe]s|cinco|dez|quinze|vinte|trinta|quarenta)\s+(minutos?|min|horas?)\b"#),
           let n = numero(g[1] ?? "") {
            let unidade = dobrar(g[2] ?? "")
            let meia = dobrar(g[1] ?? "") == "meia"
            let segundos = unidade.hasPrefix("hora") ? (meia ? 1800 : n * 3600) : n * 60
            quandoExato = agora.addingTimeInterval(TimeInterval(segundos))
        }

        // Repetição por dias da semana: "de segunda a sexta", "dias úteis", "fim de semana", "segunda, quarta e sexta"
        var diasRep: [Int] = []
        let ds = #"(?:\#(diasSemana))(?:[- ]feiras?)?"#
        if let g = L.tirar(#"\b(?:tod[oa]s?\s+(?:os\s+dias\s+)?)?(?:de\s+|da\s+|das\s+)?(\#(diasSemana))(?:[- ]feiras?)?\s+(?:a|à|ao|at[ée])\s+(\#(diasSemana))(?:[- ]feiras?)?\b"#),
           let de = diaSemana(g[1] ?? ""), let ate = diaSemana(g[2] ?? "") {
            var d = de
            while true {
                diasRep.append(d)
                if d == ate || diasRep.count >= 7 { break }
                d = d % 7 + 1
            }
        } else if L.tirar(#"\b(?:tod[oa]s?\s+(?:os\s+)?)?(?:n?os\s+|em\s+)?dias?\s+[úu]te(?:is|l)\b|\bdurante\s+a\s+semana\b"#) != nil {
            diasRep = [2, 3, 4, 5, 6]
        } else if L.tirar(#"\b(?:tod[oa]s?\s+(?:os\s+)?)?(?:n[oa]s?\s+|aos\s+)?(?:fim|fins)\s+de\s+semana\b"#) != nil {
            diasRep = [7, 1]
        } else if let g = L.tirar(#"\b(?:tod[oa]s?\s+(?:as\s+|os\s+)?)?(?:n[ao]s?\s+|[àa]s\s+)?(\#(ds)(?:\s+(?:e\s+)?\#(ds))+)\b"#),
                  let re = try? NSRegularExpression(pattern: diasSemana, options: [.caseInsensitive]) {
            let lista = g[1] ?? ""
            let ns = lista as NSString
            for m in re.matches(in: lista, range: NSRange(location: 0, length: ns.length)) {
                if let d = diaSemana(ns.substring(with: m.range)), !diasRep.contains(d) { diasRep.append(d) }
            }
        }
        if diasRep.count == 7 { diasRep = []; repeticao = "diario" }
        if !diasRep.isEmpty { repeticao = "dias" }

        if repeticao != "nunca" {
            // já decidido acima
        } else if L.tirar(#"\btod[oa]s?\s+(?:os\s+|o\s+)?dias?\b|\bdiariamente\b"#) != nil {
            repeticao = "diario"
        } else if let g = L.tirar(#"\btod[oa]s?\s+(?:as\s+|os\s+)?(\#(diasSemana))s?(?:[- ]feiras?)?\b"#) {
            repeticao = "semanal"
            semanaRep = diaSemana(g[1] ?? "")
        } else if L.tirar(#"\btoda\s+semana\b"#) != nil {
            repeticao = "semanal"
        }

        // Dia
        if L.tirar(#"\bdepois\s+de\s+amanh[ãa]\b"#) != nil {
            data = dia(2)
        } else if L.tirar(#"\bamanh[ãa]\b"#) != nil {
            data = dia(1)
        } else if L.tirar(#"\bhoje\b"#) != nil {
            data = hoje
            disseHoje = true
        }
        if data == nil {
            var diaMes: Int?
            var mesNum: Int?
            let prefixo = #"(?:(?:n?o|para\s+o|pro|at[ée]\s+o)\s+)?"#
            if let g = L.tirar(#"\b\#(prefixo)dia\s+(\d{1,2}|primeiro)(?:\s*(?:/|de|do)\s*(\d{1,2}|\#(meses)))?\b"#) {
                diaMes = numero(g[1] ?? ""); mesNum = g[2].flatMap { mes($0) }
            } else if let g = L.tirar(#"\b(\d{1,2})\s*/\s*(\d{1,2})(?:\s*/\s*\d{2,4})?\b"#) {
                diaMes = Int(g[1] ?? ""); mesNum = g[2].flatMap { mes($0) }
            } else if let g = L.tirar(#"\b\#(prefixo)(\d{1,2}|primeiro)\s+(?:de|do)\s+(\#(meses))\b"#) {
                diaMes = numero(g[1] ?? ""); mesNum = g[2].flatMap { mes($0) }
            } else if let g = L.tirar(#"\b\#(prefixo)(\d{1,2})\s+do\s+(\d{1,2})\b"#) {
                diaMes = Int(g[1] ?? ""); mesNum = g[2].flatMap { mes($0) }
            }
            if let d = diaMes, (1...31).contains(d) {
                var ano = cal.component(.year, from: hoje)
                var m = mesNum ?? cal.component(.month, from: hoje)
                if mesNum == nil && d < cal.component(.day, from: hoje) { m += 1 }
                if m > 12 { m = 1; ano += 1 }
                if var alvo = cal.date(from: DateComponents(year: ano, month: m, day: d)) {
                    if alvo < hoje, let prox = cal.date(byAdding: .year, value: 1, to: alvo) { alvo = prox }
                    if cal.component(.day, from: alvo) == d { data = alvo }
                }
            }
        }
        if data == nil,
           let g = L.tirar(#"\b(?:(?:n[ao]|na\s+pr[óo]xima|no\s+pr[óo]ximo|pr[óo]xim[ao]|nesta|nessa|esta|essa)\s+)?(\#(diasSemana))(?:[- ]feira)?\b"#),
           let sem = diaSemana(g[1] ?? "") {
            data = proximo(sem, incluindoHoje: false)
        }
        if data == nil, let sem = semanaRep {
            data = proximo(sem, incluindoHoje: true)
        }

        // Período do dia
        if let g = L.tirar(#"\b(?:d[ae]|pela|[àa])\s+(manh[ãa]|tarde|noite|madrugada)\b"#) {
            periodo = dobrar(g[1] ?? "")
        }

        // Horário
        let antes = #"(?:(?:por\s+volta\s+)?(?:d[aà]s|[àa]s|pras?|para(?:\s+as)?|at[ée]\s+[àa]s|umas)\s+)"#
        let extra = #"(?:\s*e\s*(meia|quinze|quarenta\s+e\s+cinco|\d{1,2})(?:\s*minutos?)?)?"#
        let sufixo = #"(?:\s*(am|pm)\b)?"#
        let palavrasHora = "uma|duas|dois|tr[êe]s|quatro|cinco|seis|sete|oito|nove|dez|onze|doze"

        if let g = L.tirar(#"\b(?:ao\s+|[àa]o?\s+)?meio[- ]dia(\s+e\s+meia)?\b"#) {
            hora = 12; minuto = g[1] == nil ? 0 : 30; ampm = "pm"
        } else if L.tirar(#"\b(?:[àa]\s+)?meia[- ]noite\b"#) != nil {
            hora = 0; minuto = 0; ampm = "am"
        } else if let g = L.tirar(#"\#(antes)?\b(\d{1,2})\s*[:h.]\s*(\d{2})\b\#(sufixo)"#) {
            hora = Int(g[1] ?? ""); minuto = Int(g[2] ?? "") ?? 0; ampm = g[3]
        } else if let g = L.tirar(#"\#(antes)?\b(\d{1,2})\s*(?:h|hs|hrs?|horas?)\b\#(extra)\#(sufixo)"#) {
            hora = Int(g[1] ?? ""); minuto = minutos(g[2]); ampm = g[3]
        } else if let g = L.tirar(#"\#(antes)\b(\d{1,2})\b\#(extra)\#(sufixo)"#) {
            hora = Int(g[1] ?? ""); minuto = minutos(g[2]); ampm = g[3]
        } else if let g = L.tirar(#"\b(\d{1,2})\s+e\s+(meia|quinze)\b\#(sufixo)"#) {
            hora = Int(g[1] ?? ""); minuto = minutos(g[2]); ampm = g[3]
        } else if let g = L.tirar(#"\b(\d{1,2})\s*(am|pm)\b"#) {
            hora = Int(g[1] ?? ""); ampm = g[2]
        } else if let g = L.tirar(#"\#(antes)\b(\#(palavrasHora))\b(?:\s+horas?)?\#(extra)\#(sufixo)"#) {
            hora = numero(g[1] ?? ""); minuto = minutos(g[2]); ampm = g[3]
        } else if let g = L.tirar(#"\b(\#(palavrasHora))\s+(?:horas?\s+)?e\s+(meia|quinze|quarenta\s+e\s+cinco)\b\#(sufixo)"#) {
            // "seis e meia", "sete horas e quinze"
            hora = numero(g[1] ?? ""); minuto = minutos(g[2]); ampm = g[3]
        } else if let g = L.tirar(#"\b(\#(palavrasHora))\s+horas?\b\#(sufixo)"#) {
            hora = numero(g[1] ?? ""); ampm = g[2]
        }
        if let h = hora, !(0...23).contains(h) { hora = nil }
        minuto = min(59, max(0, minuto))

        // Resolve o horário final
        var quando: Date?
        var temHora = false
        if let exato = quandoExato {
            quando = exato
            temHora = true
        } else if var h = hora {
            let a = ampm.map(dobrar)
            let pm = a == "pm" || periodo == "tarde" || periodo == "noite"
            let am = a == "am" || periodo == "manha" || periodo == "madrugada"
            var ambigua = false
            if pm && h < 12 { h += 12 } else if am && h == 12 { h = 0 } else if !pm && !am && (1...11).contains(h) { ambigua = true }
            // Sem "da manhã/da tarde": de 1 a 5 é de tarde; de 6 a 11, de manhã
            let preferida = ambigua && h <= 5 ? h + 12 : h
            temHora = true
            if let d = data, !disseHoje {
                quando = em(d, preferida, minuto)
            } else if ambigua && repeticao == "nunca" {
                // "3:30" falado às 14h = 15:30: o próximo horário que ainda não passou
                if let proxima = [h, h + 12].map({ em(hoje, $0, minuto) }).first(where: { $0 > agora }) {
                    quando = proxima
                } else {
                    quando = em(disseHoje ? hoje : dia(1), preferida, minuto)
                }
            } else {
                var t = em(hoje, preferida, minuto)
                if t <= agora && !disseHoje && repeticao == "nunca" { t = em(dia(1), preferida, minuto) }
                quando = t
            }
        } else if let p = periodo {
            let h = ["manha": 8, "tarde": 15, "noite": 20, "madrugada": 6][p] ?? 9
            var t = em(data ?? hoje, h, 0)
            if data == nil && t <= agora && repeticao == "nunca" { t = em(dia(1), h, 0) }
            quando = t
            temHora = true
        } else if let d = data {
            if pedeLembrete && !disseHoje {
                quando = em(d, 9, 0)
                temHora = true
            } else {
                quando = d
            }
        } else if repeticao != "nunca" {
            quando = pedeLembrete ? em(hoje, 9, 0) : hoje
            temHora = pedeLembrete
        }

        // "De segunda a sexta": começa no próximo dia escolhido que ainda não passou
        if !diasRep.isEmpty, let q = quando {
            let h = cal.component(.hour, from: q)
            let mi = cal.component(.minute, from: q)
            for n in 0...7 {
                let d = dia(n)
                guard diasRep.contains(cal.component(.weekday, from: d)) else { continue }
                let t = temHora ? em(d, h, mi) : d
                if !temHora || t > agora { quando = t; break }
            }
        }

        // Título: o que sobrou da frase, sem "me lembra de", "quero que você", etc.
        // Se a pessoa se corrigiu ("não cria… na verdade…"), vale só o que veio depois
        if let re = try? NSRegularExpression(pattern: #"\b(?:na\s+verdade|quer\s+dizer|ou\s+melhor|melhor\s+dizendo|corrigindo)\b"#,
                                             options: [.caseInsensitive]) {
            let ns = L.texto as NSString
            if let ultima = re.matches(in: L.texto, range: NSRange(location: 0, length: ns.length)).last {
                let fim = ultima.range.location + ultima.range.length
                L.texto = ns.substring(from: fim)
            }
        }
        // "…com o nome de mandar mensagem pro Claude": o título é exatamente o que vem depois.
        // "…com a palavra plano" / um segundo "com o nome plano": é o conteúdo da mensagem, vai entre aspas
        // → Mandar mensagem pro Claude "plano"
        if let re = try? NSRegularExpression(
            pattern: #"\b(?:(com\s+o\s+(?:nome|t[íi]tulo)|com\s+(?:nome|t[íi]tulo)|chamad[oa]|que\s+se\s+chama|com\s+a\s+descri[çc][ãa]o)|(com\s+a\s+palavra|com\s+o\s+texto|escrito|dizendo))\b(?:\s+de\b)?"#,
            options: [.caseInsensitive]) {
            let ns = L.texto as NSString
            let achados = re.matches(in: L.texto, range: NSRange(location: 0, length: ns.length))
            if let primeiro = achados.first {
                func trecho(_ i: Int) -> String {
                    let ini = achados[i].range.location + achados[i].range.length
                    let fim = i + 1 < achados.count ? achados[i + 1].range.location : ns.length
                    return ns.substring(with: NSRange(location: ini, length: fim - ini))
                        .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
                }
                let primeiroEhNome = primeiro.range(at: 1).location != NSNotFound
                var nome = primeiroEhNome ? trecho(0) : ns.substring(to: primeiro.range.location)
                let conteudo = achados.indices
                    .filter { $0 > 0 || !primeiroEhNome }
                    .map(trecho)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !conteudo.isEmpty { nome += " \"\(conteudo)\"" }
                if !nome.trimmingCharacters(in: .whitespaces).isEmpty { L.texto = nome }
            }
        }
        var enchimentos = [
            #"\b(?:cria|crie|criar|coloca|coloque|colocar|bota|bote|p[õo]e|ponha|define|marca|marque|agenda|agende|faz|fa[çc]a|adiciona|adicione|salva|salve)\s+(?:(?:pra|para)\s+mim\s+)?(?:(?:um|uma|uns|umas)\s+)?(?:alarmes?|lembretes?|tarefas?|despertador(?:es)?|notifica[çc](?:[ãa]o|[õo]es))\b(?:\s+(?:de|para|pra|que))?"#,
            #"\b(?:um|uma)\s+(?:alarme|despertador|lembrete|tarefa)\b(?:\s+(?:de|para|pra))?"#,
            #"\b(?:pra|para)\s+mim\b"#,
            #"\b(?:beleza|valeu|obrigad[oa]|t[áa]\s+bom|pode\s+ser|fechou)\b"#,
            #"\b(?:ei|oi|ok|ol[áa])\b"#,
            #"\b(?:eu\s+)?(?:quero|queria|gostaria)\s+(?:que\s+)?(?:voc[êe]\s+|vc\s+)?(?:me\s+)?(?:lembr[ae]s?|avis[ae]s?)\b(?:\s+(?:de|que|para|pra))?"#,
            #"\b(?:me\s+)?(?:lembre-me|lembr[ae]r?|avis[ae]r?)\b(?:\s+(?:de|que|para|pra))?"#,
            #"\b(?:eu\s+)?(?:quero|queria|gostaria)\s+que\s+(?:voc[êe]|vc)\b"#,
            #"\bn[ãa]o\s+(?:me\s+)?deix[ae]r?\s+(?:eu\s+)?esquecer\b(?:\s+de)?"#,
            #"\bn[ãa]o\s+(?:posso\s+)?esquecer\b(?:\s+de)?"#,
            #"\b(?:um\s+|uns\s+)?lembretes?\b(?:\s+(?:de|para|pra))?"#,
            #"\b(?:eu\s+)?(?:preciso|tenho\s+que|tenho\s+de)\b(?:\s+de)?"#,
            #"\bpor\s+favor\b"#,
            #"\bmais\s+ou\s+menos\b"#,
            #"\bpor\s+volta\b(?:\s+d[ea]s?)?"#,
        ]
        // "…de segunda a sexta todo das 7h30": sobra o "todo"
        if repeticao != "nunca" { enchimentos.append(#"\btod[oa]s?\b(?:\s+(?:os|as)\b)?"#) }
        for e in enchimentos { while L.tirar(e) != nil {} }
        var palavras = L.texto.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let soltas: Set<String> = ["para", "pra", "pro", "as", "a", "no", "na", "do", "da", "de", "em", "dia", "o", "e",
                                   "que", "ate", "umas", "por", "la", "mais", "horas", "hora", "h", "das", "ao", "com", "pras"]
        while let p = palavras.last, soltas.contains(dobrar(p)) { palavras.removeLast() }
        while let p = palavras.first, soltas.contains(dobrar(p)) { palavras.removeFirst() }
        var titulo = palavras.joined(separator: " ")
        if titulo.isEmpty { titulo = alarme == true ? "Alarme" : fala.trimmingCharacters(in: .whitespacesAndNewlines) }
        titulo = titulo.prefix(1).uppercased() + titulo.dropFirst()

        // Saída
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.calendar = cal
        iso.timeZone = cal.timeZone
        iso.dateFormat = "yyyy-MM-dd"
        let hm = DateFormatter()
        hm.locale = Locale(identifier: "en_US_POSIX")
        hm.calendar = cal
        hm.timeZone = cal.timeZone
        hm.dateFormat = "HH:mm"

        let dataTexto = quando.map { iso.string(from: $0) } ?? ""
        let horaTexto = temHora ? quando.map { hm.string(from: $0) } ?? "" : ""

        var resumo = "Tarefa anotada!"
        if let q = quando {
            var diaFalado: String
            if repeticao == "dias" {
                let d = Set(diasRep)
                let nomes = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
                if d == Set(2...6) {
                    diaFalado = "de segunda a sexta"
                } else if d == Set(2...7) {
                    diaFalado = "de segunda a sábado"
                } else if d == [1, 7] {
                    diaFalado = "no fim de semana"
                } else {
                    let lista = diasRep.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { nomes[$0 - 1] }
                    diaFalado = "toda " + (lista.count > 1 ? lista.dropLast().joined(separator: ", ") + " e " + lista.last! : lista[0])
                }
            } else if repeticao == "diario" {
                diaFalado = "todo dia"
            } else if repeticao == "semanal" {
                let nomes = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
                diaFalado = "toda \(nomes[cal.component(.weekday, from: q) - 1])"
            } else if cal.isDate(q, inSameDayAs: hoje) {
                diaFalado = "hoje"
            } else if cal.isDate(q, inSameDayAs: dia(1)) {
                diaFalado = "amanhã"
            } else {
                let f = DateFormatter()
                f.locale = Locale(identifier: "pt_BR")
                f.timeZone = cal.timeZone
                f.dateFormat = "EEEE, dd/MM"
                diaFalado = f.string(from: q)
            }
            resumo = temHora ? "Beleza! Te lembro \(diaFalado) às \(horaTexto)." : "Anotado pra \(diaFalado)."
        }

        return Interpretacao(resumo: resumo, programa: "",
                             tarefas: [.init(titulo: titulo, data: dataTexto, hora: horaTexto,
                                             repeticao: diasRep.isEmpty ? repeticao
                                                 : "dias:" + diasRep.sorted().map(String.init).joined(separator: ","),
                                             alarme: alarme)],
                             habitos: [])
    }
}

// MARK: - Notas por cliente

struct NotaEntendida: Equatable {
    var cliente: String   // "" = geral
    var texto: String
    var tipo: String      // nota | ideia
}

struct ClienteInfo {
    let nome: String
    let apelidos: [String]
    let gmb: Bool
}

extension InterpretadorLocal {
    /// Clientes da agência (pasta clientes/ do ClaudePRO). Os apelidos cobrem como o reconhecimento de voz escreve.
    static let clientesPadrao: [ClienteInfo] = [
        ClienteInfo(nome: "JA Climatização", apelidos: ["ja climatizacao", "ja clima", "jota a"], gmb: true),
        ClienteInfo(nome: "CA Macirlene", apelidos: ["macirlene", "ms santos", "ca macirlene"], gmb: true),
        ClienteInfo(nome: "Climax Ar Condicionado", apelidos: ["climax"], gmb: true),
        ClienteInfo(nome: "Gás Express", apelidos: ["gas express"], gmb: true),
        ClienteInfo(nome: "Giselle Saggin", apelidos: ["giselle", "gisele", "saggin"], gmb: true),
        ClienteInfo(nome: "JL Ar Condicionado Sul", apelidos: ["jl ar", "jl", "jota ele"], gmb: true),
        ClienteInfo(nome: "Ludmila Furtado", apelidos: ["ludmila", "ludimila"], gmb: false),
        ClienteInfo(nome: "Sara Carvalho", apelidos: ["sara carvalho", "sara", "sarah"], gmb: false),
        ClienteInfo(nome: "Vtech Cell", apelidos: ["vtech", "v tech", "vitech", "vi tech"], gmb: false),
    ]

    /// "Na Climax subi o orçamento" → cliente Climax, texto "Subi o orçamento"
    static func nota(_ fala: String, clientes: [ClienteInfo]) -> NotaEntendida {
        let L = Leitor(fala.precomposedStringWithCanonicalMapping)
        var tipo = "nota"
        _ = L.tirar(#"^\s*(?:anot[ae]r?|nota|registr[ae]r?)(?:\s+(?:a[íi]|que))?\s*[:,\-–—]?\s*"#)
        if L.tirar(#"^\s*(?:uma\s+|tive\s+uma\s+)?ideias?(?:\s+(?:de|pra|para)\s+(?:um\s+)?(?:v[íi]deos?|conte[úu]dos?|posts?|reels?|stor(?:y|ies)))?\s*[:,\-–—]?\s*"#) != nil {
            tipo = "ideia"
        }

        // Cliente: o apelido mais longo que aparecer como palavra inteira
        let original = L.texto as NSString
        let dobrado = dobrar(L.texto) as NSString
        var achado: (nome: String, faixa: NSRange)?
        for c in clientes {
            for a in [c.nome] + c.apelidos {
                let alvo = NSRegularExpression.escapedPattern(for: dobrar(a))
                guard !alvo.isEmpty, let re = try? NSRegularExpression(pattern: "\\b" + alvo + "\\b") else { continue }
                if let m = re.firstMatch(in: dobrado as String, range: NSRange(location: 0, length: dobrado.length)),
                   m.range.length > (achado?.faixa.length ?? 0) {
                    achado = (c.nome, m.range)
                }
            }
        }
        var cliente = ""
        var t = L.texto
        if let a = achado {
            cliente = a.nome
            if dobrado.length == original.length {
                t = original.replacingCharacters(in: a.faixa, with: " ")
            }
        }
        // Conectores que sobraram: "Na  subi…", "Cliente  : …", "…da campanha da"
        t = t.replacingOccurrences(of: #"^\s*(?:(?:no|na|do|da|pro|pra|para\s+[oa]|o|a)\s+)?(?:cliente\s+)?[:,\-–—]?\s*"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+(?:no|na|do|da|pro|pra|para|de|o|a|cliente)\s*$"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :,-–—"))
        if t.isEmpty { t = fala.trimmingCharacters(in: .whitespacesAndNewlines) }
        t = t.prefix(1).uppercased() + t.dropFirst()
        return NotaEntendida(cliente: cliente, texto: t, tipo: tipo)
    }
}

// MARK: - Programas de hábitos prontos (sem IA)

enum Programas {
    typealias H = Interpretacao.HabitoIA

    static func montar(_ fala: String) -> Interpretacao {
        let d = InterpretadorLocal.dobrar(fala)
        func tem(_ padrao: String) -> Bool { d.range(of: padrao, options: .regularExpression) != nil }

        var nome = fala.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
        nome = nome.prefix(1).uppercased() + nome.dropFirst()
        var habitos: [H]

        if tem("palavr|xingar|xingo|falar mal|boca suja") {
            nome = "Parar de falar palavrão"
            habitos = [
                H(titulo: "Ficar sem palavrão", descricao: "Sempre que sentir vontade de soltar um palavrão, respire fundo, conte até 3 e troque por uma palavra neutra.", tipo: "abstinencia", meta: 1, minutos: 1, xp: 20, icone: "nosign", lembretes: ["09:00"]),
                H(titulo: "Registrar deslizes", descricao: "No fim do dia, anote quantas vezes escapou e em qual situação. Saber o gatilho é metade do caminho.", tipo: "contagem", meta: 1, minutos: 1, xp: 10, icone: "pencil", lembretes: ["21:30"]),
                H(titulo: "Pausar e respirar", descricao: "Nos momentos de frustração ou tensão, faça 3 respirações profundas antes de falar.", tipo: "duracao", meta: 5, minutos: 1, xp: 15, icone: "wind", lembretes: ["14:00"]),
            ]
        } else if tem("celular|instagram|tiktok|rede social|redes sociais|tela|youtube|scroll|rolar") {
            nome = "Usar menos o celular"
            habitos = [
                H(titulo: "Sem celular ao acordar", descricao: "Na primeira meia hora do dia, nada de redes sociais. Levante, beba água e só depois pegue o celular.", tipo: "abstinencia", meta: 1, minutos: 1, xp: 20, icone: "iphone", lembretes: ["07:00"]),
                H(titulo: "Bloco de foco sem celular", descricao: "Deixe o celular em outro cômodo e foque numa coisa só até o cronômetro acabar.", tipo: "duracao", meta: 2, minutos: 30, xp: 20, icone: "brain.head.profile", lembretes: ["10:00", "15:00"]),
                H(titulo: "Celular longe na cama", descricao: "Na hora de dormir, deixe o celular carregando longe da cama.", tipo: "contagem", meta: 1, minutos: 1, xp: 10, icone: "bed.double.fill", lembretes: ["22:30"]),
            ]
        } else if tem("dorm|sono|acordo|acordar|insonia|cansad") {
            nome = "Dormir melhor"
            habitos = [
                H(titulo: "Desligar as telas", descricao: "Uma hora antes de dormir, desligue TV e celular. Luz de tela atrasa o sono.", tipo: "contagem", meta: 1, minutos: 1, xp: 15, icone: "moon.fill", lembretes: ["22:00"]),
                H(titulo: "Relaxar antes de deitar", descricao: "Respiração lenta, leitura leve ou alongamento. Só isso, sem tela.", tipo: "duracao", meta: 1, minutos: 10, xp: 15, icone: "wind", lembretes: ["22:30"]),
                H(titulo: "Deitar no horário", descricao: "Deite sempre no mesmo horário, inclusive no fim de semana.", tipo: "contagem", meta: 1, minutos: 1, xp: 20, icone: "bed.double.fill", lembretes: ["23:00"]),
            ]
        } else if tem("agua|hidrat") {
            nome = "Beber mais água"
            habitos = [
                H(titulo: "Beber água", descricao: "Um copo cheio a cada registro. Deixe uma garrafa sempre à vista.", tipo: "contagem", meta: 8, minutos: 1, xp: 5, icone: "drop.fill", lembretes: ["09:00", "12:00", "15:00", "18:00"]),
                H(titulo: "Copo de água ao acordar", descricao: "Antes do café, um copo de água.", tipo: "contagem", meta: 1, minutos: 1, xp: 10, icone: "sun.max.fill", lembretes: ["07:30"]),
            ]
        } else if tem("fum|cigarro|vape|pod|nicotina|tabaco") {
            nome = "Parar de fumar"
            habitos = [
                H(titulo: "Sem fumar", descricao: "Conte cada hora limpa. Se escorregar, registre e recomece na hora, sem culpa.", tipo: "abstinencia", meta: 1, minutos: 1, xp: 30, icone: "nosign", lembretes: ["09:00", "18:00"]),
                H(titulo: "Respirar na vontade", descricao: "A vontade passa em poucos minutos. Quando bater, respire fundo até o cronômetro acabar.", tipo: "duracao", meta: 3, minutos: 3, xp: 15, icone: "wind", lembretes: ["14:00"]),
                H(titulo: "Registrar gatilhos", descricao: "Anote o que aconteceu antes da vontade: café, estresse, bebida, companhia.", tipo: "contagem", meta: 1, minutos: 1, xp: 10, icone: "pencil", lembretes: ["21:00"]),
            ]
        } else if tem("doce|acucar|refri|besteira|comer|comida|dieta|emagrec|peso|fast food") {
            nome = "Comer melhor"
            habitos = [
                H(titulo: "Sem doce e refri", descricao: "Hoje não. Se bater vontade, beba água e espere 10 minutos.", tipo: "abstinencia", meta: 1, minutos: 1, xp: 20, icone: "nosign", lembretes: ["15:00"]),
                H(titulo: "Água antes de comer", descricao: "Um copo de água antes de cada refeição.", tipo: "contagem", meta: 3, minutos: 1, xp: 5, icone: "drop.fill", lembretes: ["11:45", "19:30"]),
                H(titulo: "Prato com salada", descricao: "Metade do prato com salada ou legumes.", tipo: "contagem", meta: 2, minutos: 1, xp: 10, icone: "leaf.fill", lembretes: ["12:00"]),
            ]
        } else if tem("exercic|academia|treinar|treino|sedentar|caminhar|correr|preguica de mexer") {
            nome = "Me exercitar"
            habitos = [
                H(titulo: "Caminhar", descricao: "Uma caminhada em ritmo firme. Vale na rua, na esteira ou no trabalho.", tipo: "duracao", meta: 1, minutos: 20, xp: 25, icone: "figure.walk", lembretes: ["18:30"]),
                H(titulo: "Alongar", descricao: "Alongue pescoço, costas e pernas por alguns minutos.", tipo: "duracao", meta: 1, minutos: 5, xp: 10, icone: "dumbbell.fill", lembretes: ["07:30"]),
                H(titulo: "Separar a roupa do treino", descricao: "Deixe a roupa pronta na noite anterior. Tira a desculpa do dia seguinte.", tipo: "contagem", meta: 1, minutos: 1, xp: 5, icone: "checkmark.seal.fill", lembretes: ["21:00"]),
            ]
        } else if tem("procrastin|foco|concentr|preguica|enrol|adiar|produtiv|estud") {
            nome = "Parar de procrastinar"
            habitos = [
                H(titulo: "3 prioridades do dia", descricao: "De manhã, escreva as 3 coisas que precisam sair hoje. Comece pela mais chata.", tipo: "contagem", meta: 1, minutos: 1, xp: 10, icone: "checkmark.seal.fill", lembretes: ["08:00"]),
                H(titulo: "Foco total", descricao: "Um bloco de trabalho sem celular e sem abas abertas. Quando acabar, pausa de 5 minutos.", tipo: "duracao", meta: 4, minutos: 25, xp: 20, icone: "brain.head.profile", lembretes: ["09:00", "14:00"]),
                H(titulo: "Regra dos 2 minutos", descricao: "Se leva menos de 2 minutos, faça agora. Registre cada vez que fizer.", tipo: "contagem", meta: 3, minutos: 1, xp: 5, icone: "flame.fill", lembretes: []),
            ]
        } else if tem("ansie|estress|nervos|raiva|irrit|calma|preocup") {
            nome = "Controlar a ansiedade"
            habitos = [
                H(titulo: "Respiração 4-6", descricao: "Puxe o ar em 4 segundos e solte em 6. Repita até o cronômetro acabar.", tipo: "duracao", meta: 2, minutos: 5, xp: 15, icone: "wind", lembretes: ["10:00", "16:00"]),
                H(titulo: "Anotar o que sente", descricao: "Escreva em uma frase o que está sentindo e por quê. Tira o peso da cabeça.", tipo: "contagem", meta: 1, minutos: 1, xp: 10, icone: "pencil", lembretes: ["21:00"]),
                H(titulo: "Caminhada leve", descricao: "Uma volta sem fone e sem pressa, prestando atenção no caminho.", tipo: "duracao", meta: 1, minutos: 10, xp: 15, icone: "figure.walk", lembretes: ["18:00"]),
            ]
        } else if tem("ler|leitura|livro") {
            nome = "Ler mais"
            habitos = [
                H(titulo: "Ler", descricao: "Leia sem celular por perto até o cronômetro acabar.", tipo: "duracao", meta: 1, minutos: 15, xp: 15, icone: "book.fill", lembretes: ["21:30"]),
                H(titulo: "Livro à vista", descricao: "Deixe o livro num lugar que você passa todo dia.", tipo: "contagem", meta: 1, minutos: 1, xp: 5, icone: "checkmark.seal.fill", lembretes: []),
            ]
        } else {
            habitos = [
                H(titulo: "Ficar firme", descricao: "Conte o tempo sem cair no que você quer largar. Se escorregar, registre e recomece sem culpa.", tipo: "abstinencia", meta: 1, minutos: 1, xp: 20, icone: "nosign", lembretes: ["09:00"]),
                H(titulo: "Registrar gatilhos", descricao: "Anote rapidinho o que aconteceu antes da vontade aparecer.", tipo: "contagem", meta: 1, minutos: 1, xp: 10, icone: "pencil", lembretes: ["21:00"]),
                H(titulo: "Pausar e respirar", descricao: "Quando bater a vontade, pare e respire devagar: 4 segundos pra dentro, 6 pra fora.", tipo: "duracao", meta: 2, minutos: 3, xp: 15, icone: "wind", lembretes: ["15:00"]),
            ]
        }
        return Interpretacao(resumo: "Programa montado! Você recebe lembretes nos horários certos.",
                             programa: nome, tarefas: [], habitos: habitos)
    }
}
