import SwiftUI
import SwiftData

struct EditarHabitoView: View {
    @Bindable var habito: Habito
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var fechar
    @State private var lembretes: [Date] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Hábito") {
                    TextField("Nome", text: $habito.titulo)
                    TextField("Como fazer", text: $habito.descricao, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Tipo", selection: Binding(get: { habito.tipo }, set: { habito.tipo = $0 })) {
                        ForEach(TipoHabito.allCases, id: \.self) { Text($0.nome).tag($0) }
                    }
                }
                Section("Meta") {
                    if habito.tipo != .abstinencia {
                        Stepper("\(habito.meta)x por dia", value: $habito.meta, in: 1...20)
                    }
                    if habito.tipo == .duracao {
                        Stepper("\(habito.minutos) min de cronômetro", value: $habito.minutos, in: 1...120)
                    }
                    Stepper("\(habito.xp) XP por registro", value: $habito.xp, in: 1...100, step: 5)
                }
                Section("Ícone") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(IA.icones, id: \.self) { s in
                                IconeHabito(simbolo: s, cor: s == habito.icone ? .verde : .cartao2, tamanho: 38)
                                    .onTapGesture { habito.icone = s }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
                Section {
                    ForEach(lembretes.indices, id: \.self) { i in
                        DatePicker("Lembrete \(i + 1)", selection: $lembretes[i], displayedComponents: .hourAndMinute)
                    }
                    .onDelete { lembretes.remove(atOffsets: $0) }
                    Button("Adicionar lembrete", systemImage: "bell.badge") {
                        lembretes.append(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now)
                    }
                } header: {
                    Text("Lembretes diários")
                } footer: {
                    Text("Arraste pro lado pra remover.")
                }
                if habito.tipo == .abstinencia {
                    Section {
                        Button("Zerar contador sem registrar deslize", role: .destructive) { habito.inicioContagem = .now }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fundo.ignoresSafeArea())
            .navigationTitle("Editar hábito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { salvar() }.bold()
                }
            }
            .onAppear {
                let cal = Calendar.current
                lembretes = habito.lembretes.compactMap { txt in
                    let p = txt.split(separator: ":").compactMap { Int($0) }
                    guard p.count == 2 else { return nil }
                    return cal.date(bySettingHour: p[0], minute: p[1], second: 0, of: .now)
                }
            }
        }
    }

    private func salvar() {
        let cal = Calendar.current
        habito.lembretes = lembretes.map {
            String(format: "%02d:%02d", cal.component(.hour, from: $0), cal.component(.minute, from: $0))
        }
        if habito.titulo.trimmingCharacters(in: .whitespaces).isEmpty { habito.titulo = "Hábito" }
        try? ctx.save()
        Notificacoes.reagendar(ctx)
        fechar()
    }
}

struct EditarTarefaView: View {
    /// nil = tarefa nova
    var tarefa: Tarefa?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var fechar
    @State private var titulo = ""
    @State private var temData = false
    @State private var temHora = false
    @State private var quando = Date.now
    @State private var repeticao = Repeticao.nunca
    @State private var dias: Set<Int> = [2, 3, 4, 5, 6]
    @State private var tocarAlarme = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("O que precisa fazer?", text: $titulo, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Toggle("Data", isOn: $temData.animation())
                    if temData {
                        DatePicker("Dia", selection: $quando, displayedComponents: .date)
                        Toggle("Horário com alerta", isOn: $temHora.animation())
                        if temHora {
                            DatePicker("Hora", selection: $quando, displayedComponents: .hourAndMinute)
                            Toggle(isOn: $tocarAlarme) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tocar alarme")
                                    Text(tocarAlarme ? "Toca igual despertador, mesmo no silencioso" : "Só notificação (respeita o silencioso)")
                                        .font(.caption)
                                        .foregroundStyle(Color.texto2)
                                }
                            }
                            .tint(Color.verde)
                        }
                        Picker("Repetir", selection: $repeticao) {
                            ForEach(Repeticao.allCases, id: \.self) { Text($0.nome).tag($0) }
                        }
                        if repeticao == .dias {
                            // Toque pra ligar/desligar cada dia (começa na segunda)
                            HStack(spacing: 6) {
                                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                                    let ligado = dias.contains(d)
                                    Text(DiasSemana.letras[d - 1])
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(ligado ? Color.fundo : .white)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(ligado ? Color.verde : Color.cartao2, in: Circle())
                                        .onTapGesture {
                                            if ligado { dias.remove(d) } else { dias.insert(d) }
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if let tarefa {
                    Section {
                        Button("Apagar tarefa", role: .destructive) {
                            ctx.delete(tarefa)
                            try? ctx.save()
                            Notificacoes.reagendar(ctx)
                            fechar()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fundo.ignoresSafeArea())
            .navigationTitle(tarefa == nil ? "Nova tarefa" : "Editar tarefa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { fechar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { salvar() }
                        .bold()
                        .disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let tarefa else { return }
                titulo = tarefa.titulo
                temData = tarefa.quando != nil
                temHora = tarefa.temHora
                quando = tarefa.quando ?? .now
                repeticao = tarefa.repeticao
                if tarefa.repeticao == .dias { dias = Set(tarefa.dias) }
                tocarAlarme = tarefa.tocarAlarme
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func salvar() {
        var data: Date? = nil
        if temData {
            data = temHora ? quando : Calendar.current.startOfDay(for: quando)
        }
        let t = tarefa ?? {
            let nova = Tarefa(titulo: "", quando: nil, temHora: false)
            ctx.insert(nova)
            return nova
        }()
        t.titulo = titulo.trimmingCharacters(in: .whitespaces)
        t.quando = data
        t.temHora = temData && temHora
        t.tocarAlarme = tocarAlarme
        t.repeticao = temData ? repeticao : .nunca
        if t.repeticao == .dias {
            if dias.isEmpty { t.repeticao = .nunca } else { t.dias = Array(dias) }
        }
        try? ctx.save()
        Notificacoes.reagendar(ctx)
        fechar()
    }
}
