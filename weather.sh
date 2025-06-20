#!/bin/bash
set -euo pipefail

# ANSI colors
RED='\033[1;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'
BOLD='\033[1m'

REFRESH_INTERVAL=600  # 10 minutes

# Trap Ctrl+C to exit cleanly
trap 'echo -e "\n${RED}Interrupted. Exiting...${RESET}"; exit 0' SIGINT

if [ $# -ne 1 ]; then
    echo -e "${RED}Usage: $0 <ZIP Code>${RESET}"
    exit 1
fi

ZIP="$1"

# Input validation: only 5 digits
if ! [[ $ZIP =~ ^[0-9]{5}$ ]]; then
    echo -e "${RED}❌ Invalid ZIP code format. Please enter 5 digits only.${RESET}"
    exit 1
fi

command -v jq >/dev/null 2>&1 || {
    echo -e "${RED}❌ jq is required. Install it: sudo apt install jq${RESET}"
    exit 1
}

command -v curl >/dev/null 2>&1 || {
    echo -e "${RED}❌ curl is required. Install it: sudo apt install curl${RESET}"
    exit 1
}

command -v column >/dev/null 2>&1 || {
    echo -e "${RED}❌ column is required. Install it: sudo apt install bsdmainutils${RESET}"
    exit 1
}

# Use HTTPS for API calls, with timeout and fail options
ZIPDATA=$(curl --fail --show-error --max-time 10 -s "https://api.zippopotam.us/us/$ZIP") || {
    echo -e "${RED}❌ Failed to fetch ZIP code data.${RESET}"
    exit 1
}

if echo "$ZIPDATA" | grep -q '"error"'; then
    echo -e "${RED}❌ Invalid ZIP code.${RESET}"
    exit 1
fi

LAT=$(echo "$ZIPDATA" | jq -r '.places[0].latitude')
LON=$(echo "$ZIPDATA" | jq -r '.places[0].longitude')
CITY=$(echo "$ZIPDATA" | jq -r '.places[0]["place name"]')
STATE=$(echo "$ZIPDATA" | jq -r '.places[0]["state abbreviation"]')

while true; do
    clear
    echo -e "${GREEN}📍 Weather for $CITY, $STATE ($LAT, $LON)  —  Refreshed at $(date '+%I:%M:%S %p')${RESET}"

    WEATHER=$(curl --fail --show-error --max-time 10 -s \
      "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current_weather=true&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=auto&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max") || {
        echo -e "${RED}❌ Failed to fetch weather data.${RESET}"
        sleep "$REFRESH_INTERVAL"
        continue
    }

    echo -e "\n${YELLOW}${BOLD}🌡️  Current Weather:${RESET}"
    echo "$WEATHER" | jq -r '.current_weather | "  Temperature: \(.temperature)°F\n  Wind: \(.windspeed) mph\n  Time: \(.time)"'

    echo -e "\n${BLUE}${BOLD}⏳ Hourly Forecast (Today):${RESET}"
    echo -e "${BOLD}Hour | Temp (°F) | Humidity (%) | Rain (%) | Wind (mph)${RESET}"
    echo -e "-----|-----------|--------------|-----------|------------"
    CURRENT_DATE=$(date +"%Y-%m-%d")
    CURRENT_HOUR=$(date +"%H")

    echo "$WEATHER" | jq -r --arg date "$CURRENT_DATE" --arg hour "$CURRENT_HOUR" '
      .hourly as $h |
      [range(0; ($h.time | length))] 
      | map(select($h.time[.] | startswith($date) and (. >= ($date + "T" + $hour)))) 
      | .[] 
      | "\($h.time[.] | split("T")[1][0:5]) | \($h.temperature_2m[.])      | \($h.relative_humidity_2m[.])         | \($h.precipitation_probability[.])        | \($h.wind_speed_10m[.])"' | column -t -s '|'

    echo -e "\n${BLUE}${BOLD}📅 7-Day Forecast:${RESET}"
    echo -e "${BOLD}Date       | High (°F) | Low (°F) | Rain (in) | Max Wind (mph)${RESET}"
    echo -e "-----------|-----------|----------|-----------|----------------"
    echo "$WEATHER" | jq -r '
      .daily as $d |
      [range(0; ($d.time | length))] 
      | .[] 
      | "\($d.time[.]) | \($d.temperature_2m_max[.])       | \($d.temperature_2m_min[.])      | \($d.precipitation_sum[.])        | \($d.wind_speed_10m_max[.])"' | column -t -s '|'

    echo -e "\n${CYAN}🔁 Next refresh in $((REFRESH_INTERVAL / 60)) minutes... (Ctrl+C to exit)${RESET}"
    sleep "$REFRESH_INTERVAL"
done
