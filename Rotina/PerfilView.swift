import SwiftUI
import SwiftData
import UserNotifications

struct PerfilView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var habitos: [Habito]
    @Query private var registros: [Registro]
    @Query private var tarefas: [Tarefa]
    @AppStorage("nome") private var nome = ""
    @AppStorage("modeloIA") private var modelo = "claude-opus-5"
    @State private var chave = Chave.ler() ?? ""
    @State private var testando = false
    @State private var resultadoTeste: String?
    @State private var apagarTudo = false
    @State private var notificacoesLigadas = true
    @State private var mostrarIA = false
    @AppStorage("alarmeTarefas") private var alarme = true
    @State private var alarmeAutorizado = Alarmes.autorizado
    @State private var agenda = Agenda.shared
    @AppStorage("avisoBlocos") private var avisoBlocos = true
    @AppStorage("minutosAntesBloco") private var minutosAntes = 5
    @AppStorage("blocosComAlarme") private var blocosComAlarme = "Alinhamento, Fechamento"
    @AppStorage("lembreteCheckin") private var lembreteCheckin = true
    @AppStorage("perguntarFimBloco") private var perguntarFimBloco = true
    @AppStorage("alarmeBlocos") private var alarmeBlocos = true
    @AppStorage("horasCheckin") private var horasCheckin = ""

    private var placar: Placar { Placar(habitos: habitos, registros: registros, tarefas: tarefas) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    nivel
                    numeros
                    atalho
                    ia
                    ajustes
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Color.fundo.ignoresSafeArea())
            .navigationTitle("Perfil")
            .task {
                notificacoesLigadas = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
                alarmeAutorizado = Alarmes.autorizado
            }
            .confirmationDialog("Apagar todas as tarefas, hábitos e XP?", isPresented: $apagarTudo, titleVisibility: .visible) {
                Button("Apagar tudo", role: .destructive) {
                    try? ctx.delete(model: Registro.self)
                    try? ctx.delete(model: Habito.self)
                    try? ctx.delete(model: Tarefa.self)
                    try? ctx.save()
                    Notificacoes.reagendar(ctx)
                }
            }
        }
    }

    // MARK: Horários do lembrete de check-in

    private func dataDe(_ h: String) -> Date {
        let hm = h.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: hm.first ?? 17, minute: hm.count > 1 ? hm[1] : 0,
                                     second: 0, of: .now) ?? .now
    }

    private func trocarHora(_ i: Int, _ data: Date) {
        var horas = Notificacoes.horasCheckin()
        guard horas.indices.contains(i) else { return }
        let cal = Calendar.current
        horas[i] = String(format: "%02d:%02d", cal.component(.hour, from: data), cal.component(.minute, from: data))
        salvarHoras(horas)
    }

    private func salvarHoras(_ horas: [String]) {
        horasCheckin = Array(Set(horas)).sorted().joined(separator: ",")
        Notificacoes.reagendar(ctx)
    }

    private var nivel: some View {
        let xp = placar.xpTotal
        let n = Nivel.de(xp)
        let prox = n.proximo
        let progresso = prox.map { Double(xp - n.xpMinimo) / Double($0.xpMinimo - n.xpMinimo) } ?? 1
        return VStack(spacing: 12) {
            ZStack {
                Anel(progresso: progresso, cor: n.cor, espessura: 7)
                Text(String(nome.prefix(1)).uppercased())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            .frame(width: 92, height: 92)
            Text(nome).titulo(22)
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                Text("Nível \(n.nome)")
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(n.cor)
            Text(prox.map { "\(xp) XP · faltam \($0.xpMinimo - xp) pra \($0.nome)" } ?? "\(xp) XP · nível máximo!")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.texto2)
        }
        .frame(maxWidth: .infinity)
        .cartao(20)
        .padding(.top, 8)
    }

    private var numeros: some View {
        HStack(spacing: 10) {
            numero("\(placar.pontuacao)", "placar")
            numero("\(placar.sequencia)", "dias seguidos")
            numero("\(registros.filter { !$0.deslize }.count + tarefas.filter { $0.concluidaEm != nil }.count)", "registros")
        }
    }

    private func numero(_ valor: String, _ rotulo: String) -> some View {
        VStack(spacing: 2) {
            Text(valor).titulo(22)
            Text(rotulo).font(.system(size: 11, design: .rounded)).foregroundStyle(Color.texto2)
        }
        .frame(maxWidth: .infinity)
        .cartao(14)
    }

    private var atalho: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Atalho de 2 toques", systemImage: "hand.tap.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.verde)
            passo(1, "Abra Ajustes > Acessibilidade > Toque > Tocar Atrás > Toque Duplo.")
            passo(2, "Escolha \"Captura rápida\" (em Atalhos, na lista). Pronto: dois toquinhos nas costas do iPhone abrem o app já ouvindo.")
            Text("Também dá pra pôr na Central de Controle: segure a Central > Adicionar controle > Atalhos > \"Captura rápida\".")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.texto2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartao()
    }

    private func passo(_ n: Int, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.fundo)
                .frame(width: 22, height: 22)
                .background(Color.verde, in: Circle())
            Text(texto).font(.system(size: 14, design: .rounded))
        }
    }

    private var ia: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { mostrarIA.toggle() }
            } label: {
                HStack {
                    Label("IA do Claude (opcional, paga)", systemImage: "sparkles")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: mostrarIA ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.texto2)
                }
            }
            .foregroundStyle(.white)
            Text(IA.temChave
                 ? "Conectado. A IA entende o que você fala e monta os programas de hábitos."
                 : "Não precisa: o app já entende datas, horários e monta programas sozinho, de graça. A IA só deixa tudo mais sob medida.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.texto2)
            if mostrarIA || IA.temChave {
            SecureField("", text: $chave, prompt: Text("sk-ant-...").foregroundStyle(Color.white.opacity(0.3)))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 12))
            Picker("Modelo", selection: $modelo) {
                ForEach(IA.modelos) { Text($0.nome).tag($0.id) }
            }
            .pickerStyle(.menu)
            HStack(spacing: 10) {
                Button("Salvar chave") {
                    Chave.salvar(chave.trimmingCharacters(in: .whitespacesAndNewlines))
                    resultadoTeste = chave.isEmpty ? "Chave removida." : "Chave salva."
                    Haptico.sucesso()
                }
                .buttonStyle(EstiloSecundario())
                Button(testando ? "Testando…" : "Testar") {
                    Chave.salvar(chave.trimmingCharacters(in: .whitespacesAndNewlines))
                    testando = true
                    Task {
                        resultadoTeste = await IA.testarChave()
                        testando = false
                    }
                }
                .buttonStyle(EstiloSecundario(cor: .verde))
                .disabled(testando || chave.isEmpty)
            }
            if let r = resultadoTeste {
                Text(r)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(r.hasPrefix("Funcionando") || r.hasPrefix("Chave") ? Color.verde : Color.vermelho)
            }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartao()
    }

    private var ajustes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ajustes", systemImage: "gearshape.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            HStack {
                Text("Nome").foregroundStyle(Color.texto2)
                // Não deixa o nome ficar vazio (senão volta pra tela de boas-vindas)
                TextField("Seu nome", text: Binding(get: { nome }, set: { if !$0.isEmpty { nome = $0 } }))
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: 15, design: .rounded))
            // Agenda (Google Agenda pelo Calendário do iPhone)
            VStack(alignment: .leading, spacing: 10) {
                Label("Agenda", systemImage: "calendar")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                if agenda.autorizada {
                    let _ = agenda.versao
                    let todos = agenda.calendarios()
                    NavigationLink {
                        CalendariosView()
                    } label: {
                        HStack {
                            Text("Calendários que aparecem")
                            Spacer()
                            Text("\(todos.filter { agenda.mostra($0.id) }.count) de \(todos.count)")
                                .foregroundStyle(Color.texto2)
                        }
                    }
                    .foregroundStyle(.white)
                    Toggle("Avisar antes de cada bloco", isOn: $avisoBlocos)
                        .tint(Color.verde)
                        .onChange(of: avisoBlocos) { _, _ in Notificacoes.reagendar(ctx) }
                    if avisoBlocos {
                        Picker("Quanto antes", selection: $minutosAntes) {
                            Text("Na hora").tag(0)
                            Text("5 min antes").tag(5)
                            Text("10 min antes").tag(10)
                            Text("15 min antes").tag(15)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: minutosAntes) { _, _ in Notificacoes.reagendar(ctx) }
                    }
                    Toggle("Perguntar \"Fez?\" no fim de cada bloco", isOn: $perguntarFimBloco)
                        .tint(Color.verde)
                        .onChange(of: perguntarFimBloco) { _, _ in Notificacoes.reagendar(ctx) }
                    Toggle(isOn: $alarmeBlocos) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alarme nos blocos importantes")
                            Text(alarmeBlocos ? "Toca igual despertador, mesmo no silencioso"
                                              : "Desligado: só a notificação normal (respeita o silencioso)")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Color.texto2)
                        }
                    }
                    .tint(Color.verde)
                    .onChange(of: alarmeBlocos) { _, _ in Notificacoes.reagendar(ctx) }
                    if alarmeBlocos {
                        Text("Blocos que tocam alarme (parte do nome, separado por vírgula)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.texto2)
                        TextField("Alinhamento, Fechamento", text: $blocosComAlarme)
                            .padding(10)
                            .background(Color.cartao2, in: RoundedRectangle(cornerRadius: 10))
                            .onSubmit { Notificacoes.reagendar(ctx) }
                    }
                    Toggle("Lembrete de check-in (seg a sex)", isOn: $lembreteCheckin)
                        .tint(Color.verde)
                        .onChange(of: lembreteCheckin) { _, _ in Notificacoes.reagendar(ctx) }
                    if lembreteCheckin {
                        let _ = horasCheckin
                        let horas = Notificacoes.horasCheckin()
                        ForEach(Array(horas.enumerated()), id: \.offset) { i, h in
                            HStack {
                                DatePicker("Lembrete \(i + 1)",
                                           selection: Binding(get: { dataDe(h) }, set: { trocarHora(i, $0) }),
                                           displayedComponents: .hourAndMinute)
                                if horas.count > 1 {
                                    Button {
                                        salvarHoras(horas.enumerated().filter { $0.offset != i }.map(\.element))
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color.vermelho)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Button {
                            // Próximo horário sugerido: 3h depois do último (ou 12:00)
                            let ultimo = horas.last.flatMap { Int($0.prefix(2)) } ?? 9
                            salvarHoras(horas + [String(format: "%02d:00", min(22, ultimo + 3))])
                        } label: {
                            Label("Adicionar horário", systemImage: "plus.circle.fill")
                                .foregroundStyle(Color.verde)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text(agenda.negada
                         ? "Acesso negado. Libere em Ajustes > Apps > LBO Rotina > Calendários > Acesso Total."
                         : "Conecte pra ver o bloco de agora e receber aviso antes de cada compromisso.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.texto2)
                    Button(agenda.negada ? "Abrir Ajustes" : "Conectar agenda") {
                        Task {
                            if agenda.negada, let url = URL(string: UIApplication.openSettingsURLString) {
                                await UIApplication.shared.open(url)
                            } else {
                                await agenda.pedirAcesso()
                                Notificacoes.reagendar(ctx)
                            }
                        }
                    }
                    .buttonStyle(EstiloSecundario(cor: .verde))
                }
            }
            .font(.system(size: 15, design: .rounded))
            .padding(.vertical, 4)

            if Alarmes.disponivel {
                Toggle(isOn: $alarme) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tocar alarme nas tarefas")
                        Text(alarme && !alarmeAutorizado ? "Toque pra permitir o alarme" : "Toca igual despertador, mesmo no silencioso")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.texto2)
                    }
                }
                .font(.system(size: 15, design: .rounded))
                .tint(Color.verde)
                .onChange(of: alarme) { _, ligado in
                    Task {
                        if ligado { alarmeAutorizado = await Alarmes.pedirPermissao() }
                        Notificacoes.reagendar(ctx)
                    }
                }
                if alarme && !alarmeAutorizado {
                    Button("Permitir alarme") {
                        Task {
                            alarmeAutorizado = await Alarmes.pedirPermissao()
                            if !alarmeAutorizado, let url = URL(string: UIApplication.openSettingsURLString) {
                                await UIApplication.shared.open(url)
                            }
                            Notificacoes.reagendar(ctx)
                        }
                    }
                    .buttonStyle(EstiloSecundario(cor: .verde))
                }
            }
            if !notificacoesLigadas {
                Button("Ativar notificações") {
                    Task {
                        notificacoesLigadas = await Notificacoes.pedirPermissao()
                        if !notificacoesLigadas, let url = URL(string: UIApplication.openSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                    }
                }
                .buttonStyle(EstiloPrincipal())
            }
            Button("Apagar todos os dados", role: .destructive) { apagarTudo = true }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.vermelho)
            Text("LBO Rotina 1.0")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color.texto2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartao()
    }
}
