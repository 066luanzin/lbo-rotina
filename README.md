# LBO Rotina

App de iPhone de rotina por voz: fale uma tarefa e ele te lembra na hora; conte uma dificuldade e ele monta um programa de hábitos com XP e lembretes.

## Como funciona
- **Captura rápida** (botão "Fale aí", ou 2 toques nas costas do iPhone): a fala vira texto na hora (reconhecimento de voz do iPhone) e o Claude transforma em tarefa com data, hora e repetição. As notificações ficam agendadas no próprio celular.
- **Programa de hábitos** (segurar o "Fale aí", ou o cartão da tela inicial): o Claude monta de 2 a 4 hábitos de 3 tipos: abstinência (contador de tempo limpo + "Escorreguei"), contagem (meta de vezes por dia) e duração (cronômetro).
- **Gamificação**: XP por registro, níveis Bronze, Prata, Ouro e Ícone, placar de 0 a 100 dos últimos 7 dias e dias seguidos.
- Sem a chave da IA, o app entende o básico sozinho ("amanhã às 9h").

## Estrutura
- `Rotina/` tem o código SwiftUI: `IA.swift` (Claude), `Voz.swift` (fala), `Models.swift` (SwiftData), `Notificacoes.swift`, `Intents.swift` (Atalhos) e as telas.
- `project.yml` é o projeto (XcodeGen).
- `.github/workflows/build.yml` compila no GitHub e gera o `LBO-Rotina.ipa`, sem assinatura. Quem assina é o AltStore.

## Instalar
1. Cada push na branch `main` gera o artefato **LBO-Rotina-ipa** na aba Actions.
2. Baixe, descompacte e instale com o AltServer (Shift + clique > Sideload .ipa).
3. No app: Perfil > cole a chave da API do Claude > Testar.
4. Atalho de 2 toques: Ajustes > Acessibilidade > Toque > Tocar Atrás > Toque Duplo > "Captura rápida".
