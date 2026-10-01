import Foundation
import SwiftData

/// Ponte com o Claude Code pelo iCloud Drive (pasta "LBO Sync"):
/// - app-estado.json / hoje.md: o app escreve o dia (check-ins, tarefas, notas) pro Claude ler no PC
/// - do-claude.json: o Claude escreve pedidos (tarefas, notas, check-ins) que o app aplica ao abrir
enum Sincronizacao {
    private static let chaveBookmark = "pastaSyncBookmark"
    private static let chaveAplicados = "syncAplicados"
    static var ultima: Date? { UserDefaults.standard.object(forKey: "ultimaSync") as? Date }
    static var configurada: Bool { UserDefaults.standard.data(forKey: chaveBookmark) != nil }
    static var nomePasta: String { UserDefaults.standard.string(forKey: "pastaSyncNome") ?? "" }

    // MARK: Pasta escolhida (fica salva entre aberturas do app)

    static func salvarPasta(_ url: URL) -> Bool {
        let acesso = url.startAccessingSecurityScopedResource()
        defer { if acesso { url.stopAccessingSecurityScopedResource() } }
        guard let dados = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        UserDefaults.standard.set(dados, forKey: chaveBookmark)
        UserDefaults.standard.set(url.lastPathComponent, forKey: "pastaSyncNome")
        return true
    }

    static func esquecerPasta() {
        UserDefaults.standard.removeObject(forKey: chaveBookmark)
        UserDefaults.standard.removeObject(forKey: "pastaSyncNome")
    }

