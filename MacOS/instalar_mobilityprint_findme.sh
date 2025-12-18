#!/bin/zsh

################################################################################
# SCRIPT: INSTALAÇÃO MOBILITY PRINT (DMG) E LIMPEZA DE IMPRESSORAS
################################################################################

# Variáveis
MOBILITY_URL="https://cdn.papercut.com/web/products/mobility-print/installers/client/macos-cloud/mobility-print-client-installer-1.0.422.dmg"
DMG_PATH="/tmp/mobility.dmg"
MOUNT_POINT="/tmp/mobility_mount"
CLOUD_CONFIG_URL="https://mp.cloud.papercut.com/?token=eyJhbGciOiJSUzI1NiIsIm9yZyI6Im9yZy1DMUNCVE04NiIsInNydiI6InNydi1OWU1aUVk2RiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NjQwMzg3NDcsImlzcyI6InNydi1OWU1aUVk2RiIsImp0aSI6IjhUTjdDSzhZIiwibG5rIjoiOFRON0NLOFkiLCJvcmciOiJvcmctQzFDQlRNODYiLCJzcnYiOiJzcnYtTllNWlFZNkYiLCJzdWIiOiJ0b2tlbkNyZWF0aW9uIn0.itDFtOvuy1b2xpaRosrzNPrPs7EY-YOdCpdzX-VqXNhoxUaC486WU7g0x5aZCU6WCqIBP_hnUDi7yVvelmMLBD78sawBoj_1mH_rVdtWEKi_njTZOei85X7tmK4ZUYhgbExBamQ1MAIrjGRQczExBqtIk8vY09Vh5SxZ9CjDV-jlPdFBAPPdCq6xkPIzb_rjWmskwoGk7aIP4c33qitO-FAInam42-sKGH-ShIsUfbdaz9Q3nO2kVU0A-ruevoAx_Zrs-Tz3pKPHte09cHxJV8VN-iZwIO313G4JxpgSctNAapOAOqBpZBKsh40pUz0aygp-sh5_1aYgOrrwsJxQkytxTI3gMJZliunZsudmv3WT1ae4dlwpiZrUTPDF-6Z5lGG8dsNeRrVTWWHK0OGqFI4Z5c1OWaEE6f9-UWqeNRSgD82jVwh5QoQv4AY2S1uKybrdYP0MkoI8yvixUWk_Dp2oE4z8GOGB3DR6kDda6HmLFJWjTgNQrRtuiXP-sg5aJvN6cSRZadEQpjH28aFY95yBtY7C7SwwcNcwxg5HfbkxUgazPiEmoGR9W6MWUsu6k9crd6iG0wKRWxIxMHDk-UDWBNkbVjDi5ryku_pM-Sn6gwmLPXl-GAI6arKv6510Q1UVK7KdoXC58ubIManafU5LL-YIVj1dgUO436cLsdM"

TARGET_PRINTERS=(
    "PRINT-ARCO-FOR-BLACK" "PRINT-ARCO-FOR-COLOR" "PRINT-ARCO-SC-BLACK"
    "PRINT-HUB-BLACK" "PRINT-HUB-BLACK-3ANDAR" "PRINT-HUB-BLACK-TERREO"
    "PRINT-HUB-COLOR" "PRINT-HUB-COLOR-2ANDAR" "PRINT-ARCO-SP-10º_ANDAR"
    "PRINT-ARCO-DIR-SP" "PRINT-ARCO-SP-BLACK" "PRINT-ARCO-SP-COLOR"
)

# 1. Instalação
echo "STATUS: Baixando DMG..."
curl -L "$MOBILITY_URL" -o "$DMG_PATH"

echo "STATUS: Montando DMG..."
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

echo "STATUS: Instalando PKG de dentro do DMG..."
# Busca qualquer arquivo .pkg dentro do volume montado e instala
PKG_FILE=$(find "$MOUNT_POINT" -name "*.pkg")
sudo installer -pkg "$PKG_FILE" -target /

echo "STATUS: Desmontando e limpando arquivos temporários..."
hdiutil detach "$MOUNT_POINT" -quiet
rm -f "$DMG_PATH"

# 2. Configuração
# Definimos a base da instalação
BASE_DIR="/Applications/PaperCut Mobility Print Client"
echo "STATUS: Localizando o binário de execução..."
LATEST_VERSION_BIN=$(ls -d "$BASE_DIR"/v*/mobility-print-client 2>/dev/null | tail -n 1)

if [ -f "$LATEST_VERSION_BIN" ]; then
    echo "SUCESSO: Binário encontrado em: $LATEST_VERSION_BIN"
    echo "STATUS: Vinculando ao Cloud com o Token..."
    
    # Executa o binário em background (&) passando a URL do Cloud
    "$LATEST_VERSION_BIN" -url "$CLOUD_CONFIG_URL" &
    
    echo "STATUS: Aguardando 45s para registro no sistema e detecção da FINDME..."
    sleep 45
else
    # Caso a estrutura de pastas v* não exista, tenta o binário da raiz como redundância
    echo "AVISO: Pasta de versão não encontrada, tentando binário da raiz..."
    ROOT_BIN="$BASE_DIR/pc-mobility-print-client"
    
    if [ -f "$ROOT_BIN" ]; then
        "$ROOT_BIN" -url "$CLOUD_CONFIG_URL" &
        sleep 45
    else
        echo "ERRO FATAL: Não foi possível localizar o executável do Mobility Print."
        exit 1
    fi
fi

# 3. Validação e Limpeza
echo "STATUS: Validando presença da FINDME..."

# O comando lpstat -v lista os dispositivos. 
# Usamos um grep mais simples para pegar qualquer variação de "PRINT-ARCO-FINDME"
if lpstat -v | grep -i "PRINT-ARCO-FINDME" > /dev/null; then
    echo "SUCESSO: Impressora FINDME detectada no sistema!"
    
    echo "STATUS: Iniciando remoção das impressoras legadas..."
    # Obtém a lista de todas as filas de impressão atuais
    INSTALLED_PRINTERS=$(lpstat -a | awk '{print $1}')

    for PRINTER in "${TARGET_PRINTERS[@]}"; do
        # Verifica se a impressora da lista de remoção existe no Mac
        if echo "$INSTALLED_PRINTERS" | grep -q "$PRINTER"; then
            echo "REMOVENDO: $PRINTER"
            sudo lpadmin -x "$PRINTER"
        else
            echo "IGNORADO: $PRINTER não encontrada (já removida ou inexistente)."
        fi
    done
    echo "PROCESSO FINALIZADO: Configuração aplicada e limpeza concluída."
else
    echo "ERRO: A impressora FINDME não foi detectada pelo CUPS após 45s."
    echo "DICA: Verifique se o Token Cloud é válido para este ambiente."
fi
