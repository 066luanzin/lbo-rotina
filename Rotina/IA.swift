import Foundation
import Security

enum ErroIA: LocalizedError {
    case semChave, recusou, resposta(String), rede(String)
    var errorDescription: String? {
        switch self {
        case .semChave: return "Coloque sua chave da API do Claude no Perfil."
        case .recusou: return "O Claude não quis responder esse pedido. Tente falar de outro jeito."
        case .resposta(let m): return "A IA respondeu com erro: \(m)"
        case .rede(let m): return "Sem conexão com a IA (\(m))."
        }
    }
}

enum IA {
    static let icones = ["sparkles", "drop.fill", "moon.fill", "sun.max.fill", "book.fill", "figure.walk",
                         "dumbbell.fill", "wind", "nosign", "brain.head.profile", "leaf.fill", "bed.double.fill",
                         "pencil", "heart.fill", "fork.knife", "flame.fill", "hand.raised.fill", "checkmark.seal.fill",
                         "iphone", "bubble.left.fill", "cup.and.saucer.fill", "music.note", "house.fill", "cart.fill"]

    struct Modelo: Identifiable {
        let id: String
        let nome: String
    }

    static let modelos = [
        Modelo(id: "claude-opus-5", nome: "Claude Opus 5 (mais esperto)"),
        Modelo(id: "claude-haiku-4-5", nome: "Claude Haiku 4.5 (mais barato)")
    ]

    static var modelo: String {
        UserDefaults.standard.string(forKey: "modeloIA") ?? "claude-opus-5"
    }

    static var temChave: Bool { !(Chave.ler() ?? "").isEmpty }

    /// Manda o que a pessoa falou pro Claude e recebe tarefas/hábitos prontos
    static func interpretar(_ fala: String, modo: ModoCaptura) async throws -> Interpretacao {
        guard let chave = Chave.ler(), !chave.isEmpty else { throw ErroIA.semChave }

        let agora = Date.now
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEE, dd/MM/yyyy 'às' HH:mm"
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"

        let pedido: String
        switch modo {
        case .tarefa:
            pedido = """
            A pessoa falou isto no modo "tarefa ou lembrete":
            "\(fala)"

            Transforme em tarefas. Se ela pedir pra ser lembrada num horário, preencha data e hora. \
            "Hoje à noite" sem hora = 20:00; "de manhã" = 08:00; "à tarde" = 15:00; "9 e meia da noite" = 21:30. \
            Sem data mas com hora: hoje se o horário ainda não passou, senão amanhã. \
            Hora de 1 a 11 sem "da manhã/da tarde/AM/PM" é ambígua: hoje, use o próximo horário que ainda não \
            passou (se agora são 14h, "3:30" = 15:30 e "9" = 21:00); em outros dias, de 1 a 6 = tarde, de 7 a 11 = manhã. \
            Pedido de lembrete com data mas sem hora = 09:00. \
            Se ela descrever um hábito recorrente pra construir ou largar (ex.: "quero beber mais água"), \
            crie em "habitos" em vez de "tarefas". Título curto, começando com verbo, sem "me lembrar de".
            """
        case .dificuldade:
            pedido = """
            A pessoa contou esta dificuldade:
            "\(fala)"

            Monte um programa curto e prático de 2 a 4 hábitos pra ajudar, no estilo de um coach gentil e direto. \
            Use os tipos: "abstinencia" (algo pra parar de fazer; o app conta o tempo sem deslize e tem o botão \
            "Escorreguei"), "contagem" (fazer X vezes no dia; meta = vezes) e "duracao" (cronômetro; minutos = \
            duração, meta = vezes por dia). Quase sempre inclua 1 hábito de abstinência ou o principal, 1 de \
            consciência/registro e 1 de técnica prática. "descricao" = como fazer, em 1 ou 2 frases, na 2ª pessoa. \
            XP entre 5 e 30 conforme o esforço. Sugira 0 a 2 lembretes por hábito, em horários que façam sentido. \
            "programa" = nome curto do objetivo (ex.: "Parar de falar palavrão"). "tarefas" fica vazio.
            """
        }

        let sistema = """
        Você é o cérebro do LBO Rotina, um app brasileiro de hábitos e tarefas controlado por voz. \
        A fala vem do reconhecimento de voz e pode ter erros; interprete a intenção. \
        Agora é \(f.string(from: agora)) (hoje = \(iso.string(from: agora)), fuso \(TimeZone.current.identifier)). \
        Responda em português do Brasil. Em "resumo", escreva uma frase curta e animada confirmando o que foi \
        criado (ex.: "Beleza! Te lembro de varrer a casa hoje às 21:30."). \
        Nos campos que não se aplicam use "" ou 0. Datas no formato AAAA-MM-DD e horas HH:mm (24h). \
        Latency-sensitive; begin your visible answer immediately.
        """

        var corpo: [String: Any] = [
            "model": modelo,
            "max_tokens": 4000,
            "system": sistema,
            "messages": [["role": "user", "content": pedido]]
        ]
        var saida: [String: Any] = ["format": ["type": "json_schema", "schema": esquema]]
        let opus = modelo.hasPrefix("claude-opus")
        if opus {
            saida["effort"] = "low"
            corpo["fallbacks"] = "default"
        }
        corpo["output_config"] = saida

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(chave, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if opus { req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        req.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let dados: Data
        let resposta: URLResponse
        do {
            (dados, resposta) = try await URLSession.shared.data(for: req)
        } catch {
            throw ErroIA.rede(error.localizedDescription)
        }

        let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] ?? [:]
        if let http = resposta as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw ErroIA.resposta(msg)
        }
        if (json["stop_reason"] as? String) == "refusal" { throw ErroIA.recusou }

        let blocos = json["content"] as? [[String: Any]] ?? []
        let texto = blocos.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard let d = texto.data(using: .utf8),
              let resultado = try? JSONDecoder().decode(Interpretacao.self, from: d) else {
            throw ErroIA.resposta("não entendi o formato da resposta")
        }
        return resultado
    }

