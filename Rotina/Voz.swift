import Foundation
import AVFoundation
import Speech
import Observation

/// Transforma a fala em texto ao vivo (reconhecimento de voz do próprio iPhone, em português)
@MainActor
@Observable
final class Voz {
    var texto = ""
    var ouvindo = false
    /// 0...1, pra animar a onda
    var nivel: Double = 0
    var erro: String?

    private let reconhecedor = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarefa: SFSpeechRecognitionTask?

    func pedirPermissoes() async -> Bool {
        let fala = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        if !fala || !mic {
            erro = "Libere o microfone e o reconhecimento de fala em Ajustes > LBO Rotina."
        }
        return fala && mic
    }

    func comecar() async {
        guard !ouvindo else { return }
        erro = nil
        texto = ""
        guard await pedirPermissoes() else { return }
        guard let reconhecedor, reconhecedor.isAvailable else {
            erro = "Reconhecimento de voz indisponível agora. Você pode digitar."
            return
        }

        do {
            let sessao = AVAudioSession.sharedInstance()
            try sessao.setCategory(.record, mode: .measurement, options: .duckOthers)
            try sessao.setActive(true, options: .notifyOthersOnDeactivation)

            let pedido = SFSpeechAudioBufferRecognitionRequest()
            pedido.shouldReportPartialResults = true
            pedido.addsPunctuation = true
            self.pedido = pedido

            let entrada = motor.inputNode
            let formato = entrada.outputFormat(forBus: 0)
            entrada.removeTap(onBus: 0)
            entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] buffer, _ in
                pedido.append(buffer)
                let n = Voz.volume(buffer)
                Task { @MainActor in self?.nivel = n }
            }
            motor.prepare()
            try motor.start()
            ouvindo = true

            tarefa = reconhecedor.recognitionTask(with: pedido) { [weak self] resultado, erro in
                let frase = resultado?.bestTranscription.formattedString
                let fim = erro != nil || (resultado?.isFinal ?? false)
                Task { @MainActor in
                    guard let self else { return }
                    if let frase { self.texto = frase }
                    if fim { self.parar() }
                }
            }
        } catch {
            self.erro = "Não consegui abrir o microfone. Tente de novo."
            parar()
        }
    }

    func parar() {
        if motor.isRunning { motor.stop() }
        motor.inputNode.removeTap(onBus: 0)
        pedido?.endAudio()
        tarefa?.finish()
        pedido = nil
        tarefa = nil
        ouvindo = false
        nivel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func volume(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let canal = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var soma: Float = 0
        for i in 0..<n { soma += canal[i] * canal[i] }
        let rms = sqrt(soma / Float(n))
        // Converte pra uma escala que "parece" certa pro olho
        let db = 20 * log10(max(rms, 0.000_01))
        return Double(max(0, min(1, (db + 50) / 40)))
    }
}
