import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppState.self) private var estado
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Habito.ordem) private var habitos: [Habito]
    @Query private var registros: [Registro]
    @Query private var tarefas: [Tarefa]
    @AppStorage("nome") private var nome = ""
    @State private var dia = Date.now
    @State private var cronometro: Habito?

    private var placar: Placar { Placar(habitos: habitos, registros: registros, tarefas: tarefas) }
    private var hoje: Bool { Calendar.current.isDateInToday(dia) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        cabecalho
                        if habitos.isEmpty { cartaoPrograma }
                        semana
                        resumo
                        lista
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
            // Faixa atrás do relógio: o conteúdo rolado não fica por baixo da hora e da bateria
            .overlay(alignment: .top) {
                Color.fundo.opacity(0.95).ignoresSafeArea(edges: .top).frame(height: 0)
            }
            .navigationDestination(for: Habito.self) { HabitoDetalheView(habito: $0) }
            .sheet(item: $cronometro) { CronometroView(habito: $0) }
        }
    }

    // MARK: Cabeçalho "E aí, Luan!"

    private var cabecalho: some View {
        let nivel = Nivel.de(placar.xpTotal)
        return HStack(spacing: 12) {
            Text(String(nome.prefix(1)).uppercased())
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(width: 42, height: 42)
                .background(Color.destaque.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("E aí, \(nome)!").titulo(20)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).primeiraMaiuscula)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.texto2)
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "shield.lefthalf.filled")
                Text("\(nivel.nome) · \(placar.xpTotal) XP")
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(nivel.cor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(nivel.cor.opacity(0.14), in: Capsule())
        }
        .padding(.top, 8)
    }

    // MARK: Chamada pra montar o 1º programa

    private var cartaoPrograma: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qual hábito tá difícil?").titulo(18)
            Text("Me conta por voz e eu monto um programa com hábitos, lembretes e XP pra você.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.texto2)
            Button {
                estado.captura = .dificuldade
            } label: {
                Label("Montar meu programa", systemImage: "mic.fill")
            }
            .buttonStyle(EstiloPrincipal())
            .padding(.top, 4)
        }
        .cartao(18)
    }

    // MARK: Semana

    private var semana: some View {
        let cal = Calendar.current
        let inicio = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)) ?? .now
        let dias = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: inicio) }
        return HStack(spacing: 6) {
            ForEach(dias, id: \.self) { d in
                let p = placar.progresso(em: d)
                let f = p.0
                let t = p.1
                let sel = cal.isDate(d, inSameDayAs: dia)
                let futuro = cal.startOfDay(for: d) > cal.startOfDay(for: .now)
                Button {
                    Haptico.leve()
                    dia = d
                } label: {
                    VStack(spacing: 6) {
                        Text(d.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(sel ? Color.fundo : Color.texto2)
                        Text(d.formatted(.dateTime.day()))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(sel ? Color.fundo : .white)
                        Circle()
                            .fill(t == 0 || futuro ? Color.clear : (f == t ? Color.verde : (f > 0 ? Color.orange : Color.white.opacity(0.2))))
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(sel ? Color.verde : Color.cartao, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Placar

    private var resumo: some View {
        let (f, t) = placar.progresso(em: dia)
        let registrados = placar.registros.filter { !$0.deslize && Calendar.current.isDate($0.data, inSameDayAs: dia) }.count
        return HStack(spacing: 16) {
            ZStack {
                Anel(progresso: Double(placar.pontuacao) / 100, espessura: 9)
                VStack(spacing: 0) {
                    Text("\(placar.pontuacao)").titulo(24)
                    Text("placar").font(.system(size: 10, design: .rounded)).foregroundStyle(Color.texto2)
                }
            }
            .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 4) {
                Text(hoje ? "\(registrados) registrados hoje" : "\(registrados) registrados")
                    .titulo(18)
                Text(t == 0 ? "Nada planejado pra esse dia." : "\(f) de \(t) concluídos · \(placar.sequencia) dias seguidos")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.texto2)
                ProgressView(value: t == 0 ? 0 : Double(f) / Double(t))
                    .tint(Color.verde)
                    .padding(.top, 4)
            }
        }
        .cartao(16)
    }

    // MARK: Lista do dia

    private var lista: some View {
        let (f, t) = placar.progresso(em: dia)
        let ts = placar.tarefas(em: dia)
        let hs = habitos.filter { Calendar.current.startOfDay(for: $0.criadoEm) <= Calendar.current.startOfDay(for: dia) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(hoje ? "Hoje" : dia.formatted(.dateTime.weekday(.wide).day()).primeiraMaiuscula).titulo(20)
                Text("\(f)/\(t)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.texto2)
                Spacer()
                Button {
                    estado.captura = .tarefa
                } label: {
                    Label("Registrar", systemImage: "plus")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.cartao2, in: Capsule())
                }
                .foregroundStyle(Color.verde)
            }
            if hs.isEmpty && ts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(Color.verde)
                    Text("Toque em \"Fale aí\" e diga, por exemplo:\n\"me lembra de varrer a casa hoje às 21h30\"")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.texto2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .cartao(24)
            }
            ForEach(hs) { h in
                NavigationLink(value: h) {
                    LinhaHabito(habito: h, placar: placar, dia: dia, ativo: hoje) { cronometro = h }
                }
                .buttonStyle(.plain)
            }
            ForEach(ts) { t in
                LinhaTarefa(tarefa: t, dia: dia)
            }
        }
    }
}

/// Botão flutuante verde "Fale aí" (segurar = montar programa)
struct BotaoFale: View {
    @Environment(AppState.self) private var estado
    var body: some View {
        Label("Fale aí", systemImage: "mic.fill")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Color.fundo)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(Color.verde, in: Capsule())
            .shadow(color: Color.verde.opacity(0.45), radius: 16, y: 4)
            .onTapGesture {
                Haptico.leve()
                estado.captura = .tarefa
            }
            .onLongPressGesture {
                Haptico.sucesso()
                estado.captura = .dificuldade
            }
    }
}

