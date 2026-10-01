import SwiftUI
import SwiftData

// MARK: - Aba Notas

struct NotasView: View {
    @Environment(AppState.self) private var estado
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Nota.data, order: .reverse) private var notas: [Nota]
    @State private var filtro = "Todas"
    @State private var fechamento = false
    @State private var relatorio = false

    private var filtradas: [Nota] {
        if filtro == "Todas" { return notas }
        if filtro == "Ideias" { return notas.filter { $0.tipo == "ideia" } }
        if filtro == "Gerais" { return notas.filter { $0.cliente.isEmpty && $0.tipo == "nota" } }
        return notas.filter { $0.cliente == filtro }
    }

    private var opcoes: [String] {
        ["Todas", "Ideias", "Gerais"] + Array(Set(notas.map(\.cliente).filter { !$0.isEmpty })).sorted()
    }

    struct GrupoNotas: Identifiable {
        let dia: Date
        let notas: [Nota]
        var id: Date { dia }
    }

    private var dias: [GrupoNotas] {
        Dictionary(grouping: filtradas) { Calendar.current.startOfDay(for: $0.data) }
            .map { GrupoNotas(dia: $0.key, notas: $0.value.sorted { $0.data > $1.data }) }
            .sorted { $0.dia > $1.dia }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            atalho("Fechamento do dia", "doc.text.fill") { fechamento = true }
                            atalho("Relatório da semana", "chart.bar.fill") { relatorio = true }
                            NavigationLink { ClientesView() } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: "person.2.fill").font(.system(size: 20)).foregroundStyle(Color.verde)
                                    Text("Clientes")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                .cartao(14)
                            }
                            .buttonStyle(.plain)
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(opcoes, id: \.self) { o in
                                    Text(o)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(filtro == o ? Color.fundo : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(filtro == o ? Color.verde : Color.cartao2, in: Capsule())
                                        .onTapGesture { filtro = o }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)

                        if filtradas.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "note.text").font(.system(size: 32)).foregroundStyle(Color.verde)
                                Text("Nenhuma nota ainda").titulo(18)
                                Text("Toque em \"Nova nota\" e fale, por exemplo:\n\"JA Climatização: pausei a campanha de pesquisa\"\nou \"ideia de vídeo: erro de orçamento baixo em PMax\"")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(Color.texto2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }

                        ForEach(dias) { grupo in
                            Text(rotulo(grupo.dia))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(Color.texto2)
                                .padding(.top, 4)
                            ForEach(grupo.notas) { n in
                                LinhaNota(nota: n)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)

                Button {
                    Haptico.leve()
                    estado.captura = .nota
                } label: {
                    Label("Nova nota", systemImage: "mic.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.fundo)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 15)
                        .background(Color.verde, in: Capsule())
                        .shadow(color: Color.verde.opacity(0.45), radius: 16, y: 4)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 16)
            }
            .background(Color.fundo.ignoresSafeArea())
            .navigationTitle("Notas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ClientesView() } label: { Image(systemName: "person.2.fill") }
                }
            }
            .sheet(isPresented: $fechamento) { FechamentoView(dia: .now) }
            .sheet(isPresented: $relatorio) { RelatorioView() }
        }
    }

    private func atalho(_ titulo: String, _ icone: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icone).font(.system(size: 20)).foregroundStyle(Color.verde)
                Text(titulo)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .cartao(14)
        }
        .buttonStyle(.plain)
    }

    private func rotulo(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "HOJE" }
        if Calendar.current.isDateInYesterday(d) { return "ONTEM" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }
}

struct LinhaNota: View {
    let nota: Nota
    @Environment(\.modelContext) private var ctx

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: nota.tipo == "ideia" ? "lightbulb.fill" : (nota.cliente.isEmpty ? "note.text" : "person.fill"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(nota.tipo == "ideia" ? Color.orange : Color.verde)
                .frame(width: 32, height: 32)
                .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(nota.tipo == "ideia" ? "Ideia de vídeo" : (nota.cliente.isEmpty ? "Geral" : nota.cliente))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(nota.tipo == "ideia" ? Color.orange : Color.verde)
                    Text(nota.data.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.texto2)
                }
                Text(nota.texto)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button("Copiar", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = nota.cliente.isEmpty ? nota.texto : "\(nota.cliente): \(nota.texto)"
            }
            Button("Apagar", systemImage: "trash", role: .destructive) {
                ctx.delete(nota)
                try? ctx.save()
            }
        }
    }
}

// MARK: - Clientes (nomes e apelidos que a voz reconhece)

