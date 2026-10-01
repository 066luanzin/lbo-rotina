import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Cópia de tudo do app num arquivo .json (salvar no iCloud Drive e restaurar quando precisar)
struct BackupDados: Codable {
    struct TarefaB: Codable {
        var id: UUID; var titulo: String; var quando: Date?; var temHora: Bool; var repeticaoRaw: String
        var diasRaw: String; var concluidaEm: Date?; var criadaEm: Date; var cliente: String
        var tocarAlarme: Bool?
    }
    struct HabitoB: Codable {
        var id: UUID; var titulo: String; var descricao: String; var tipoRaw: String; var meta: Int; var minutos: Int
        var xp: Int; var icone: String; var programa: String; var lembretes: [String]; var inicioContagem: Date
        var recordeSegundos: Double; var criadoEm: Date; var ordem: Int
    }
    struct RegistroB: Codable { var id: UUID; var habitoID: UUID; var data: Date; var deslize: Bool; var xp: Int }
    struct FeitoB: Codable { var blocoID: String; var titulo: String; var inicio: Date; var feitoEm: Date }
    struct ItemB: Codable { var id: UUID; var chave: String; var texto: String; var ordem: Int }
    struct MarcadoB: Codable { var itemID: UUID; var dia: Date }
    struct ClienteB: Codable { var id: UUID; var nome: String; var apelidos: String; var gmb: Bool; var ativo: Bool; var ordem: Int }
    struct NotaB: Codable { var id: UUID; var texto: String; var cliente: String; var tipo: String; var data: Date }

    var versao = 1
    var criadoEm = Date.now
    var tarefas: [TarefaB] = []
    var habitos: [HabitoB] = []
    var registros: [RegistroB] = []
    var feitos: [FeitoB] = []
    var itens: [ItemB] = []
    var marcados: [MarcadoB] = []
    var clientes: [ClienteB] = []
    var notas: [NotaB] = []
    var ajustes: [String: String] = [:]
}

enum Backup {
    /// Ajustes (nome, avisos, calendários…) que também vão no backup
    private static let chavesTexto = ["nome", "blocosComAlarme", "horasCheckin", "modeloIA"]
    private static let chavesBool = ["avisoBlocos", "perguntarFimBloco", "lembreteCheckin", "alarmeBlocos", "alarmeTarefas"]
    private static let chavesInt = ["minutosAntesBloco", "metaSemanal"]

    @MainActor
    static func gerar(_ ctx: ModelContext) -> Data? {
        var b = BackupDados()
        b.tarefas = ((try? ctx.fetch(FetchDescriptor<Tarefa>())) ?? []).map {
            .init(id: $0.id, titulo: $0.titulo, quando: $0.quando, temHora: $0.temHora, repeticaoRaw: $0.repeticaoRaw,
                  diasRaw: $0.diasRaw, concluidaEm: $0.concluidaEm, criadaEm: $0.criadaEm, cliente: $0.cliente,
                  tocarAlarme: $0.tocarAlarme)
        }
        b.habitos = ((try? ctx.fetch(FetchDescriptor<Habito>())) ?? []).map {
            .init(id: $0.id, titulo: $0.titulo, descricao: $0.descricao, tipoRaw: $0.tipoRaw, meta: $0.meta, minutos: $0.minutos,
                  xp: $0.xp, icone: $0.icone, programa: $0.programa, lembretes: $0.lembretes, inicioContagem: $0.inicioContagem,
                  recordeSegundos: $0.recordeSegundos, criadoEm: $0.criadoEm, ordem: $0.ordem)
        }
        b.registros = ((try? ctx.fetch(FetchDescriptor<Registro>())) ?? []).map {
            .init(id: $0.id, habitoID: $0.habitoID, data: $0.data, deslize: $0.deslize, xp: $0.xp)
        }
        b.feitos = ((try? ctx.fetch(FetchDescriptor<BlocoFeito>())) ?? []).map {
            .init(blocoID: $0.blocoID, titulo: $0.titulo, inicio: $0.inicio, feitoEm: $0.feitoEm)
        }
        b.itens = ((try? ctx.fetch(FetchDescriptor<ItemChecklist>())) ?? []).map {
            .init(id: $0.id, chave: $0.chave, texto: $0.texto, ordem: $0.ordem)
        }
        b.marcados = ((try? ctx.fetch(FetchDescriptor<ItemMarcado>())) ?? []).map { .init(itemID: $0.itemID, dia: $0.dia) }
        b.clientes = ((try? ctx.fetch(FetchDescriptor<Cliente>())) ?? []).map {
            .init(id: $0.id, nome: $0.nome, apelidos: $0.apelidos, gmb: $0.gmb, ativo: $0.ativo, ordem: $0.ordem)
        }
        b.notas = ((try? ctx.fetch(FetchDescriptor<Nota>())) ?? []).map {
            .init(id: $0.id, texto: $0.texto, cliente: $0.cliente, tipo: $0.tipo, data: $0.data)
        }
        let d = UserDefaults.standard
        for k in chavesTexto { if let v = d.string(forKey: k) { b.ajustes[k] = v } }
        for k in chavesBool where d.object(forKey: k) != nil { b.ajustes[k] = d.bool(forKey: k) ? "1" : "0" }
        for k in chavesInt where d.object(forKey: k) != nil { b.ajustes[k] = String(d.integer(forKey: k)) }
        if let cals = d.array(forKey: "calendariosAgenda") as? [String] { b.ajustes["calendariosAgenda"] = cals.joined(separator: "\n") }

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(b)
    }

