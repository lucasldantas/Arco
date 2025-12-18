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

# 2. Configuração (Igual ao anterior)
APP_BIN="/Applications/PaperCut Mobility Print Client/PaperCut Mobility Print Client.app/Contents/MacOS/mobility-print-client"
if [ -f "$APP_BIN" ]; then
    echo "STATUS: Vinculando ao Cloud..."
    "$APP_BIN" -url "$CLOUD_CONFIG_URL" &
    sleep 30
else
    echo "ERRO: Aplicativo não encontrado em $APP_BIN"
    exit 1
fi

# 3. Limpeza de Impressoras
echo "STATUS: Validando FINDME e limpando legadas..."
if lpstat -a | grep -i "PRINT-ARCO-FINDME" > /dev/null; then
    INSTALLED_PRINTERS=$(lpstat -a | awk '{print $1}')
    for PRINTER in "${TARGET_PRINTERS[@]}"; do
        if echo "$INSTALLED_PRINTERS" | grep -q "$PRINTER"; then
            echo "REMOVENDO: $PRINTER"
            sudo lpadmin -x "$PRINTER"
        fi
    done
    echo "SUCESSO: Processo concluído."
else
    echo "AVISO: Impressora FINDME não apareceu a tempo. Limpeza abortada."
fi
