import SwiftUI
import SwiftData

struct HabitoDetalheView: View {
    let habito: Habito
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var voltar
    @Query private var registros: [Registro]
    @Query private var tarefas: [Tarefa]
    @State private var editar = false
    @State private var confirmarExclusao = false
    @State private var confirmarDeslize = false
    @State private var cronometro = false

    private var meus: [Registro] { registros.filter { $0.habitoID == habito.id } }
    private var placar: Placar { Placar(habitos: [habito], registros: meus, tarefas: []) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    IconeHabito(simbolo: habito.icone, cor: habito.cor, tamanho: 64)
                    Text(habito.titulo).titulo(24).multilineTextAlignment(.center)
                    Text([habito.tipo.nome, habito.programa].filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color.texto2)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                principal

                if !habito.descricao.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMO FAZER")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Color.verde)
                        Text(habito.descricao)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cartao()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    info("Tipo", habito.tipo.nome)
                    info("Frequência", habito.frequenciaTexto)
                    info("XP", "\(habito.xp) XP / registro")
                    info("Lembretes", habito.lembretes.isEmpty ? "Nenhum" : habito.lembretes.joined(separator: ", "))
                }

                ultimosDias

                HStack(spacing: 10) {
                    Button("Editar") { editar = true }
                        .buttonStyle(EstiloSecundario())
                    Button("Excluir") { confirmarExclusao = true }
                        .buttonStyle(EstiloSecundario(cor: .vermelho))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Color.fundo.ignoresSafeArea())
        .navigationTitle(habito.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editar) { EditarHabitoView(habito: habito) }
        .sheet(isPresented: $cronometro) { CronometroView(habito: habito) }
        .confirmationDialog("Excluir \"\(habito.titulo)\"?", isPresented: $confirmarExclusao, titleVisibility: .visible) {
            Button("Excluir hábito e histórico", role: .destructive) { excluir() }
        }
        .confirmationDialog("Escorregou? Tudo bem, recomeça agora.", isPresented: $confirmarDeslize, titleVisibility: .visible) {
            Button("Registrar deslize e zerar", role: .destructive) { Acoes.deslize(habito, ctx: ctx) }
        }
    }

    // MARK: Bloco principal por tipo

    @ViewBuilder
    private var principal: some View {
        switch habito.tipo {
        case .abstinencia:
            VStack(spacing: 12) {
                Text("TEMPO LIMPO")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.texto2)
                TimelineView(.periodic(from: .now, by: 1)) { t in
                    let c = t.date.timeIntervalSince(habito.inicioContagem).contador
                    HStack(spacing: 14) {
                        bloco(c.d, "dias")
                        bloco(c.h, "hrs")
                        bloco(c.m, "min")
                        bloco(c.s, "seg")
                    }
                }
                HStack {
                    Text("Recorde")
                    Spacer()
                    Text(max(habito.recordeSegundos, Date.now.timeIntervalSince(habito.inicioContagem)).duracaoCurta)
                        .foregroundStyle(Color.verde)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.texto2)
                Button {
                    confirmarDeslize = true
                } label: {
                    Label("Escorreguei", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(EstiloSecundario(cor: .vermelho))
            }
            .cartao(18)
        case .contagem, .duracao:
            let feitos = placar.feitosHoje(habito)
            let completo = feitos >= habito.meta
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Anel(progresso: Double(feitos) / Double(habito.meta), espessura: 8)
                        Text("\(Int(min(1, Double(feitos) / Double(habito.meta)) * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(feitos)/\(habito.meta)").titulo(28)
                        Text(completo ? "Meta de hoje batida!" : "feitos hoje")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(completo ? Color.verde : Color.texto2)
                    }
                    Spacer()
                }
                if habito.tipo == .duracao {
                    Button {
                        cronometro = true
                    } label: {
                        Label("Iniciar cronômetro · \(habito.minutos) min", systemImage: "play.fill")
                    }
                    .buttonStyle(EstiloPrincipal())
                    .disabled(completo)
                    .opacity(completo ? 0.5 : 1)
                } else {
                    Button {
                        Acoes.registrar(habito, ctx: ctx)
                    } label: {
                        Label("Registrar +1", systemImage: "plus")
                    }
                    .buttonStyle(EstiloPrincipal())
                    .disabled(completo)
                    .opacity(completo ? 0.5 : 1)
                }
            }
            .cartao(18)
        }
    }

    private func bloco(_ n: Int, _ rotulo: String) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", n))
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.verde)
                .contentTransition(.numericText())
            Text(rotulo)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color.texto2)
        }
    }

    private func info(_ rotulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rotulo.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.texto2)
            Text(valor)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .cartao(14)
    }

    private var ultimosDias: some View {
        let cal = Calendar.current
        let dias = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: .now) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("ÚLTIMOS 7 DIAS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color.texto2)
            HStack {
                ForEach(dias, id: \.self) { d in
                    let antes = cal.startOfDay(for: d) < cal.startOfDay(for: habito.criadoEm)
                    let ok = !antes && placar.completo(habito, em: d)
                    VStack(spacing: 6) {
                        Circle()
                            .fill(antes ? Color.white.opacity(0.06) : (ok ? Color.verde : Color.white.opacity(0.15)))
                            .frame(width: 26, height: 26)
                            .overlay {
                                if ok { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.fundo) }
                            }
                        Text(d.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color.texto2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .cartao()
    }

    private func excluir() {
        meus.forEach { ctx.delete($0) }
        ctx.delete(habito)
        try? ctx.save()
        Notificacoes.reagendar(ctx)
        voltar()
    }
}

// MARK: - Cronômetro "Pausar e respirar · 5 min"

struct CronometroView: View {
    let habito: Habito
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var fechar
    @State private var fim: Date?
    @State private var restantePausado: TimeInterval?
    @State private var concluido = false

    private var total: TimeInterval { TimeInterval(habito.minutos * 60) }

    var body: some View {
        VStack(spacing: 28) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 5).padding(.top, 10)
            Text(habito.titulo).titulo(22)
            TimelineView(.periodic(from: .now, by: 0.2)) { t in
                let resta = restante(t.date)
                ZStack {
                    Anel(progresso: 1 - resta / total, cor: habito.cor == .destaque ? .verde : habito.cor, espessura: 14)
                    VStack(spacing: 4) {
                        Text(concluido ? "Feito!" : String(format: "%02d:%02d", Int(resta) / 60, Int(resta) % 60))
                            .font(.system(size: 52, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text(concluido ? "+\(habito.xp) XP" : (restantePausado != nil ? "pausado" : "respira fundo"))
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(concluido ? Color.verde : Color.texto2)
                    }
                }
                .frame(width: 250, height: 250)
                .onChange(of: resta <= 0) { _, acabou in
                    if acabou && !concluido && fim != nil { terminar() }
                }
            }
            if !habito.descricao.isEmpty && !concluido {
                Text(habito.descricao)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.texto2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            VStack(spacing: 12) {
                if concluido {
                    Button("Fechar") { fechar() }.buttonStyle(EstiloPrincipal())
                } else {
                    Button(restantePausado == nil ? "Pausar" : "Continuar") { pausarOuContinuar() }
                        .buttonStyle(EstiloPrincipal())
                    Button("Concluir agora") { terminar() }
                        .buttonStyle(EstiloSecundario())
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color.fundo.ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(!concluido)
        .onAppear { iniciar() }
        .onDisappear { Notificacoes.cancelar("cronometro") }
    }

    private func restante(_ agora: Date) -> TimeInterval {
        if concluido { return 0 }
        if let p = restantePausado { return p }
        guard let fim else { return total }
        return max(0, fim.timeIntervalSince(agora))
    }

    private func iniciar() {
        fim = Date.now.addingTimeInterval(total)
        Notificacoes.agora(habito.titulo, "Tempo concluído! Volte pro app pra ganhar \(habito.xp) XP.", depoisDe: total, id: "cronometro")
    }

    private func pausarOuContinuar() {
        if let p = restantePausado {
            fim = Date.now.addingTimeInterval(p)
            restantePausado = nil
            Notificacoes.agora(habito.titulo, "Tempo concluído! Volte pro app pra ganhar \(habito.xp) XP.", depoisDe: p, id: "cronometro")
        } else {
            restantePausado = restante(.now)
            Notificacoes.cancelar("cronometro")
        }
    }

    private func terminar() {
        guard !concluido else { return }
        concluido = true
        Notificacoes.cancelar("cronometro")
        Acoes.registrar(habito, ctx: ctx)
    }
}