    /// Apaga o que está no app e coloca o conteúdo do backup. Devolve um resumo ("12 tarefas, 30 notas…")
    @MainActor
    static func restaurar(_ dados: Data, ctx: ModelContext) throws -> String {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let b = try dec.decode(BackupDados.self, from: dados)

        try ctx.delete(model: Tarefa.self)
        try ctx.delete(model: Habito.self)
        try ctx.delete(model: Registro.self)
        try ctx.delete(model: BlocoFeito.self)
        try ctx.delete(model: ItemChecklist.self)
        try ctx.delete(model: ItemMarcado.self)
        try ctx.delete(model: Cliente.self)
        try ctx.delete(model: Nota.self)

        for t in b.tarefas {
            let n = Tarefa(titulo: t.titulo, quando: t.quando, temHora: t.temHora)
            n.id = t.id; n.repeticaoRaw = t.repeticaoRaw; n.diasRaw = t.diasRaw
            n.concluidaEm = t.concluidaEm; n.criadaEm = t.criadaEm; n.cliente = t.cliente
            n.tocarAlarme = t.tocarAlarme ?? true
            ctx.insert(n)
        }
        for h in b.habitos {
            let n = Habito(titulo: h.titulo, descricao: h.descricao, tipo: TipoHabito(rawValue: h.tipoRaw) ?? .contagem,
                           meta: h.meta, minutos: h.minutos, xp: h.xp, icone: h.icone, programa: h.programa, lembretes: h.lembretes)
            n.id = h.id; n.inicioContagem = h.inicioContagem; n.recordeSegundos = h.recordeSegundos
            n.criadoEm = h.criadoEm; n.ordem = h.ordem
            ctx.insert(n)
        }
        for r in b.registros {
            let n = Registro(habitoID: r.habitoID, data: r.data, deslize: r.deslize, xp: r.xp)
            n.id = r.id
            ctx.insert(n)
        }
        for f in b.feitos {
            let n = BlocoFeito(blocoID: f.blocoID, titulo: f.titulo, inicio: f.inicio)
            n.feitoEm = f.feitoEm
            ctx.insert(n)
        }
        for i in b.itens {
            let n = ItemChecklist(chave: i.chave, texto: i.texto, ordem: i.ordem)
            n.id = i.id
            ctx.insert(n)
        }
        for m in b.marcados { ctx.insert(ItemMarcado(itemID: m.itemID, dia: m.dia)) }
        for c in b.clientes {
            let n = Cliente(nome: c.nome, apelidos: c.apelidos, gmb: c.gmb, ordem: c.ordem)
            n.id = c.id; n.ativo = c.ativo
            ctx.insert(n)
        }
        for o in b.notas {
            let n = Nota(texto: o.texto, cliente: o.cliente, tipo: o.tipo)
            n.id = o.id; n.data = o.data
            ctx.insert(n)
        }
        try ctx.save()

        let d = UserDefaults.standard
        for (k, v) in b.ajustes {
            if chavesBool.contains(k) { d.set(v == "1", forKey: k) }
            else if chavesInt.contains(k) { d.set(Int(v) ?? 0, forKey: k) }
            else if k == "calendariosAgenda" { d.set(v.split(separator: "\n").map(String.init), forKey: k) }
            else { d.set(v, forKey: k) }
        }
        Agenda.shared.escolhidos = (d.array(forKey: "calendariosAgenda") as? [String]).map { Set($0) }
        Agenda.shared.recarregar()
        Notificacoes.reagendar(ctx)
        return "\(b.tarefas.count) tarefas, \(b.habitos.count) hábitos, \(b.notas.count) notas e \(b.clientes.count) clientes"
    }

    // MARK: Backup automático (uma vez por dia, fica em Arquivos > No meu iPhone > LBO Rotina)

    static var pasta: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Backups", isDirectory: true)
    }

    static var ultimo: Date? { UserDefaults.standard.object(forKey: "ultimoBackup") as? Date }

    static func nomeArquivo(_ data: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "LBO-Rotina-backup-\(f.string(from: data)).json"
    }

    @MainActor
    static func automatico(_ ctx: ModelContext) {
        if let u = ultimo, Calendar.current.isDateInToday(u) { return }
        guard let dados = gerar(ctx) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: pasta, withIntermediateDirectories: true)
        try? dados.write(to: pasta.appendingPathComponent(nomeArquivo()), options: .atomic)
        UserDefaults.standard.set(Date.now, forKey: "ultimoBackup")
        // Guarda só os 7 mais recentes
        let arquivos = ((try? fm.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for velho in arquivos.dropFirst(7) { try? fm.removeItem(at: velho) }
    }
}

/// Arquivo pro "Salvar em Arquivos" (iCloud Drive)
struct ArquivoBackup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var dados: Data

    init(dados: Data) { self.dados = dados }

    init(configuration: ReadConfiguration) throws {
        dados = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: dados)
    }
}
