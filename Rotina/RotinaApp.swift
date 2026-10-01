import SwiftUI
import SwiftData
import Observation
import UserNotifications

/// Estado compartilhado entre telas e com as ações do app Atalhos
@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    /// Abre a tela de captura por voz (atalho de 2 toques, botão "Fale aí")
    var captura: ModoCaptura?
    var aba = 0
}

/// Banco de dados único: usado pelas telas e pelos botões das notificações (mesmo com o app fechado)
enum Banco {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Tarefa.self, Habito.self, Registro.self, BlocoFeito.self,
                                      ItemChecklist.self, ItemMarcado.self, Cliente.self, Nota.self)
        } catch {
            fatalError("Não consegui abrir o banco: \(error)")
        }
    }()
}

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Botões "✅ Feito" e "⏰ Adiar 15 min" do aviso de fim de bloco
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let conteudo = response.notification.request.content
        let info = conteudo.userInfo
        let acao = response.actionIdentifier
        guard let blocoID = info["blocoID"] as? String else { return }
        let titulo = info["titulo"] as? String ?? conteudo.title
        let inicio = Date(timeIntervalSince1970: info["inicio"] as? Double ?? Date.now.timeIntervalSince1970)
        let tituloAviso = conteudo.title
        let corpoAviso = conteudo.body
        await MainActor.run {
            switch acao {
            case "feito":
                Notificacoes.marcarBloco(blocoID: blocoID, titulo: titulo, inicio: inicio)
            case "adiar":
                Notificacoes.adiar(titulo: tituloAviso, corpo: corpoAviso,
                                   blocoID: blocoID, tituloBloco: titulo, inicio: inicio)
            default:
                break
            }
        }
    }
}

@main
struct RotinaApp: App {
    @State private var estado = AppState.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotifDelegate.shared
        Notificacoes.registrarCategorias()
    }

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(estado)
                .preferredColorScheme(.dark)
                .tint(.verde)
                .onOpenURL { url in
                    // lborotina://captura  ou  lborotina://programa
                    estado.captura = url.host == "programa" ? .dificuldade : .tarefa
                }
        }
        .modelContainer(Banco.container)
    }
}

struct RaizView: View {
    @Environment(AppState.self) private var estado
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var fase
    @AppStorage("nome") private var nome = ""

    var body: some View {
        @Bindable var estado = estado
        Group {
            if nome.isEmpty {
                BoasVindasView()
            } else {
                MainView()
            }
        }
        .fullScreenCover(item: $estado.captura) { modo in
            CapturaView(modo: modo)
        }
        .task {
            if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined,
               !nome.isEmpty {
                _ = await Notificacoes.pedirPermissao()
            }
            if !nome.isEmpty && Alarmes.ligado { await Alarmes.pedirPermissao() }
            Seeds.clientes(ctx)
            Seeds.migrarAlarmes(ctx)
            Notificacoes.reagendar(ctx)
        }
        .onChange(of: fase) { _, nova in
            if nova == .background {
                Notificacoes.reagendar(ctx)
                Backup.automatico(ctx)
                Sincronizacao.sincronizar(ctx)
            }
            if nova == .active {
                Agenda.shared.recarregar()
                // Pega os pedidos do Claude Code (iCloud) antes de refazer os avisos
                Sincronizacao.sincronizar(ctx)
                Notificacoes.reagendar(ctx)
            }
        }
    }
}

struct MainView: View {
    @Environment(AppState.self) private var estado

    var body: some View {
        @Bindable var estado = estado
        TabView(selection: $estado.aba) {
            HomeView()
                .tabItem { Label("Início", systemImage: "house.fill") }
                .tag(0)
            TarefasView()
                .tabItem { Label("Tarefas", systemImage: "checklist") }
                .tag(1)
            NotasView()
                .tabItem { Label("Notas", systemImage: "note.text") }
                .tag(2)
            PerfilView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(3)
        }
    }
}

/// Primeira vez: nome e permissões
struct BoasVindasView: View {
    @AppStorage("nome") private var nome = ""
    @State private var digitado = ""
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.verde)
            Text("Sua rotina,\nno comando de voz.")
                .titulo(34)
            Text("Fale uma tarefa e eu te lembro na hora certa. Conte uma dificuldade e eu monto um programa de hábitos pra você.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.texto2)
            Spacer()
            Text("Como posso te chamar?")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.texto2)
            TextField("", text: $digitado, prompt: Text("Seu nome").foregroundStyle(Color.white.opacity(0.3)))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .padding(16)
                .background(Color.cartao, in: RoundedRectangle(cornerRadius: 16))
                .focused($foco)
                .submitLabel(.done)
                .onSubmit(entrar)
            Button("Começar", action: entrar)
                .buttonStyle(EstiloPrincipal())
                .disabled(digitado.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(digitado.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(24)
        .background(Color.fundo.ignoresSafeArea())
    }

    private func entrar() {
        let n = digitado.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            _ = await Notificacoes.pedirPermissao()
            await Alarmes.pedirPermissao()
            withAnimation { nome = n }
        }
    }
}
