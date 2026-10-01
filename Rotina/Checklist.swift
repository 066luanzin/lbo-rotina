import SwiftUI
import SwiftData

// MARK: - Modelos

/// Item da checklist de um tipo de bloco ("checagem" → "Saldo Meta Ads")
@Model
final class ItemChecklist {
    var id: UUID = UUID()
    /// Tipo do bloco, ex.: "checagem", "whatsapp clientes" (ver Checklist.chave)
    var chave: String = ""
    var texto: String = ""
    var ordem: Int = 0

    init(chave: String, texto: String, ordem: Int) {
        self.chave = chave
        self.texto = texto
        self.ordem = ordem
    }
}

/// Item marcado num dia específico (a checklist zera todo dia)
@Model
final class ItemMarcado {
    var itemID: UUID = UUID()
    var dia: Date = Date.now

    init(itemID: UUID, dia: Date) {
        self.itemID = itemID
        self.dia = Calendar.current.startOfDay(for: dia)
    }
}

@Model
final class Cliente {
    var id: UUID = UUID()
    var nome: String = ""
    /// Como a voz costuma escrever o nome, separado por vírgula
    var apelidos: String = ""
    var gmb: Bool = false
    var ativo: Bool = true
    var ordem: Int = 0

    init(nome: String, apelidos: String, gmb: Bool, ordem: Int) {
        self.nome = nome
        self.apelidos = apelidos
        self.gmb = gmb
        self.ordem = ordem
    }

    var info: ClienteInfo {
        ClienteInfo(nome: nome,
                    apelidos: apelidos.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                    gmb: gmb)
    }
}

/// Nota falada: "JA Climatização: pausei a campanha…" ou ideia de vídeo
@Model
final class Nota {
    var id: UUID = UUID()
    var texto: String = ""
    /// Nome do cliente ("" = geral)
    var cliente: String = ""
    /// nota | ideia
    var tipo: String = "nota"
    var data: Date = Date.now

    init(texto: String, cliente: String, tipo: String) {
        self.texto = texto
        self.cliente = cliente
        self.tipo = tipo
    }
}

// MARK: - Regras da checklist

enum Checklist {
    /// "Operação (piores)" e "Operação" usam a mesma checklist: "operacao"
    static func chave(_ titulo: String) -> String {
        var t = titulo.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
        t = t.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Checklist pronta pros blocos da rotina de gestor de tráfego
    static func modelo(para chave: String, clientes: [Cliente]) -> [String] {
        let ativos = clientes.filter(\.ativo).sorted { $0.ordem < $1.ordem }
        if chave.contains("checagem") {
            return ["Saldo Meta Ads", "Saldo Google Ads", "Campanhas rodando (nada pausado sem querer)", "Custo ou CPA fora do normal?"]
        }
        if chave.contains("whatsapp") { return ativos.map(\.nome) }
        if chave.contains("meu negocio") || chave.contains("gmb") { return ativos.filter(\.gmb).map(\.nome) }
        if chave.contains("operac") {
            return ["Termômetro / piores contas", "Ajustes de orçamento e lance", "Anotar o que foi feito por cliente"]
        }
        if chave.contains("criativo") { return ["Separar referências", "Produzir os criativos", "Subir e nomear no gerenciador"] }
        if chave.contains("video") || chave.contains("instagram") {
            return ["Escolher a ideia do banco", "Gravar", "Editar", "Agendar a postagem"]
        }
        if chave.contains("estudo") { return ["Estudar o conteúdo", "Anotar 1 aprendizado", "Aplicar em 1 conta"] }
        if chave.contains("fechamento") {
            return ["Check-in dos blocos e tarefas", "Anotar pendências", "Enviar o fechamento pro Claude", "Olhar a agenda de amanhã"]
        }
        if chave.contains("revisao") { return ["Ver o relatório da semana", "Termômetro de contas", "Planejar a próxima semana"] }
        return []
    }
}

enum Seeds {
    /// 01/10/2026: o padrão passou a ser só notificação. Mantém alarme só no "Enviar Plano pro Claude".
    @MainActor
    static func migrarAlarmes(_ ctx: ModelContext) {
        let chave = "migracaoAlarmePadrao1"
        guard !UserDefaults.standard.bool(forKey: chave) else { return }
        for t in (try? ctx.fetch(FetchDescriptor<Tarefa>())) ?? [] {
            let titulo = InterpretadorLocal.dobrar(t.titulo)
            t.tocarAlarme = titulo.contains("plano") && titulo.contains("claude")
        }
        try? ctx.save()
        UserDefaults.standard.set(true, forKey: chave)
    }

