import SwiftUI
import SwiftData

struct TarefasView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Tarefa.criadaEm, order: .reverse) private var tarefas: [Tarefa]
    @State private var nova = false

    struct Grupo: Identifiable {
        let nome: String
        let itens: [Tarefa]
        var id: String { nome }
    }

    private var grupos: [Grupo] {
        let cal = Calendar.current
        let hoje = cal.startOfDay(for: .now)
        var atrasadas: [Tarefa] = [], deHoje: [Tarefa] = [], proximas: [Tarefa] = []
        var semData: [Tarefa] = [], repetem: [Tarefa] = [], feitas: [Tarefa] = []
        for t in tarefas {
            if t.repeticao != .nunca { repetem.append(t); continue }
            if t.concluidaEm != nil { feitas.append(t); continue }
            guard let q = t.quando else { semData.append(t); continue }
            if cal.isDateInToday(q) { deHoje.append(t) } else if q < hoje { atrasadas.append(t) } else { proximas.append(t) }
        }
        let porData: (Tarefa, Tarefa) -> Bool = { ($0.quando ?? .distantFuture) < ($1.quando ?? .distantFuture) }
        let concluidas = Array(feitas.sorted { ($0.concluidaEm ?? .now) > ($1.concluidaEm ?? .now) }.prefix(30))
        return [Grupo(nome: "Atrasadas", itens: atrasadas.sorted(by: porData)),
                Grupo(nome: "Hoje", itens: deHoje.sorted(by: porData)),
                Grupo(nome: "Próximas", itens: proximas.sorted(by: porData)),
                Grupo(nome: "Sem data", itens: semData),
                Grupo(nome: "Se repetem", itens: repetem),
                Grupo(nome: "Concluídas", itens: concluidas)]
            .filter { !$0.itens.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if tarefas.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "checklist").font(.system(size: 34)).foregroundStyle(Color.verde)
                                Text("Nenhuma tarefa ainda").titulo(18)
                                Text("Fale uma tarefa ou lembrete e ela aparece aqui.")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(Color.texto2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }
                        ForEach(grupos) { grupo in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(grupo.nome.uppercased())
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .tracking(1.2)
                                    .foregroundStyle(grupo.nome == "Atrasadas" ? Color.vermelho : Color.texto2)
                                ForEach(grupo.itens) { t in
                                    VStack(alignment: .leading, spacing: 0) {
                                        LinhaTarefa(tarefa: t, dia: .now)
                                        if let q = t.quando, !Calendar.current.isDateInToday(q), t.repeticao == .nunca {
                                            Text(q.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundStyle(Color.texto2)
                                                .padding(.leading, 60)
                                                .padding(.top, -2)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                BotaoFale()
                    .padding(.trailing, 18)
                    .padding(.bottom, 16)
            }
            .background(Color.fundo.ignoresSafeArea())
            .navigationTitle("Tarefas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { nova = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $nova) { EditarTarefaView(tarefa: nil) }
        }
    }
}