struct ClientesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Cliente.ordem) private var clientes: [Cliente]

    var body: some View {
        List {
            Section {
                ForEach(clientes) { c in
                    NavigationLink {
                        ClienteDetalheView(cliente: c)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(c.nome).foregroundStyle(c.ativo ? .white : Color.texto2)
                                if c.gmb {
                                    Text("GMB")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.fundo)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.verde, in: Capsule())
                                }
                            }
                            if !c.apelidos.isEmpty {
                                Text(c.apelidos).font(.system(size: 12)).foregroundStyle(Color.texto2)
                            }
                        }
                    }
                }
                .onDelete { idx in
                    idx.forEach { ctx.delete(clientes[$0]) }
                    try? ctx.save()
                }
            } footer: {
                Text("Os apelidos são como a voz costuma escrever o nome (ex.: \"jl\", \"jota ele\"). Clientes com GMB entram na checklist do Google Meu Negócio, e todos os ativos entram na do WhatsApp.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.fundo.ignoresSafeArea())
        .navigationTitle("Clientes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ctx.insert(Cliente(nome: "Novo cliente", apelidos: "", gmb: false,
                                       ordem: (clientes.map(\.ordem).max() ?? -1) + 1))
                    try? ctx.save()
                } label: { Image(systemName: "plus") }
            }
        }
    }
}

struct ClienteEditView: View {
    @Bindable var cliente: Cliente
    @Environment(\.modelContext) private var ctx

    var body: some View {
        Form {
            Section("Nome") { TextField("Nome", text: $cliente.nome) }
            Section {
                TextField("jl, jota ele", text: $cliente.apelidos)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Apelidos (separados por vírgula)")
            }
            Section {
                Toggle("Tem Google Meu Negócio", isOn: $cliente.gmb).tint(Color.verde)
                Toggle("Ativo", isOn: $cliente.ativo).tint(Color.verde)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.fundo.ignoresSafeArea())
        .navigationTitle(cliente.nome)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? ctx.save() }
    }
}

// MARK: - Fechamento do dia (texto pronto pro Claude)

struct FechamentoView: View {
    let dia: Date
    @Environment(\.dismiss) private var fechar
    @Query private var tarefas: [Tarefa]
    @Query private var feitos: [BlocoFeito]
    @Query(sort: \Nota.data) private var notas: [Nota]
    @State private var copiado = false

    private var texto: String {
        let cal = Calendar.current
        var linhas: [String] = []
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEE, dd/MM"
        linhas.append("Fechamento do dia — \(f.string(from: dia))")

        let blocos = Agenda.shared.blocos(do: dia)
        if !blocos.isEmpty {
            let ids = Set(feitos.map(\.blocoID))
            let ok = blocos.filter { ids.contains($0.id) }
            let nao = blocos.filter { !ids.contains($0.id) }
            linhas.append("")
            linhas.append("Agenda: \(ok.count) de \(blocos.count) blocos feitos")
            if !ok.isEmpty { linhas.append("✅ " + ok.map(\.titulo).joined(separator: " · ")) }
            if !nao.isEmpty { linhas.append("⏳ Não feitos: " + nao.map(\.titulo).joined(separator: ", ")) }
        }

        let doDia = Placar(habitos: [], registros: [], tarefas: tarefas).tarefas(em: dia)
        if !doDia.isEmpty {
            let ok = doDia.filter { $0.feita(em: dia) }
            let nao = doDia.filter { !$0.feita(em: dia) }
            linhas.append("")
            linhas.append("Tarefas: \(ok.count) de \(doDia.count)")
            ok.forEach { linhas.append("✅ \($0.titulo)") }
            nao.forEach { linhas.append("⏳ \($0.titulo)") }
        }

        let deHoje = notas.filter { cal.isDate($0.data, inSameDayAs: dia) }
        let porCliente = deHoje.filter { $0.tipo == "nota" && !$0.cliente.isEmpty }
        if !porCliente.isEmpty {
            linhas.append("")
            linhas.append("Notas por cliente:")
            for nome in Array(Set(porCliente.map(\.cliente))).sorted() {
                for n in porCliente where n.cliente == nome { linhas.append("• \(nome): \(n.texto)") }
            }
        }
        let gerais = deHoje.filter { $0.tipo == "nota" && $0.cliente.isEmpty }
        if !gerais.isEmpty {
            linhas.append("")
            linhas.append("Notas gerais:")
            gerais.forEach { linhas.append("• \($0.texto)") }
        }
        let ideias = deHoje.filter { $0.tipo == "ideia" }
        if !ideias.isEmpty {
            linhas.append("")
            linhas.append("Ideias de vídeo:")
            ideias.forEach { linhas.append("• \($0.texto)") }
        }
        return linhas.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Manda isso pro Claude: ele usa no fechamento do dia e atualiza o histórico e o relatório do sócio.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.texto2)
                    Text(texto)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cartao(14)
                    ShareLink(item: texto) {
                        Label("Enviar pro Claude", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(EstiloPrincipal())
                    Button {
                        UIPasteboard.general.string = texto
                        Haptico.sucesso()
                        copiado = true
                    } label: {
                        Label(copiado ? "Copiado!" : "Copiar texto", systemImage: copiado ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(EstiloSecundario(cor: .verde))
                }
                .padding(18)
            }
            .background(Color.fundo.ignoresSafeArea())
            .navigationTitle("Fechamento do dia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fechar") { fechar() }.bold() }
            }
        }
    }
}
