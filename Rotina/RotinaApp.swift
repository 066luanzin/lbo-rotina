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

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@main
struct RotinaApp: App {
    @State private var estado = AppState.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotifDelegate.shared
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
        .modelContainer(for: [Tarefa.self, Habito.self, Registro.self])
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
            Notificacoes.reagendar(ctx)
        }
        .onChange(of: fase) { _, nova in
            if nova == .background { Notificacoes.reagendar(ctx) }
            if nova == .active {
                Agenda.shared.recarregar()
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
            PerfilView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(2)
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
