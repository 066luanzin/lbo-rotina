import SwiftUI
import SwiftData

/// Onde a rotina está furando: blocos feitos por tipo, tarefas, XP e notas da semana
struct RelatorioView: View {
    @Environment(\.dismiss) private var fechar
    @Query private var tarefas: [Tarefa]
    @Query private var feitos: [BlocoFeito]
    @Query private var registros: [Registro]
    @Query private var notas: [Nota]
    @State private var semanaPassada = false

    struct LinhaTipo: Identifiable {
        let id: String
        let nome: String
        let feitos: Int
        let total: Int
        var taxa: Double { total == 0 ? 0 : Double(feitos) / Double(total) }
    }

    struct ContaCliente: Identifiable {
        let nome: String
        let qtd: Int
        var id: String { nome }
    }

    struct Resumo {
        var tipos: [LinhaTipo] = []
        var blocosFeitos = 0
        var blocosTotal = 0
        var tarefasFeitas = 0
        var tarefasTotal = 0
        var xp = 0
        var notasPorCliente: [ContaCliente] = []
        var ideias = 0
        var periodo = ""
    }

    private var dias: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2   // semana de segunda a domingo
        let base = semanaPassada ? (cal.date(byAdding: .day, value: -7, to: .now) ?? .now) : .now
        let inicio = cal.dateInterval(of: .weekOfYear, for: base)?.start ?? cal.startOfDay(for: base)
        let hoje = cal.startOfDay(for: .now)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: inicio) }.filter { $0 <= hoje }
    }

    private var resumo: Resumo {
        let cal = Calendar.current
        var r = Resumo()
        let ids = Set(feitos.map(\.blocoID))
        var totais: [String: (nome: String, feitos: Int, total: Int)] = [:]
        let placar = Placar(habitos: [], registros: [], tarefas: tarefas)

        for d in dias {
            for b in Agenda.shared.blocos(do: d) {
                let chave = Checklist.chave(b.titulo)
                var t = totais[chave] ?? (b.titulo.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression), 0, 0)
                t.total += 1
                if ids.contains(b.id) { t.feitos += 1 }
                totais[chave] = t
            }
            let ts = placar.tarefas(em: d)
            r.tarefasTotal += ts.count
            r.tarefasFeitas += ts.filter { $0.feita(em: d) }.count
        }
        r.tipos = totais.map { LinhaTipo(id: $0.key, nome: $0.value.nome, feitos: $0.value.feitos, total: $0.value.total) }
            .sorted { $0.taxa == $1.taxa ? $0.nome < $1.nome : $0.taxa < $1.taxa }
        r.blocosTotal = r.tipos.reduce(0) { $0 + $1.total }
        r.blocosFeitos = r.tipos.reduce(0) { $0 + $1.feitos }

        guard let primeiro = dias.first, let ultimo = dias.last,
              let fim = cal.date(byAdding: .day, value: 1, to: ultimo) else { return r }
        let naSemana: (Date) -> Bool = { $0 >= primeiro && $0 < fim }
        r.xp = registros.filter { naSemana($0.data) }.reduce(0) { $0 + $1.xp }
            + tarefas.filter { $0.concluidaEm.map(naSemana) ?? false }.count * xpTarefa
            + feitos.filter { naSemana($0.inicio) }.count * xpBloco
        let notasSemana = notas.filter { naSemana($0.data) }
        r.ideias = notasSemana.filter { $0.tipo == "ideia" }.count
        r.notasPorCliente = Dictionary(grouping: notasSemana.filter { $0.tipo == "nota" }) { $0.cliente.isEmpty ? "Geral" : $0.cliente }
            .map { ContaCliente(nome: $0.key, qtd: $0.value.count) }
            .sorted { $0.qtd > $1.qtd }
        r.periodo = "\(primeiro.formatted(.dateTime.day().month(.twoDigits))) a \(ultimo.formatted(.dateTime.day().month(.twoDigits)))"
        return r
    }

    private func texto(_ r: Resumo) -> String {
        var l = ["Relatório da semana — \(r.periodo)",
                 "Blocos: \(r.blocosFeitos)/\(r.blocosTotal) · Tarefas: \(r.tarefasFeitas)/\(r.tarefasTotal) · \(r.xp) XP",
                 ""]
        l.append("Por tipo de bloco (do pior pro melhor):")
        r.tipos.forEach { l.append("• \($0.nome): \($0.feitos)/\($0.total)") }
        if !r.notasPorCliente.isEmpty {
            l.append("")
            l.append("Notas por cliente:")
            r.notasPorCliente.forEach { l.append("• \($0.nome): \($0.qtd)") }
        }
        if r.ideias > 0 { l.append(""); l.append("Ideias de vídeo: \(r.ideias)") }
        return l.joined(separator: "\n")
    }

    var body: some View {
        let r = resumo
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $semanaPassada) {
                        Text("Esta semana").tag(false)
                        Text("Semana passada").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(r.periodo)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.texto2)

                    HStack(spacing: 10) {
                        numero(r.blocosTotal == 0 ? "–" : "\(Int((Double(r.blocosFeitos) / Double(r.blocosTotal) * 100).rounded()))%",
                               "blocos feitos")
                        numero("\(r.tarefasFeitas)/\(r.tarefasTotal)", "tarefas")
                        numero("\(r.xp)", "XP")
                    }

                    if r.blocosTotal > 0 {
                        let ok = MetaSemanal.bateu(feitos: r.blocosFeitos, total: r.blocosTotal)
                        Label(ok ? "Meta de \(MetaSemanal.meta)% batida (+\(MetaSemanal.xpBonus) XP)"
                                 : "Meta: \(MetaSemanal.meta)% dos blocos com check-in",
                              systemImage: ok ? "flame.fill" : "target")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(ok ? Color.orange : Color.texto2)
                    }

                    if !r.tipos.isEmpty {
                        Text("Por tipo de bloco").titulo(18)
                        VStack(spacing: 12) {
                            ForEach(r.tipos) { t in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(t.nome).font(.system(size: 15, weight: .semibold, design: .rounded))
                                        Spacer()
                                        Text("\(t.feitos)/\(t.total)")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(cor(t.taxa))
                                    }
                                    ProgressView(value: t.taxa).tint(cor(t.taxa))
                                }
                            }
                        }
                        .cartao()
                    } else {
                        Text("Sem blocos da agenda nesse período.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.texto2)
                    }

                    if !r.notasPorCliente.isEmpty || r.ideias > 0 {
                        Text("Notas").titulo(18)
                        VStack(spacing: 8) {
                            ForEach(r.notasPorCliente) { c in
                                HStack {
                                    Text(c.nome)
                                    Spacer()
                                    Text("\(c.qtd)").foregroundStyle(Color.texto2)
                                }
                            }
                            if r.ideias > 0 {
                                HStack {
                                    Text("Ideias de vídeo")
                                    Spacer()
                                    Text("\(r.ideias)").foregroundStyle(Color.orange)
                                }
                            }
                        }
                        .font(.system(size: 15, design: .rounded))
                        .cartao()
                    }

                    ShareLink(item: texto(r)) {
                        Label("Enviar relatório", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(EstiloSecundario(cor: .verde))
                }
                .padding(18)
            }
            .background(Color.fundo.ignoresSafeArea())
            .navigationTitle("Relatório da semana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fechar") { fechar() }.bold() }
            }
        }
    }

    private func cor(_ taxa: Double) -> Color {
        taxa >= 0.8 ? .verde : (taxa >= 0.5 ? .orange : .vermelho)
    }

    private func numero(_ valor: String, _ rotulo: String) -> some View {
        VStack(spacing: 2) {
            Text(valor).titulo(22)
            Text(rotulo).font(.system(size: 11, design: .rounded)).foregroundStyle(Color.texto2)
        }
        .frame(maxWidth: .infinity)
        .cartao(14)
    }
}
