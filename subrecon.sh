#!/bin/bash

# Load config
CONFIG_FILE="./config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[-] Config file not found: $CONFIG_FILE"
    exit 1
fi

source $CONFIG_FILE

# Check input
if [ -z "$1" ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

DOMAIN=$1
OUTPUT_DIR="recon_$DOMAIN"
FINAL_LIST="$OUTPUT_DIR/final_subdomains.txt"
ALIVE_LIST="$OUTPUT_DIR/alive_subdomains.txt"

mkdir -p "$OUTPUT_DIR"

echo "[+] Starting recon for: $DOMAIN"

# ----------------------------
# Subdomain Enumeration
# ----------------------------

echo "[+] Running subfinder..."
subfinder -d $DOMAIN -silent >> $OUTPUT_DIR/subfinder.txt

echo "[+] Running assetfinder..."
assetfinder --subs-only $DOMAIN >> $OUTPUT_DIR/assetfinder.txt

echo "[+] Running amass..."
amass enum -passive -d $DOMAIN >> $OUTPUT_DIR/amass.txt

# Wayback Machine
echo "[+] Fetching Wayback data..."
curl -s "http://web.archive.org/cdx/search/cdx?url=*.$DOMAIN/*&output=text&fl=original&collapse=urlkey" \
| sed -e 's_https\?://__' \
| cut -d/ -f1 \
| sort -u >> $OUTPUT_DIR/wayback.txt

# ----------------------------
# Shodan Integration
# ----------------------------

if [ ! -z "$SHODAN_API_KEY" ]; then
    echo "[+] Querying Shodan..."
    curl -s "https://api.shodan.io/dns/domain/$DOMAIN?key=$SHODAN_API_KEY" \
    | jq -r '.subdomains[]' 2>/dev/null \
    | sed "s/^/./" \
    | sed "s/$DOMAIN/&/" \
    | sed "s/^\.//" \
    | awk -v domain="$DOMAIN" '{print $0 "." domain}' \
    | sort -u >> $OUTPUT_DIR/shodan.txt
else
    echo "[-] Shodan API key missing"
fi

# ----------------------------
# Censys Integration
# ----------------------------

if [ ! -z "$CENSYS_API_ID" ] && [ ! -z "$CENSYS_API_SECRET" ]; then
    echo "[+] Querying Censys..."
    
    AUTH=$(echo -n "$CENSYS_API_ID:$CENSYS_API_SECRET" | base64)

    curl -s "https://search.censys.io/api/v2/hosts/search?q=$DOMAIN" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    | jq -r '.result.hits[].name' 2>/dev/null \
    | grep "$DOMAIN" \
    | sort -u >> $OUTPUT_DIR/censys.txt
else
    echo "[-] Censys API credentials missing"
fi

# ----------------------------
# Combine Results
# ----------------------------

echo "[+] Combining results..."
cat $OUTPUT_DIR/*.txt | sort -u > $FINAL_LIST

echo "[+] Total subdomains: $(wc -l < $FINAL_LIST)"

# ----------------------------
# Alive Check
# ----------------------------

if command -v httpx &> /dev/null
then
    echo "[+] Checking alive subdomains..."
    httpx -silent -l $FINAL_LIST -o $ALIVE_LIST
else
    echo "[-] httpx not installed, skipping alive check"
fi

echo "[+] Done. Output: $OUTPUT_DIR"
