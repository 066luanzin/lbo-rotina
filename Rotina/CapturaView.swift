import SwiftUI
import SwiftData

/// Tela de voz: "Fale uma tarefa ou lembrete…" / "Me conta sua dificuldade."
struct CapturaView: View {
    @State private var modo: ModoCaptura
    @Query(sort: \Cliente.ordem) private var clientes: [Cliente]
    @State private var notaCriada: Nota?
    @Environment(\.dismiss) private var fechar
    @Environment(\.modelContext) private var ctx
    @State private var voz = Voz()
    @State private var etapa = Etapa.ouvindo
    @State private var digitando = false
    @State private var textoDigitado = ""
    @State private var resultado: Interpretacao?
    @State private var criadas: [Tarefa] = []
    @State private var criados: [Habito] = []
    @State private var aviso: String?
    @FocusState private var foco: Bool

    enum Etapa { case ouvindo, pensando, pronto }

    init(modo: ModoCaptura) {
        _modo = State(initialValue: modo)
    }

    private var icone: String {
        switch modo {
        case .tarefa: return "bolt.fill"
        case .nota: return "note.text"
        case .dificuldade: return "sparkles"
        }
    }

    private var tituloModo: String {
        switch modo {
        case .tarefa: return "Captura rápida"
        case .nota: return "Nota de cliente"
        case .dificuldade: return "Programa de hábitos"
        }
    }

