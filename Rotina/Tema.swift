import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    static let fundo = Color(hex: 0x0B0D1F)
    static let cartao = Color(hex: 0x161935)
    static let cartao2 = Color(hex: 0x21254D)
    static let borda = Color.white.opacity(0.07)
    static let destaque = Color(hex: 0x5B5FEF)
    static let verde = Color(hex: 0xA6F46C)
    static let vermelho = Color(hex: 0xFF5C6C)
    static let texto2 = Color.white.opacity(0.55)
}

/// Botão verde grande, igual ao "Salvar tarefa" / "Montar meu programa"
struct EstiloPrincipal: ButtonStyle {
    var cor: Color = .verde
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Color.fundo)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(cor, in: Capsule())
            .shadow(color: cor.opacity(0.35), radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Permite escolher o estilo do botão com um "if" (ex.: principal ou secundário)
struct AnyButtonStyle: ButtonStyle {
    private let corpo: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ estilo: S) { corpo = { AnyView(estilo.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { corpo(configuration) }
}

struct EstiloSecundario: ButtonStyle {
    var cor: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(cor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.cartao2, in: Capsule())
            .overlay(Capsule().stroke(cor.opacity(0.25), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension View {
    func cartao(_ padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.cartao, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.borda, lineWidth: 1))
    }

    func titulo(_ tamanho: CGFloat = 22) -> some View {
        self.font(.system(size: tamanho, weight: .bold, design: .rounded)).foregroundStyle(.white)
    }
}

/// Ícone do hábito num quadradinho colorido
struct IconeHabito: View {
    let simbolo: String
    var cor: Color = .destaque
    var tamanho: CGFloat = 40
    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: tamanho * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: tamanho, height: tamanho)
            .background(cor.gradient, in: RoundedRectangle(cornerRadius: tamanho * 0.3, style: .continuous))
    }
}

/// Anel de progresso (placar do dia, meta do hábito)
struct Anel: View {
    let progresso: Double
    var cor: Color = .verde
    var espessura: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: espessura)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progresso)))
                .stroke(cor, style: StrokeStyle(lineWidth: espessura, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progresso)
        }
    }
}

/// Barrinhas que pulam conforme o volume da voz
struct OndaVoz: View {
    let nivel: Double
    var ativo: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !ativo)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<18, id: \.self) { i in
                    let onda = (sin(t * 7 + Double(i) * 0.7) + 1) / 2
                    let altura = ativo ? 6 + (8 + 46 * nivel) * (0.35 + 0.65 * onda) : 6
                    Capsule()
                        .fill(Color.verde.opacity(0.55 + 0.45 * onda))
                        .frame(width: 4, height: altura)
                }
            }
            .frame(height: 64)
        }
    }
}

enum Haptico {
    static func leve() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func sucesso() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func erro() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

extension String {
    /// "segunda-feira, 28 de setembro" → "Segunda-feira, 28 de setembro"
    var primeiraMaiuscula: String { prefix(1).uppercased() + dropFirst() }
}
