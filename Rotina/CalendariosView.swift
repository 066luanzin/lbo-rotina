import SwiftUI

/// Escolhe quais calendários da conta aparecem no app (ex.: esconder o calendário de um cliente)
struct CalendariosView: View {
    @Environment(\.modelContext) private var ctx
    @State private var agenda = Agenda.shared

    var body: some View {
        let _ = agenda.versao
        let lista = agenda.calendarios()
        let contas = Array(Set(lista.map(\.conta))).sorted()
        List {
            Section {
                Text("Desligue os calendários que não são da sua rotina (de clientes, de outras empresas, compartilhados).")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.texto2)
                    .listRowBackground(Color.clear)
            }
            ForEach(contas, id: \.self) { conta in
                Section(conta) {
                    ForEach(lista.filter { $0.conta == conta }) { c in
                        Toggle(isOn: Binding(get: { agenda.mostra(c.id) },
                                             set: { _ in
                                                 agenda.alternar(c.id)
                                                 Notificacoes.reagendar(ctx)
                                             })) {
                            HStack(spacing: 10) {
                                Circle().fill(c.cor).frame(width: 12, height: 12)
                                Text(c.nome)
                            }
                        }
                        .tint(Color.verde)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.fundo.ignoresSafeArea())
        .navigationTitle("Calendários")
        .navigationBarTitleDisplayMode(.inline)
    }
}