    /// Chips pra trocar o modo antes de salvar
    private var seletorModo: some View {
        HStack(spacing: 8) {
            ForEach([ModoCaptura.tarefa, .nota, .dificuldade]) { m in
                Text(m == .tarefa ? "Tarefa" : (m == .nota ? "Nota" : "Programa"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(modo == m ? Color.fundo : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(modo == m ? Color.verde : Color.cartao2, in: Capsule())
                    .onTapGesture {
                        Haptico.leve()
                        modo = m
                    }
            }
        }
    }

    private var fala: String {
        (digitando ? textoDigitado : voz.texto).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            topo
            if etapa == .ouvindo {
                seletorModo.padding(.top, 14)
            }
            Spacer()
            switch etapa {
            case .ouvindo: ouvindo
            case .pensando: pensando
            case .pronto: pronto
            }
            Spacer()
            rodape
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background(fundo.ignoresSafeArea())
        .task {
            if !digitando { await voz.comecar() }
        }
        .onDisappear { voz.parar() }
    }

    private var fundo: some View {
        ZStack {
            Color.fundo
            RadialGradient(colors: [Color.destaque.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
    }

    private var topo: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icone)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.fundo)
                    .frame(width: 30, height: 30)
                    .background(Color.verde, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(tituloModo)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(voz.ouvindo ? "ouvindo…" : (etapa == .pensando ? "pensando…" : "pronto"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.texto2)
                }
            }
            Spacer()
            Button {
                fechar()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.cartao2, in: Circle())
            }
        }
        .padding(.top, 8)
    }

    // MARK: Etapa 1: ouvindo

    private var ouvindo: some View {
        VStack(spacing: 26) {
            if digitando {
                TextField("", text: $textoDigitado, prompt: Text(dica).foregroundStyle(Color.white.opacity(0.3)), axis: .vertical)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2...6)
                    .focused($foco)
                    .onAppear { foco = true }
            } else {
                Text(voz.texto.isEmpty ? dica : voz.texto)
                    .font(.system(size: voz.texto.isEmpty ? 24 : 26, weight: .bold, design: .rounded))
                    .foregroundStyle(voz.texto.isEmpty ? Color.white.opacity(0.75) : .white)
                    .multilineTextAlignment(.center)
                    .animation(.easeOut(duration: 0.15), value: voz.texto)
                OndaVoz(nivel: voz.nivel, ativo: voz.ouvindo)
            }
            if let erro = voz.erro ?? aviso {
                Text(erro)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.vermelho)
                    .multilineTextAlignment(.center)
            }
            if modo == .nota && voz.texto.isEmpty && !digitando {
                Text("Ex.: \"JA Climatização: pausei a campanha de pesquisa\" ou \"ideia de vídeo: erro de orçamento baixo em PMax\"")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.texto2)
                    .multilineTextAlignment(.center)
            }
            if modo == .dificuldade && voz.texto.isEmpty && !digitando {
                Text("Ex.: \"não consigo parar de falar palavrão\", \"durmo muito tarde\", \"fico muito no celular\"")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.texto2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var dica: String {
        switch modo {
        case .tarefa: return "Fale uma tarefa ou lembrete…"
        case .nota: return "Fale o cliente e o que foi feito…"
        case .dificuldade: return "Me conta sua dificuldade."
        }
    }

    // MARK: Etapa 2: pensando

    private var pensando: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.verde)
            Text(modo == .dificuldade ? "Lendo o que você falou\ne montando os hábitos…" : "Anotando…")
                .titulo(22)
                .multilineTextAlignment(.center)
            Text("\"\(fala)\"")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color.texto2)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }

    // MARK: Etapa 3: pronto

    private var pronto: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.verde)
            if let n = notaCriada {
                Text(n.tipo == "ideia" ? "Ideia salva!" : "Nota salva!").titulo(24)
                VStack(alignment: .leading, spacing: 6) {
                    Text(n.tipo == "ideia" ? "IDEIA DE VÍDEO" : (n.cliente.isEmpty ? "GERAL" : n.cliente.uppercased()))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(n.tipo == "ideia" ? Color.orange : Color.verde)
                    Text(n.texto).font(.system(size: 16, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cartao(14)
                if n.cliente.isEmpty && n.tipo == "nota" {
                    Text("Não reconheci o cliente. Confira os nomes e apelidos em Notas > 👥.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.texto2)
                        .multilineTextAlignment(.center)
                }
            } else if !criados.isEmpty {
                Text(resultado?.programa.isEmpty == false ? resultado!.programa.uppercased() : "PROGRAMA PRONTO")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color.verde)
                Text("\(criados.count) \(criados.count == 1 ? "hábito adicionado" : "hábitos adicionados") à sua rotina.")
                    .titulo(24)
                    .multilineTextAlignment(.center)
            } else {
                Text(resultado?.resumo ?? "Pronto!")
                    .titulo(22)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                ForEach(criados) { h in
                    HStack(spacing: 12) {
                        IconeHabito(simbolo: h.icone, cor: h.cor, tamanho: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.titulo).font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("\(h.tipo.nome) · \(h.frequenciaTexto) · \(h.xp) XP")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Color.texto2)
                        }
                        Spacer()
                    }
                    .cartao(12)
                }
                ForEach(criadas) { t in
                    HStack(spacing: 12) {
                        Image(systemName: t.temHora ? "bell.fill" : "checkmark.circle")
                            .foregroundStyle(Color.verde)
                            .frame(width: 36, height: 36)
                            .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.titulo).font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text(descricao(t))
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Color.texto2)
                        }
                        Spacer()
                    }
                    .cartao(12)
                }
            }
            if !criados.isEmpty, let r = resultado, !r.resumo.isEmpty {
                Text(r.resumo)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.texto2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func descricao(_ t: Tarefa) -> String {
        guard let q = t.quando else { return "Sem horário" }
        let dia = Calendar.current.isDateInToday(q) ? "Hoje" :
            Calendar.current.isDateInTomorrow(q) ? "Amanhã" : q.formatted(.dateTime.day().month(.abbreviated))
        var s = t.temHora ? "\(dia) às \(q.formatted(.dateTime.hour().minute()))" : dia
        if t.repeticao != .nunca { s += " · \(t.repeticaoTexto.lowercased())" }
        return s
    }

    // MARK: Botões de baixo

    @ViewBuilder
    private var rodape: some View {
        VStack(spacing: 12) {
            switch etapa {
            case .ouvindo:
                Button(modo == .tarefa ? "Salvar tarefa" : (modo == .nota ? "Salvar nota" : "Montar meu programa")) {
                    Task { await enviar() }
                }
                .buttonStyle(EstiloPrincipal())
                .disabled(fala.isEmpty)
                .opacity(fala.isEmpty ? 0.45 : 1)
                HStack(spacing: 24) {
                    Button(digitando ? "Falar" : "Digitar") {
                        digitando.toggle()
                        if digitando {
                            textoDigitado = voz.texto
                            voz.parar()
                        } else {
                            foco = false
                            Task { await voz.comecar() }
                        }
                    }
                    if !digitando && !voz.ouvindo {
                        Button("Ouvir de novo") { Task { await voz.comecar() } }
                    }
                    Button("Cancelar") { fechar() }
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.texto2)
            case .pensando:
                EmptyView()
            case .pronto:
                Button(criados.isEmpty ? "Pronto" : "Começar agora") {
                    Haptico.leve()
                    fechar()
                }
                .buttonStyle(EstiloPrincipal())
                Button("Desfazer") { desfazer() }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.texto2)
            }
        }
        .padding(.top, 12)
    }

    private func enviar() async {
        let texto = fala
        guard !texto.isEmpty else { return }
        voz.parar()
        foco = false
        aviso = nil
        withAnimation { etapa = .pensando }

        if modo == .nota {
            let n = InterpretadorLocal.nota(texto, clientes: clientes.filter(\.ativo).map(\.info))
            let nova = Nota(texto: n.texto, cliente: n.cliente, tipo: n.tipo)
            ctx.insert(nova)
            try? ctx.save()
            notaCriada = nova
            Haptico.sucesso()
            withAnimation(.spring) { etapa = .pronto }
            return
        }

        var r: Interpretacao
        if IA.temChave {
            do {
                r = try await IA.interpretar(texto, modo: modo)
            } catch {
                // Sem internet ou erro na IA: não perde o que foi falado
                r = InterpretadorLocal.interpretar(texto, modo: modo)
                r.resumo = "Salvei do jeito que entendi. (\(error.localizedDescription))"
            }
        } else {
            r = InterpretadorLocal.interpretar(texto, modo: modo)
        }
        if r.tarefas.isEmpty && r.habitos.isEmpty {
            aviso = "Não entendi. Tente de novo com outras palavras."
            withAnimation { etapa = .ouvindo }
            Haptico.erro()
            return
        }
        let salvo = Aplicador.salvar(r, ctx: ctx)
        resultado = r
        criadas = salvo.tarefas
        criados = salvo.habitos
        Haptico.sucesso()
        withAnimation(.spring) { etapa = .pronto }
    }

    private func desfazer() {
        if let n = notaCriada { ctx.delete(n) }
        criadas.forEach { ctx.delete($0) }
        criados.forEach { ctx.delete($0) }
        try? ctx.save()
        Notificacoes.reagendar(ctx)
        fechar()
    }
}
