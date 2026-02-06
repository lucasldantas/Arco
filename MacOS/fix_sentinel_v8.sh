#!/bin/bash

#########################################################
#           SENTINELONE MAC - UPGRADE & LOG             #
#########################################################

# Configurações de Log e Backup
LOG_FILE="/tmp/sentinel_fix_$(date +'%Y%m%d_%H%M%S').log"
SCRIPT_BACKUP="/tmp/sentinel_fix_current.sh"

# Salva uma cópia do script atual em /tmp
cp "$0" "$SCRIPT_BACKUP" 2>/dev/null || true

# Redireciona toda a saída para o arquivo de log e para o terminal (tee)
exec > >(tee -a "$LOG_FILE") 2>&1

sentinelToken="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="
DownloadURL="https://temp-arco-itops.s3.us-east-1.amazonaws.com/MACOS_Sentinel-Release-25-3-1-8253_macos_v25_3_1_8253.pkg"
ctlPath="/usr/local/bin/sentinelctl"
filename="sentineloneagent.pkg"

status() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

status "--- Iniciando Reparo via upgrade-pkg ---"
status "Log sendo gerado em: $LOG_FILE"

# 1. Validação de Conexão
if [[ -f "$ctlPath" ]]; then
    connStatus=$(sudo "$ctlPath" status | grep "Connected:" | awk '{print $2}')
    if [[ "$connStatus" == "yes" ]]; then
        status "✅ Agente já está conectado. Saindo..."
        exit 0
    fi
    status "⚠️ Agente detectado, mas status 'Connected' é: $connStatus"
fi

# 2. Download do Pacote
TempFolder="/tmp/S1_Upgrade_$(date +%s)"
mkdir -p "$TempFolder"
cd "$TempFolder"

status "Baixando pacote para upgrade forçado..."
if curl -L --fail --silent -o "$filename" "$DownloadURL"; then
    status "Download concluído com sucesso."
else
    status "❌ Erro ao baixar o pacote. Verifique a conexão."
    exit 1
fi

# 3. Execução do Upgrade via sentinelctl
status "Executando: sudo sentinelctl upgrade-pkg $filename"
# Tentativa de upgrade forçado para bypassar o Anti-Tamper/Self-Protection
if sudo "$ctlPath" upgrade-pkg "$filename"; then
    status "✅ Comando de upgrade aceito pelo binário."
else
    status "❌ Falha no upgrade-pkg. Tentando fallback via token file..."
    # Fallback: coloca o token onde o daemon pode ler no próximo reinício
    echo "$sentinelToken" > "/tmp/com.sentinelone.registration-token"
fi

status "Aguardando reinicialização dos serviços e handshake (45s)..."
sleep 45

# 4. Verificação Final de Conectividade e Permissões
status "--- Relatório Final de Operação ---"
if [[ -f "$ctlPath" ]]; then
    FINAL_STATUS_FULL=$(sudo "$ctlPath" status)
    finalConn=$(echo "$FINAL_STATUS_FULL" | grep "Connected:" | awk '{print $2}')

    if [[ "$finalConn" == "yes" ]]; then
        status "RESULTADO: [SUCESSO] Agente Conectado e Comunicando! ✅"
    else
        status "RESULTADO: [FALHA] Ainda sem conexão. Status: $finalConn"
        status "Verificando 'Missing Authorizations' no log..."
        echo "$FINAL_STATUS_FULL" | grep "Authorizations" || true
    fi
else
    status "RESULTADO: [ERRO] Binário sentinelctl não encontrado após o processo."
fi

# Limpeza da pasta de download (o log e o backup do script permanecem em /tmp)
rm -rf "$TempFolder"
status "Processo finalizado. Verifique o log completo em $LOG_FILE"