// MARK: - Linhas da lista

enum Acoes {
    @MainActor
    static func registrar(_ h: Habito, ctx: ModelContext) {
        ctx.insert(Registro(habitoID: h.id, xp: h.xp))
        try? ctx.save()
        Haptico.sucesso()
    }

    /// "Escorreguei": zera o contador e guarda o recorde
    @MainActor
    static func deslize(_ h: Habito, ctx: ModelContext) {
        let tempo = Date.now.timeIntervalSince(h.inicioContagem)
        h.recordeSegundos = max(h.recordeSegundos, tempo)
        h.inicioContagem = .now
        ctx.insert(Registro(habitoID: h.id, deslize: true, xp: 0))
        try? ctx.save()
        Haptico.erro()
    }

    @MainActor
    static func alternar(_ t: Tarefa, dia: Date, ctx: ModelContext) {
        if t.feita(em: dia) {
            t.concluidaEm = nil
        } else {
            t.concluidaEm = Calendar.current.isDateInToday(dia) ? .now : dia
            Haptico.sucesso()
        }
        try? ctx.save()
        Notificacoes.reagendar(ctx)
    }
}

struct LinhaHabito: View {
    let habito: Habito
    let placar: Placar
    let dia: Date
    let ativo: Bool
    var abrirCronometro: () -> Void
    @Environment(\.modelContext) private var ctx

    var body: some View {
        let completo = placar.completo(habito, em: dia)
        let feitos = placar.feitosHoje(habito, em: dia)
        HStack(spacing: 12) {
            IconeHabito(simbolo: habito.icone, cor: habito.cor)
            VStack(alignment: .leading, spacing: 3) {
                Text(habito.titulo)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitulo(feitos))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(completo ? Color.verde : Color.texto2)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            acao(feitos: feitos, completo: completo)
        }
        .padding(12)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(completo ? Color.verde.opacity(0.35) : Color.borda, lineWidth: 1))
    }

    private func subtitulo(_ feitos: Int) -> String {
        switch habito.tipo {
        case .abstinencia:
            return "\(habito.tipo.nome) · \(habito.xp) XP/dia"
        case .contagem:
            return "\(feitos)/\(habito.meta) hoje · \(habito.xp) XP"
        case .duracao:
            return "\(feitos)/\(habito.meta) · \(habito.minutos) min · \(habito.xp) XP"
        }
    }

    @ViewBuilder
    private func acao(feitos: Int, completo: Bool) -> some View {
        switch habito.tipo {
        case .abstinencia:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let c = ctx.date.timeIntervalSince(habito.inicioContagem).contador
                Text(String(format: "%dd %02d:%02d:%02d", c.d, c.h, c.m, c.s))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.verde)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.verde.opacity(0.12), in: Capsule())
            }
        case .contagem:
            Button {
                Acoes.registrar(habito, ctx: ctx)
            } label: {
                Image(systemName: completo ? "checkmark" : "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(completo ? Color.fundo : .white)
                    .frame(width: 38, height: 38)
                    .background(completo ? Color.verde : Color.cartao2, in: Circle())
            }
            .disabled(!ativo || completo)
        case .duracao:
            Button(action: abrirCronometro) {
                Image(systemName: completo ? "checkmark" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(completo ? Color.fundo : .white)
                    .frame(width: 38, height: 38)
                    .background(completo ? Color.verde : Color.destaque, in: Circle())
            }
            .disabled(!ativo || completo)
        }
    }
}

struct LinhaTarefa: View {
    let tarefa: Tarefa
    let dia: Date
    @Environment(\.modelContext) private var ctx
    @State private var editar = false

    var body: some View {
        let feita = tarefa.feita(em: dia)
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.3)) { Acoes.alternar(tarefa, dia: dia, ctx: ctx) }
            } label: {
                Image(systemName: feita ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(feita ? Color.verde : Color.white.opacity(0.35))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(tarefa.titulo)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .strikethrough(feita)
                    .foregroundStyle(feita ? Color.texto2 : .white)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let h = tarefa.horaTexto {
                        Image(systemName: "bell.fill").font(.system(size: 10))
                        Text(h)
                    }
                    if tarefa.repeticao != .nunca {
                        Image(systemName: "repeat").font(.system(size: 10))
                        Text(tarefa.repeticaoTexto)
                    }
                    if tarefa.horaTexto == nil && tarefa.repeticao == .nunca { Text("Tarefa · \(xpTarefa) XP") }
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.texto2)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.borda, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { editar = true }
        .contextMenu {
            Button("Editar", systemImage: "pencil") { editar = true }
            Button("Apagar", systemImage: "trash", role: .destructive) {
                ctx.delete(tarefa)
                try? ctx.save()
                Notificacoes.reagendar(ctx)
            }
        }
        .sheet(isPresented: $editar) { EditarTarefaView(tarefa: tarefa) }
    }
}
