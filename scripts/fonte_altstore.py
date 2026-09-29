"""Gera o altstore.json (fonte do AltStore) pra versão que acabou de ser compilada.

Uso: python3 scripts/fonte_altstore.py <versao> <build> <tag> <tamanho_bytes> <notas>
"""
import json
import sys
from datetime import datetime, timezone

versao, build, tag, tamanho, notas = sys.argv[1:6]
repo = "066luanzin/lbo-rotina"
download = f"https://github.com/{repo}/releases/download/{tag}/LBO-Rotina.ipa"
icone = f"https://raw.githubusercontent.com/{repo}/main/Rotina/Assets.xcassets/AppIcon.appiconset/icon.png"
data = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

privacidade = {
    "NSMicrophoneUsageDescription": "O LBO Rotina usa o microfone pra você falar suas tarefas e hábitos.",
    "NSSpeechRecognitionUsageDescription": "O LBO Rotina transforma o que você fala em texto pra criar tarefas e hábitos.",
    "NSAlarmKitUsageDescription": "O LBO Rotina toca um alarme na hora das suas tarefas, mesmo com o celular no silencioso.",
    "NSCalendarsFullAccessUsageDescription": "O LBO Rotina lê sua agenda pra mostrar o bloco de agora e avisar antes de cada compromisso.",
    "NSCalendarsUsageDescription": "O LBO Rotina lê sua agenda pra mostrar o bloco de agora e avisar antes de cada compromisso.",
}

fonte = {
    "name": "LBO Apps",
    "identifier": "com.lborotina.fonte",
    "subtitle": "Apps do Luan",
    "sourceURL": f"https://github.com/{repo}/releases/latest/download/altstore.json",
    "iconURL": icone,
    "tintColor": "A6F46C",
    "apps": [{
        "name": "LBO Rotina",
        "bundleIdentifier": "com.lborotina.app",
        "developerName": "Luan",
        "subtitle": "Sua rotina no comando de voz",
        "localizedDescription": "Fale uma tarefa e o app te lembra na hora certa, com alarme. "
                                "Conte uma dificuldade e ele monta um programa de hábitos com XP.",
        "iconURL": icone,
        "tintColor": "A6F46C",
        "category": "productivity",
        "screenshotURLs": [],
        "versions": [{
            "version": versao,
            "buildVersion": build,
            "date": data,
            "localizedDescription": notas,
            "downloadURL": download,
            "size": int(tamanho),
            "minOSVersion": "17.0",
        }],
        # Campos antigos (versões mais velhas do AltStore)
        "version": versao,
        "versionDate": data,
        "versionDescription": notas,
        "downloadURL": download,
        "size": int(tamanho),
        "appPermissions": {"entitlements": [], "privacy": privacidade},
    }],
    "news": [],
}
print(json.dumps(fonte, ensure_ascii=False, indent=2))