    /// Testa a chave com um pedido mínimo
    static func testarChave() async -> String {
        do {
            let r = try await interpretar("me lembrar de beber água amanhã às 10h", modo: .tarefa)
            return "Funcionando! \(r.resumo)"
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Esquema da resposta (structured outputs)

    private static var esquema: [String: Any] {
        let tarefa: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["titulo", "data", "hora", "repeticao"],
            "properties": [
                "titulo": ["type": "string"],
                "data": ["type": "string", "description": "AAAA-MM-DD ou vazio"],
                "hora": ["type": "string", "description": "HH:mm ou vazio"],
                "repeticao": ["type": "string", "enum": ["nunca", "diario", "semanal"]]
            ]
        ]
        let habito: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["titulo", "descricao", "tipo", "meta", "minutos", "xp", "icone", "lembretes"],
            "properties": [
                "titulo": ["type": "string"],
                "descricao": ["type": "string"],
                "tipo": ["type": "string", "enum": ["abstinencia", "contagem", "duracao"]],
                "meta": ["type": "integer", "description": "vezes por dia"],
                "minutos": ["type": "integer", "description": "duração do cronômetro, só no tipo duracao"],
                "xp": ["type": "integer"],
                "icone": ["type": "string", "enum": icones],
                "lembretes": ["type": "array", "items": ["type": "string", "description": "HH:mm"]]
            ]
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["resumo", "programa", "tarefas", "habitos"],
            "properties": [
                "resumo": ["type": "string"],
                "programa": ["type": "string"],
                "tarefas": ["type": "array", "items": tarefa],
                "habitos": ["type": "array", "items": habito]
            ]
        ]
    }
}

// MARK: - Chave da API guardada no Keychain

enum Chave {
    private static let servico = "com.lborotina.claude"

    static func salvar(_ valor: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: servico]
        SecItemDelete(base as CFDictionary)
        guard !valor.isEmpty else { return }
        var novo = base
        novo[kSecValueData as String] = Data(valor.utf8)
        novo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(novo as CFDictionary, nil)
    }

    static func ler() -> String? {
        let busca: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: servico,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(busca as CFDictionary, &item) == errSecSuccess,
              let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
