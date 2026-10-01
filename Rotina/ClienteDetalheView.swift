import SwiftUI
import SwiftData

/// Ficha do cliente: próximos passos (tarefas com lembrete) e todas as notas em ordem
struct ClienteDetalheView: View {
    @Bindable var cliente: Cliente
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Nota.data, order: .reverse) private var todasNotas: [Nota]
    @Query(sort: \Tarefa.criadaEm, order: .reverse) private var todasTarefas: [Tarefa]
    @State private var novoPasso = ""
    @State private var comData = false
    @State private var quando = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0,
                                                      of: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now) ?? .now
    @FocusState private var foco: Bool

    private var notas: [Nota] { todasNotas.filter { $0.cliente == cliente.nome } }
    private var pendentes: [Tarefa] {
        todasTarefas.filter { $0.cliente == cliente.nome && ($0.concluidaEm == nil || $0.repeticao != .nunca) }
            .sorted { ($0.quando ?? .distantFuture) < ($1.quando ?? .distantFuture) }
    }
    private var concluidos: [Tarefa] {
        Array(todasTarefas.filter { $0.cliente == cliente.nome && $0.concluidaEm != nil && $0.repeticao == .nunca }
            .sorted { ($0.concluidaEm ?? .now) > ($1.concluidaEm ?? .now) }
            .prefix(10))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Text(String(cliente.nome.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(width: 52, height: 52)
                        .background(Color.destaque.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cliente.nome).titulo(22)
                        Text("\(notas.count) notas · \(pendentes.count) próximos passos" + (cliente.gmb ? " · GMB" : ""))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.texto2)
                    }
                }

                // Próximos passos
                VStack(alignment: .leading, spacing: 10) {
                    Text("Próximos passos").titulo(18)
                    ForEach(pendentes) { t in LinhaTarefa(tarefa: t, dia: .now) }
                    VStack(spacing: 10) {
                        TextField("Ex.: checar resultado da página nova", text: $novoPasso, axis: .vertical)
                            .focused($foco)
                            .lineLimit(1...3)
                        Toggle("Com data e lembrete", isOn: $comData.animation()).tint(Color.verde)
                        if comData {
                            DatePicker("Quando", selection: $quando)
                        }
                        Button("Adicionar próximo passo", action: adicionarPasso)
                            .buttonStyle(EstiloPrincipal())
                            .disabled(novoPasso.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(novoPasso.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    }
                    .font(.system(size: 15, design: .rounded))
                    .cartao(14)
                    Text("Dica: na nota por voz, fale \"\(cliente.nome): checar o resultado dia 24\" que vira próximo passo sozinho.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.texto2)
                }

                if !concluidos.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Feitos recentemente").titulo(18)
                        ForEach(concluidos) { t in LinhaTarefa(tarefa: t, dia: t.concluidaEm ?? .now) }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Notas").titulo(18)
                    if notas.isEmpty {
                        Text("Nenhuma nota desse cliente ainda.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.texto2)
                    }
                    ForEach(notas) { n in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.data.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.texto2)
                            LinhaNota(nota: n)
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(Color.fundo.ignoresSafeArea())
        .navigationTitle(cliente.nome)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Editar") { ClienteEditView(cliente: cliente) }
            }
        }
    }

    private func adicionarPasso() {
        let texto = novoPasso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        let t = Tarefa(titulo: texto, quando: comData ? quando : nil, temHora: comData)
        t.cliente = cliente.nome
        ctx.insert(t)
        try? ctx.save()
        Notificacoes.reagendar(ctx)
        Haptico.sucesso()
        novoPasso = ""
        foco = false
    }
}