    /// Na primeira vez, cadastra os clientes da agência
    @MainActor
    static func clientes(_ ctx: ModelContext) {
        let existentes = (try? ctx.fetchCount(FetchDescriptor<Cliente>())) ?? 0
        guard existentes == 0 else { return }
        for (i, c) in InterpretadorLocal.clientesPadrao.enumerated() {
            ctx.insert(Cliente(nome: c.nome, apelidos: c.apelidos.joined(separator: ", "), gmb: c.gmb, ordem: i))
        }
        try? ctx.save()
    }
}

extension Acoes {
    /// Marca/desmarca o check-in de um bloco da agenda
    @MainActor
    static func checkinBloco(_ b: Bloco, ctx: ModelContext) {
        let id = b.id
        let existentes = (try? ctx.fetch(FetchDescriptor<BlocoFeito>(predicate: #Predicate { $0.blocoID == id }))) ?? []
        if existentes.isEmpty {
            ctx.insert(BlocoFeito(blocoID: b.id, titulo: b.titulo, inicio: b.inicio))
            Haptico.sucesso()
        } else {
            existentes.forEach { ctx.delete($0) }
        }
        try? ctx.save()
        Notificacoes.reagendar(ctx)
    }
}

// MARK: - Tela do bloco: check-in + checklist

struct BlocoDetalheView: View {
    let bloco: Bloco
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var fechar
    @Query(sort: \ItemChecklist.ordem) private var todosItens: [ItemChecklist]
    @Query private var marcados: [ItemMarcado]
    @Query private var feitos: [BlocoFeito]
    @Query private var clientes: [Cliente]
    @State private var novoItem = ""
    @State private var editando = false
    @FocusState private var focoNovo: Bool

    private var chave: String { Checklist.chave(bloco.titulo) }
    private var itens: [ItemChecklist] { todosItens.filter { $0.chave == chave } }
    private var dia: Date { Calendar.current.startOfDay(for: bloco.inicio) }
    private var futuro: Bool { dia > Calendar.current.startOfDay(for: .now) }
    private var feito: Bool { feitos.contains { $0.blocoID == bloco.id } }

    private func marcado(_ item: ItemChecklist) -> Bool {
        marcados.contains { $0.itemID == item.id && Calendar.current.isDate($0.dia, inSameDayAs: dia) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bloco.titulo).titulo(24)
                        Text(bloco.horario)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.texto2)
                    }
                    .listRowBackground(Color.clear)
                    Button {
                        Acoes.checkinBloco(bloco, ctx: ctx)
                    } label: {
                        Label(feito ? "Bloco feito ✅" : "Marcar bloco como feito",
                              systemImage: feito ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(EstiloPrincipal(cor: feito ? Color(hex: 0x2FBF71) : .verde))
                    .disabled(futuro && !feito)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                Section {
                    ForEach(itens) { item in
                        let ok = marcado(item)
                        HStack(spacing: 12) {
                            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(ok ? Color.verde : Color.white.opacity(futuro ? 0.15 : 0.35))
                            Text(item.texto)
                                .strikethrough(ok)
                                .foregroundStyle(ok ? Color.texto2 : .white)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { alternar(item) }
                        .listRowBackground(Color.cartao)
                    }
                    .onDelete { apagar($0) }
                    .onMove { mover($0, $1) }

                    HStack {
                        TextField("Adicionar item…", text: $novoItem)
                            .focused($focoNovo)
                            .submitLabel(.done)
                            .onSubmit(adicionar)
                        if !novoItem.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Adicionar", action: adicionar).foregroundStyle(Color.verde)
                        }
                    }
                    .listRowBackground(Color.cartao)
                } header: {
                    let total = itens.count
                    let ok = itens.filter { marcado($0) }.count
                    Text(total == 0 ? "Checklist" : "Checklist · \(ok)/\(total)")
                } footer: {
                    Text(futuro
                         ? "Dia futuro: dá pra montar a lista, mas marcar só no dia."
                         : "A checklist zera todo dia e vale pra todos os blocos com esse nome. Marcou tudo, o bloco ganha check-in sozinho. Arraste pro lado pra apagar um item.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fundo.ignoresSafeArea())
            .environment(\.editMode, .constant(editando ? .active : .inactive))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editando ? "Pronto" : "Reordenar") { withAnimation { editando.toggle() } }
                        .disabled(itens.count < 2)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fechar") { fechar() }.bold() }
            }
            .onAppear(perform: criarModeloSePrecisar)
        }
        .presentationDetents([.medium, .large])
    }

    private func criarModeloSePrecisar() {
        guard itens.isEmpty else { return }
        let modelo = Checklist.modelo(para: chave, clientes: clientes)
        for (i, texto) in modelo.enumerated() {
            ctx.insert(ItemChecklist(chave: chave, texto: texto, ordem: i))
        }
        try? ctx.save()
    }

    private func alternar(_ item: ItemChecklist) {
        guard !futuro else { return }
        let estavaMarcado = marcado(item)
        // Os outros itens, olhando antes do toque (a lista da tela só atualiza depois)
        let outrosOk = itens.filter { $0.id != item.id }.allSatisfy { marcado($0) }
        if estavaMarcado {
            marcados.filter { $0.itemID == item.id && Calendar.current.isDate($0.dia, inSameDayAs: dia) }
                .forEach { ctx.delete($0) }
        } else {
            ctx.insert(ItemMarcado(itemID: item.id, dia: dia))
            Haptico.leve()
        }
        try? ctx.save()
        // Marcou o último item: o bloco ganha check-in sozinho
        if !estavaMarcado && outrosOk && !feito {
            Acoes.checkinBloco(bloco, ctx: ctx)
        }
    }

    private func adicionar() {
        let texto = novoItem.trimmingCharacters(in: .whitespaces)
        guard !texto.isEmpty else { return }
        ctx.insert(ItemChecklist(chave: chave, texto: texto, ordem: (itens.map(\.ordem).max() ?? -1) + 1))
        try? ctx.save()
        novoItem = ""
        focoNovo = true
    }

    private func apagar(_ offsets: IndexSet) {
        for i in offsets { ctx.delete(itens[i]) }
        try? ctx.save()
    }

    private func mover(_ origem: IndexSet, _ destino: Int) {
        var lista = itens
        lista.move(fromOffsets: origem, toOffset: destino)
        for (i, item) in lista.enumerated() { item.ordem = i }
        try? ctx.save()
    }
}
