// Roda no GitHub antes de compilar: junta Rotina/Interpretador.swift + este arquivo e executa com `swift`.
// "Agora" nos testes = segunda-feira, 28/09/2026.

var falhas = 0

func momento(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

func checar(_ fala: String, agora: String = "2026-09-28 14:00",
            titulo: String? = nil, data: String, hora: String, repeticao: String = "nunca") {
    let r = InterpretadorLocal.interpretar(fala, modo: .tarefa, agora: momento(agora))
    guard let t = r.tarefas.first else { print("FALHOU (sem tarefa):", fala); falhas += 1; return }
    let ok = t.data == data && t.hora == hora && t.repeticao == repeticao && (titulo == nil || t.titulo == titulo!)
    print(ok ? "ok     " : "FALHOU ", "\"\(fala)\" [\(agora)] -> \"\(t.titulo)\" \(t.data) \(t.hora) \(t.repeticao) | \(r.resumo)")
    if !ok {
        print("        esperado: \"\(titulo ?? "-")\" \(data) \(hora) \(repeticao)")
        falhas += 1
    }
}

// Frases reais do Luan
checar("Quero que você me lembre de colocar a máquina para 3:30",
       titulo: "Colocar a máquina", data: "2026-09-28", hora: "15:30")
checar("Quero que você me lembre de cancelar a assinatura do YouTube Music no dia 1º de outubro",
       titulo: "Cancelar a assinatura do YouTube Music", data: "2026-10-01", hora: "09:00")
checar("me lembre de cancelar a assinatura do YouTube Music dia 1 do 10",
       titulo: "Cancelar a assinatura do YouTube Music", data: "2026-10-01", hora: "09:00")

// 28/09 às 18:47: queria 06:30 da manhã, tinha ido pra 18:30
checar("Cria pra mim um alarme um alarme não cria pra mim na verdade amanhã às 6:30 pra mim comprar pão beleza",
       agora: "2026-09-28 18:47", titulo: "Comprar pão", data: "2026-09-29", hora: "06:30")
checar("amanhã 6 e meia comprar pão", agora: "2026-09-28 18:47", titulo: "Comprar pão", data: "2026-09-29", hora: "06:30")
checar("comprar pão 6:30", agora: "2026-09-28 18:47", titulo: "Comprar pão", data: "2026-09-29", hora: "06:30")
checar("seis e meia da manhã comprar pão", agora: "2026-09-28 18:47", titulo: "Comprar pão", data: "2026-09-29", hora: "06:30")
checar("amanhã às 6 correr", titulo: "Correr", data: "2026-09-29", hora: "06:00")
// Acento em formato "separado", como às vezes vem do reconhecimento de voz
checar("amanhã às 7 academia".decomposedStringWithCanonicalMapping, titulo: "Academia", data: "2026-09-29", hora: "07:00")
checar("me lembra daqui a 2 minutos de testar o alarme", titulo: "Testar o alarme", data: "2026-09-28", hora: "14:02")
checar("Prospectar o nicho de dentista quinta-feira às 2", titulo: "Prospectar o nicho de dentista", data: "2026-10-01", hora: "14:00")

// 28/09 às 22:02: queria de segunda a sexta às 7h30 mandar "plano" pro Claude.
// Criou só pra segunda e com o título errado. ("Claudio" é o reconhecimento de voz ouvindo "Claude")
checar("Eu quero que você cria pra mim lembretes de segunda a sexta todo das 7h30 com o nome de mandar mensagem para o Claudio com o nome plano",
       agora: "2026-09-28 22:02", titulo: "Mandar mensagem para o Claudio \"plano\"", data: "2026-09-29", hora: "07:30",
       repeticao: "dias:2,3,4,5,6")
checar("de segunda a sexta às 7h30 mandar mensagem pro Claude com a palavra plano",
       agora: "2026-09-28 22:02", titulo: "Mandar mensagem pro Claude \"plano\"", data: "2026-09-29", hora: "07:30",
       repeticao: "dias:2,3,4,5,6")
checar("cria um lembrete de segunda a sábado às 7h30 chamado mandar mensagem pro Claudio",
       agora: "2026-09-28 22:02", titulo: "Mandar mensagem pro Claudio", data: "2026-09-29", hora: "07:30",
       repeticao: "dias:2,3,4,5,6,7")
checar("dias úteis às 8 tomar remédio", titulo: "Tomar remédio", data: "2026-09-29", hora: "08:00", repeticao: "dias:2,3,4,5,6")
checar("segunda quarta e sexta às 18h academia", titulo: "Academia", data: "2026-09-28", hora: "18:00", repeticao: "dias:2,4,6")
checar("fim de semana às 10h lavar o carro", titulo: "Lavar o carro", data: "2026-10-03", hora: "10:00", repeticao: "dias:1,7")
checar("me lembra de segunda a sexta de beber água", titulo: "Beber água", data: "2026-09-29", hora: "09:00", repeticao: "dias:2,3,4,5,6")

// Horários ambíguos
checar("me lembra de varrer a casa hoje às 9 e meia da noite", titulo: "Varrer a casa", data: "2026-09-28", hora: "21:30")
checar("ligar pro João 3:30 PM", titulo: "Ligar pro João", data: "2026-09-28", hora: "15:30")
checar("me lembra às duas e meia de tirar a roupa do varal", titulo: "Tirar a roupa do varal", data: "2026-09-28", hora: "14:30")
checar("me lembra às 9 de beber água", agora: "2026-09-28 08:00", titulo: "Beber água", data: "2026-09-28", hora: "09:00")
checar("me lembra às 9 de beber água", titulo: "Beber água", data: "2026-09-28", hora: "21:00")
checar("me lembra às 7 de acordar cedo", agora: "2026-09-28 23:00", titulo: "Acordar cedo", data: "2026-09-29", hora: "07:00")
checar("me lembra de colocar a máquina às 15h30", titulo: "Colocar a máquina", data: "2026-09-28", hora: "15:30")
checar("tirar o lixo às 10 da manhã", agora: "2026-09-28 11:00", titulo: "Tirar o lixo", data: "2026-09-29", hora: "10:00")

// Outros dias
checar("amanhã às 7 academia", titulo: "Academia", data: "2026-09-29", hora: "07:00")
checar("amanhã às 3 reunião com o cliente", titulo: "Reunião com o cliente", data: "2026-09-29", hora: "15:00")
checar("sexta às 10 da manhã dentista", titulo: "Dentista", data: "2026-10-02", hora: "10:00")
checar("reunião segunda-feira às 9", titulo: "Reunião", data: "2026-10-05", hora: "09:00")
checar("lembrar de pagar a luz primeiro de outubro às 15 horas", titulo: "Pagar a luz", data: "2026-10-01", hora: "15:00")
checar("pagar o boleto 1/10", titulo: "Pagar o boleto", data: "2026-10-01", hora: "")
checar("meio-dia almoçar com a Ana amanhã", titulo: "Almoçar com a Ana", data: "2026-09-29", hora: "12:00")
checar("me lembra de pagar o aluguel dia 5", titulo: "Pagar o aluguel", data: "2026-10-05", hora: "09:00")
checar("aniversário da mãe dia 30", titulo: "Aniversário da mãe", data: "2026-09-30", hora: "")

// Relativo e repetição
checar("me lembra daqui a 20 minutos de tirar o bolo", titulo: "Tirar o bolo", data: "2026-09-28", hora: "14:20")
checar("me avisa em meia hora de ligar pra Ana", titulo: "Ligar pra Ana", data: "2026-09-28", hora: "14:30")
checar("tomar remédio todo dia às 22h", titulo: "Tomar remédio", data: "2026-09-28", hora: "22:00", repeticao: "diario")
checar("todo dia às 7 beber água", titulo: "Beber água", data: "2026-09-28", hora: "07:00", repeticao: "diario")
checar("toda sexta às 18h pagar o Pedro", titulo: "Pagar o Pedro", data: "2026-10-02", hora: "18:00", repeticao: "semanal")
checar("comprar pão", titulo: "Comprar pão", data: "", hora: "")
checar("hoje à noite estudar inglês", titulo: "Estudar inglês", data: "2026-09-28", hora: "20:00")

// Programas sem IA
let p = InterpretadorLocal.interpretar("não consigo parar de falar palavrão", modo: .dificuldade)
if p.habitos.count == 3 && p.habitos[0].titulo == "Ficar sem palavrão" {
    print("ok      programa palavrão:", p.habitos.map(\.titulo))
} else {
    print("FALHOU  programa palavrão:", p.habitos.map(\.titulo)); falhas += 1
}

if falhas > 0 {
    print("\n\(falhas) teste(s) falharam")
    exit(1)
}
print("\nTodos os testes passaram")
