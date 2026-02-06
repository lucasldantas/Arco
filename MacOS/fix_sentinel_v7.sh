#!/bin/bash

sentinelToken="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="
DownloadURL="https://temp-arco-itops.s3.us-east-1.amazonaws.com/MACOS_Sentinel-Release-25-3-1-8253_macos_v25_3_1_8253.pkg"
ctlPath="/usr/local/bin/sentinelctl"
filename="sentineloneagent.pkg"

status() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

status "--- Iniciando Reparo via upgrade-pkg ---"

# 1. Validação de Conexão
if [[ -f "$ctlPath" ]]; then
    connStatus=$(sudo "$ctlPath" status | grep "Connected:" | awk '{print $2}')
    if [[ "$connStatus" == "yes" ]]; then
        status "✅ Agente já está conectado. Saindo..."
        exit 0
    fi
fi

# 2. Download do Pacote
TempFolder="/tmp/S1_Upgrade_$(date +%s)"
mkdir -p "$TempFolder"
cd "$TempFolder"

status "Baixando pacote para upgrade forçado..."
curl -L --fail --silent -o "$filename" "$DownloadURL"

# 3. Execução do Upgrade via sentinelctl
# O comando upgrade-pkg é o único que o Sentinel aceita para sobrescrever 
# uma instalação existente sem pedir a senha (passphrase) em muitos casos.
status "Executando: sudo sentinelctl upgrade-pkg $filename"
if sudo "$ctlPath" upgrade-pkg "$filename"; then
    status "✅ Comando de upgrade aceito."
else
    status "❌ Falha no upgrade-pkg. O agente pode estar com Anti-Tamper rigoroso."
    # Se falhar, tentamos injetar o token via arquivo e torcer para o daemon ler no boot
    echo "$sentinelToken" > "/tmp/com.sentinelone.registration-token"
fi

status "Aguardando reinicialização dos serviços (40s)..."
sleep 40

# 4. Verificação Final de Conectividade
finalConn=$(sudo "$ctlPath" status | grep "Connected:" | awk '{print $2}')

if [[ "$finalConn" == "yes" ]]; then
    status "RESULTADO: [SUCESSO] Agente Conectado e Comunicando! ✅"
else
    status "RESULTADO: [FALHA] Ainda sem conexão. Status: $finalConn"
    status "Verifique se o Full Disk Access está liberado para o Sentinel."
fi

# Limpeza
rm -rf "$TempFolder"
