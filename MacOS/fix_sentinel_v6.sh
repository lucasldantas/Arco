#!/bin/bash

sentinelToken="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="
DownloadURL="https://temp-arco-itops.s3.us-east-1.amazonaws.com/MACOS_Sentinel-Release-25-3-1-8253_macos_v25_3_1_8253.pkg"
ctlPath="/usr/local/bin/sentinelctl"
filename="sentineloneagent.pkg"

status() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

status "--- Iniciando Validação de Comunicação ---"

# 1. Checa se está conectado
if [[ -f "$ctlPath" ]]; then
    connStatus=$(sudo "$ctlPath" status | grep "Connected:" | awk '{print $2}')
    if [[ "$connStatus" == "yes" ]]; then
        status "✅ Agente já está conectado e funcional. Saindo..."
        exit 0
    fi
    status "⚠️ Agente instalado mas SEM COMUNICAÇÃO (Connected: $connStatus)."
fi

# 2. Preparação para reparo/reinstalação
TempFolder="/tmp/S1_Fix_$(date +%s)"
mkdir -p "$TempFolder"
cd "$TempFolder"

# Criar o arquivo de token que o instalador do Mac usa como prioridade
# O local /tmp/com.sentinelone.registration-token é lido pelo pacote .pkg
echo "$sentinelToken" > "/tmp/com.sentinelone.registration-token"
echo "$sentinelToken" > "com.sentinelone.registration-token"

status "Baixando instalador para forçar reparo..."
curl -L --fail --silent -o "$filename" "$DownloadURL"

# 3. Instalação sobreposta (Upgrade/Repair)
# Isso geralmente contorna o bloqueio de 'restart' porque o processo de 
# instalação tem permissão de substituir os binários e configurações.
status "Executando instalação de sobreposição..."
sudo /usr/sbin/installer -pkg "$filename" -target /

status "Aguardando inicialização (30s)..."
sleep 30

# 4. Forçar ativação se ainda não estiver conectado
finalConn=$(sudo "$ctlPath" status | grep "Connected:" | awk '{print $2}')

if [[ "$finalConn" != "yes" ]]; then
    status "Tentando vincular token via configuração persistente..."
    # Tentamos o set, mas se pedir senha, o instalador acima é nossa melhor chance
    sudo "$ctlPath" set registration_token "$sentinelToken" || status "Aviso: Autoproteção impediu comando 'set'."
    sudo "$ctlPath" agent-activation --enable || true
fi

# 5. Relatório Final
finalStatus=$(sudo "$ctlPath" status)
if echo "$finalStatus" | grep -q "Connected: yes"; then
    status "RESULTADO: [SUCESSO] Agente Conectado! ✅"
else
    status "RESULTADO: [FALHA] Agente continua sem conexão. Verifique permissões de Full Disk Access no macOS."
fi

# Limpeza
rm -rf "$TempFolder"
rm -f "/tmp/com.sentinelone.registration-token"
