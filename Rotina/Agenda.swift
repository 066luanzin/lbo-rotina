import Foundation
import EventKit
import CryptoKit
import SwiftUI
import Observation

/// Um evento da agenda (Google Agenda sincronizado no Calendário do iPhone)
struct Bloco: Identifiable, Hashable {
    let id: String
    let titulo: String
    let inicio: Date
    let fim: Date
    let cor: Color

    var horario: String {
        "\(inicio.formatted(.dateTime.hour().minute())) – \(fim.formatted(.dateTime.hour().minute()))"
    }

    func acontecendo(_ agora: Date = .now) -> Bool { inicio <= agora && agora < fim }
}

/// Lê a agenda do iPhone. Sem API e sem custo: o próprio iOS sincroniza o Google Agenda.
@MainActor
@Observable
final class Agenda {
    static let shared = Agenda()

    private let store = EKEventStore()
    /// Muda quando a agenda é relida, pra atualizar as telas
    var versao = 0
    var autorizada: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var negada: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
    }

    @discardableResult
    func pedirAcesso() async -> Bool {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        recarregar()
        return ok
    }

    func recarregar() {
        store.refreshSourcesIfNecessary()
        versao += 1
    }

    /// Eventos com horário entre as datas (ignora dia inteiro, aniversários e feriados)
    func blocos(de inicio: Date, ate fim: Date) -> [Bloco] {
        guard autorizada else { return [] }
        let calendarios = store.calendars(for: .event).filter { $0.type != .birthday && $0.type != .subscription }
        guard !calendarios.isEmpty else { return [] }
        let busca = store.predicateForEvents(withStart: inicio, end: fim, calendars: calendarios)
        return store.events(matching: busca)
            .filter { !$0.isAllDay && $0.endDate > $0.startDate }
            .map { e in
                Bloco(id: (e.eventIdentifier ?? e.title ?? "") + "@\(Int(e.startDate.timeIntervalSince1970))",
                      titulo: e.title ?? "Evento",
                      inicio: e.startDate,
                      fim: e.endDate,
                      cor: Color(cgColor: e.calendar.cgColor))
            }
            .sorted { $0.inicio < $1.inicio }
    }

    func blocos(do dia: Date) -> [Bloco] {
        let cal = Calendar.current
        let inicio = cal.startOfDay(for: dia)
        return blocos(de: inicio, ate: cal.date(byAdding: .day, value: 1, to: inicio) ?? inicio)
    }

    /// (bloco de agora, próximo bloco) — olha até amanhã pro "próximo"
    func agoraEProximo(_ agora: Date = .now) -> (Bloco?, Bloco?) {
        let cal = Calendar.current
        let lista = blocos(de: cal.startOfDay(for: agora),
                           ate: cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: agora)) ?? agora)
        // Se tiver dois ao mesmo tempo (ex.: "WhatsApp" dentro de "Entrevista"), vale o que começou por último
        let atual = lista.filter { $0.acontecendo(agora) }.max { $0.inicio < $1.inicio }
        let proximo = lista.first { $0.inicio > agora }
        return (atual, proximo)
    }

    // MARK: - Ajustes

    static var avisarAntes: Bool { UserDefaults.standard.object(forKey: "avisoBlocos") as? Bool ?? true }
    static var minutosAntes: Int { UserDefaults.standard.object(forKey: "minutosAntesBloco") as? Int ?? 5 }
    /// Blocos que tocam alarme de verdade (partes do nome, separadas por vírgula)
    static var comAlarme: [String] {
        (UserDefaults.standard.string(forKey: "blocosComAlarme") ?? "Alinhamento, Fechamento")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func tocaAlarme(_ b: Bloco) -> Bool {
        let t = b.titulo.lowercased()
        return comAlarme.contains { t.contains($0) }
    }
}

extension UUID {
    /// UUID fixo a partir de um texto (o mesmo evento gera sempre o mesmo id de alarme)
    init(texto: String) {
        let b = Array(Insecure.MD5.hash(data: Data(texto.utf8)))
        self = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