    /// Abre a pasta com permissão e roda o bloco
    private static func comPasta<T>(_ bloco: (URL) throws -> T) -> T? {
        guard let dados = UserDefaults.standard.data(forKey: chaveBookmark) else { return nil }
        var velho = false
        guard let url = try? URL(resolvingBookmarkData: dados, options: [], relativeTo: nil, bookmarkDataIsStale: &velho) else { return nil }
        let acesso = url.startAccessingSecurityScopedResource()
        defer { if acesso { url.stopAccessingSecurityScopedResource() } }
        if velho, let novo = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(novo, forKey: chaveBookmark)
        }
        return try? bloco(url)
    }

    private static func ler(_ arquivo: URL) -> Data? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: arquivo)
        var dados: Data?
        var erro: NSError?
        NSFileCoordinator().coordinate(readingItemAt: arquivo, options: [], error: &erro) { url in
            dados = try? Data(contentsOf: url)
        }
        return dados
    }

    private static func escrever(_ dados: Data, em arquivo: URL) {
        var erro: NSError?
        NSFileCoordinator().coordinate(writingItemAt: arquivo, options: .forReplacing, error: &erro) { url in
            try? dados.write(to: url, options: .atomic)
        }
    }

    // MARK: Sincronizar (ao abrir e ao sair do app)

    /// Aplica os pedidos do Claude e escreve o estado atual. Devolve quantos pedidos foram aplicados.
    @MainActor
    @discardableResult
    static func sincronizar(_ ctx: ModelContext) -> Int {
        guard configurada else { return 0 }
        let aplicados = importar(ctx)
        exportar(ctx)
        UserDefaults.standard.set(Date.now, forKey: "ultimaSync")
        return aplicados
    }

    // MARK: Claude → app

    struct Pedidos: Decodable {
        struct Pedido: Decodable {
            var id: String
            var tipo: String            // tarefa | nota | checkin
            var fala: String?           // "checar saldo da Climax amanhã às 9" (o app interpreta)
            var titulo: String?
            var data: String?           // AAAA-MM-DD
            var hora: String?           // HH:mm
            var repeticao: String?      // nunca | diario | semanal | dias:2,3,4,5,6
            var cliente: String?
            var texto: String?          // nota
            var tipoNota: String?       // nota | ideia
            var bloco: String?          // checkin: parte do nome do bloco
        }
        var pedidos: [Pedido]
    }

    @MainActor
    private static func importar(_ ctx: ModelContext) -> Int {
        let resultado: Int? = comPasta { pasta in
            let arquivo = pasta.appendingPathComponent("do-claude.json")
            guard let dados = ler(arquivo),
                  let lista = try? JSONDecoder().decode(Pedidos.self, from: dados) else { return 0 }
            var feitos = Set(UserDefaults.standard.stringArray(forKey: chaveAplicados) ?? [])
            var n = 0
            for p in lista.pedidos where !feitos.contains(p.id) {
                aplicar(p, ctx: ctx)
                feitos.insert(p.id)
                n += 1
            }
            if n > 0 {
                try? ctx.save()
                UserDefaults.standard.set(Array(feitos), forKey: chaveAplicados)
                Notificacoes.reagendar(ctx)
            }
            return n
        }
        return resultado ?? 0
    }

    @MainActor
    private static func aplicar(_ p: Pedidos.Pedido, ctx: ModelContext) {
        let cliente = p.cliente ?? ""
        switch p.tipo {
        case "tarefa":
            let r: Interpretacao
            if let fala = p.fala, !fala.isEmpty {
                r = InterpretadorLocal.interpretar(fala, modo: .tarefa)
            } else {
                r = Interpretacao(resumo: "", programa: "",
                                  tarefas: [.init(titulo: p.titulo ?? "Tarefa do Claude", data: p.data ?? "",
                                                  hora: p.hora ?? "", repeticao: p.repeticao ?? "nunca")],
                                  habitos: [])
            }
            let salvo = Aplicador.salvar(r, ctx: ctx)
            if !cliente.isEmpty { salvo.tarefas.forEach { $0.cliente = cliente } }
        case "nota":
            let texto = p.texto ?? p.fala ?? ""
            guard !texto.isEmpty else { return }
            if cliente.isEmpty {
                let clientes = ((try? ctx.fetch(FetchDescriptor<Cliente>())) ?? []).filter(\.ativo).map(\.info)
                let n = InterpretadorLocal.nota(texto, clientes: clientes)
                ctx.insert(Nota(texto: n.texto, cliente: n.cliente, tipo: p.tipoNota ?? n.tipo))
            } else {
                ctx.insert(Nota(texto: texto, cliente: cliente, tipo: p.tipoNota ?? "nota"))
            }
        case "checkin":
            guard let nome = p.bloco?.lowercased(), !nome.isEmpty else { return }
            let iso = DateFormatter()
            iso.locale = Locale(identifier: "en_US_POSIX")
            iso.dateFormat = "yyyy-MM-dd"
            let dia = p.data.flatMap { iso.date(from: $0) } ?? .now
            let feitos = Set(((try? ctx.fetch(FetchDescriptor<BlocoFeito>())) ?? []).map(\.blocoID))
            for b in Agenda.shared.blocos(do: dia) where b.titulo.lowercased().contains(nome) && !feitos.contains(b.id) {
                ctx.insert(BlocoFeito(blocoID: b.id, titulo: b.titulo, inicio: b.inicio))
            }
        default:
            break
        }
    }

    // MARK: App → Claude

    struct Estado: Encodable {
        struct BlocoE: Encodable { var titulo: String; var inicio: String; var fim: String; var feito: Bool; var checklist: String? }
        struct TarefaE: Encodable { var titulo: String; var hora: String?; var feita: Bool; var cliente: String?; var repeticao: String }
        struct DiaE: Encodable { var data: String; var blocos: [BlocoE]; var tarefas: [TarefaE] }
        struct PendenteE: Encodable { var titulo: String; var quando: String?; var cliente: String?; var repeticao: String }
        struct NotaE: Encodable { var data: String; var cliente: String?; var tipo: String; var texto: String }
        struct MetaE: Encodable { var metaPct: Int; var semanaPct: Int; var blocosFeitos: Int; var blocosTotal: Int; var semanasSeguidas: Int }

        var geradoEm: String
        var dias: [DiaE]
        var pendentes: [PendenteE]
        var notas: [NotaE]
        var meta: MetaE
        var pedidosAplicados: [String]
    }

    @MainActor
    private static func exportar(_ ctx: ModelContext) {
        let cal = Calendar.current
        let isoDia = DateFormatter()
        isoDia.locale = Locale(identifier: "en_US_POSIX")
        isoDia.dateFormat = "yyyy-MM-dd"
        let isoHora = DateFormatter()
        isoHora.locale = Locale(identifier: "en_US_POSIX")
        isoHora.dateFormat = "yyyy-MM-dd HH:mm"
        let hm = DateFormatter()
        hm.locale = Locale(identifier: "en_US_POSIX")
        hm.dateFormat = "HH:mm"

        let tarefas = (try? ctx.fetch(FetchDescriptor<Tarefa>())) ?? []
        let feitos = Set(((try? ctx.fetch(FetchDescriptor<BlocoFeito>())) ?? []).map(\.blocoID))
        let itens = (try? ctx.fetch(FetchDescriptor<ItemChecklist>())) ?? []
        let marcados = (try? ctx.fetch(FetchDescriptor<ItemMarcado>())) ?? []
        let notas = (try? ctx.fetch(FetchDescriptor<Nota>())) ?? []
        let placar = Placar(habitos: [], registros: [], tarefas: tarefas)
        let hoje = cal.startOfDay(for: .now)

        // Últimos 7 dias + hoje + amanhã
        var dias: [Estado.DiaE] = []
        for n in -7...1 {
            guard let d = cal.date(byAdding: .day, value: n, to: hoje) else { continue }
            let blocos = Agenda.shared.blocos(do: d).map { b -> Estado.BlocoE in
                let chave = Checklist.chave(b.titulo)
                let its = itens.filter { $0.chave == chave }
                let ok = its.filter { i in marcados.contains { $0.itemID == i.id && cal.isDate($0.dia, inSameDayAs: d) } }.count
                return .init(titulo: b.titulo, inicio: hm.string(from: b.inicio), fim: hm.string(from: b.fim),
                             feito: feitos.contains(b.id), checklist: its.isEmpty ? nil : "\(ok)/\(its.count)")
            }
            let ts = placar.tarefas(em: d).map {
                Estado.TarefaE(titulo: $0.titulo, hora: $0.horaTexto, feita: $0.feita(em: d),
                               cliente: $0.cliente.isEmpty ? nil : $0.cliente,
                               repeticao: $0.repeticao == .dias ? "dias:\($0.diasRaw)" : $0.repeticaoRaw)
            }
            if !blocos.isEmpty || !ts.isEmpty {
                dias.append(.init(data: isoDia.string(from: d), blocos: blocos, tarefas: ts))
            }
        }

        let pendentes = tarefas.filter { $0.concluidaEm == nil && $0.repeticao == .nunca }
            .sorted { ($0.quando ?? .distantFuture) < ($1.quando ?? .distantFuture) }
            .map { Estado.PendenteE(titulo: $0.titulo, quando: $0.quando.map { isoHora.string(from: $0) },
                                    cliente: $0.cliente.isEmpty ? nil : $0.cliente, repeticao: $0.repeticaoRaw) }

        let limite = cal.date(byAdding: .day, value: -30, to: hoje) ?? hoje
        let notasE = notas.filter { $0.data >= limite }.sorted { $0.data > $1.data }.map {
            Estado.NotaE(data: isoHora.string(from: $0.data), cliente: $0.cliente.isEmpty ? nil : $0.cliente,
                         tipo: $0.tipo, texto: $0.texto)
        }

        let semana = MetaSemanal.semanaAtual(feitos: feitos)
        let meta = Estado.MetaE(metaPct: MetaSemanal.meta,
                                semanaPct: semana.total == 0 ? 0 : Int((Double(semana.feitos) / Double(semana.total) * 100).rounded()),
                                blocosFeitos: semana.feitos, blocosTotal: semana.total,
                                semanasSeguidas: MetaSemanal.historico(feitos: feitos).sequencia)

        let estado = Estado(geradoEm: isoHora.string(from: .now), dias: dias, pendentes: pendentes, notas: notasE,
                            meta: meta, pedidosAplicados: UserDefaults.standard.stringArray(forKey: chaveAplicados) ?? [])
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let json = try? enc.encode(estado) else { return }

        // Versão pra leitura rápida (o mesmo texto do Fechamento do dia)
        var md = ["# LBO Rotina — \(isoHora.string(from: .now))", ""]
        if let d = dias.first(where: { $0.data == isoDia.string(from: hoje) }) {
            md.append("## Hoje")
            d.blocos.forEach { md.append("- [\($0.feito ? "x" : " ")] \($0.inicio) \($0.titulo)" + ($0.checklist.map { " (checklist \($0))" } ?? "")) }
            d.tarefas.forEach { md.append("- [\($0.feita ? "x" : " ")] \($0.hora.map { "\($0) " } ?? "")\($0.titulo)" + ($0.cliente.map { " — \($0)" } ?? "")) }
            md.append("")
        }
        let notasHoje = notasE.filter { $0.data.hasPrefix(isoDia.string(from: hoje)) }
        if !notasHoje.isEmpty {
            md.append("## Notas de hoje")
            notasHoje.forEach { md.append("- \($0.tipo == "ideia" ? "💡 Ideia" : ($0.cliente ?? "Geral")): \($0.texto)") }
            md.append("")
        }
        md.append("Meta da semana: \(meta.semanaPct)% de \(meta.metaPct)% (\(meta.blocosFeitos)/\(meta.blocosTotal) blocos)")

        _ = comPasta { pasta in
            escrever(json, em: pasta.appendingPathComponent("app-estado.json"))
            escrever(Data(md.joined(separator: "\n").utf8), em: pasta.appendingPathComponent("hoje.md"))
        }
    }
}
