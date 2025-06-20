
#!/bin/bash
set -euo pipefail

# ANSI color codes
RED='\033[1;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'
BOLD='\033[1m'

if [ $# -ne 1 ]; then
    echo -e "${RED}Usage: $0 <ZIP Code>${RESET}"
    exit 1
fi

ZIP="$1"

command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ jq is required. Install it with: sudo apt install jq${RESET}"; exit 1; }

# 1. ZIP to Lat/Lon using Zippopotam.us
echo -e "${CYAN}🔍 Resolving ZIP code $ZIP...${RESET}"
ZIPDATA=$(curl -s "http://api.zippopotam.us/us/$ZIP")

if echo "$ZIPDATA" | grep -q '"error"'; then
    echo -e "${RED}❌ Invalid ZIP code.${RESET}"
    exit 1
fi

LAT=$(echo "$ZIPDATA" | jq -r '.places[0].latitude')
LON=$(echo "$ZIPDATA" | jq -r '.places[0].longitude')
CITY=$(echo "$ZIPDATA" | jq -r '.places[0]["place name"]')
STATE=$(echo "$ZIPDATA" | jq -r '.places[0]["state abbreviation"]')

echo -e "${GREEN}📍 Location: $CITY, $STATE ($LAT, $LON)${RESET}"

# 2. Fetch weather from Open-Meteo
echo -e "${CYAN}🌤️ Fetching weather data...${RESET}"
WEATHER=$(curl -s "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current_weather=true&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=auto&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max")

# 3. Show current weather
echo -e "\n${BOLD}${YELLOW}🌡️  Current Weather in $CITY, $STATE:${RESET}"
echo "$WEATHER" | jq -r '.current_weather | "  Temperature: \(.temperature)°F\n  Wind: \(.windspeed) mph\n  Time: \(.time)"'

# 4. Hourly forecast (rest of today)
echo -e "\n${BOLD}${BLUE}⏳ Hourly Forecast (Remaining Today):${RESET}"
CURRENT_DATE=$(date +"%Y-%m-%d")
CURRENT_HOUR=$(date +"%H")

echo -e "${BOLD}Hour | Temp (°F) | Humidity (%) | Rain (%) | Wind (mph)${RESET}"
echo -e "-----|-----------|--------------|-----------|------------"

echo "$WEATHER" | jq -r --arg date "$CURRENT_DATE" --arg hour "$CURRENT_HOUR" '
  .hourly as $h |
  [range(0; ($h.time | length))] 
  | map(select($h.time[.] | startswith($date) and (. >= ($date + "T" + $hour)))) 
  | .[] 
  | "\($h.time[.] | split("T")[1][0:5]) | \($h.temperature_2m[.])      | \($h.relative_humidity_2m[.])         | \($h.precipitation_probability[.])        | \($h.wind_speed_10m[.])"' | column -t -s '|'

# 5. 7-day forecast
echo -e "\n${BOLD}${BLUE}📅 7-Day Forecast:${RESET}"
echo -e "${BOLD}Date       | High (°F) | Low (°F) | Rain (in) | Max Wind (mph)${RESET}"
echo -e "-----------|-----------|----------|-----------|----------------"

echo "$WEATHER" | jq -r '
  .daily as $d |
  [range(0; ($d.time | length))] 
  | .[] 
  | "\($d.time[.]) | \($d.temperature_2m_max[.])       | \($d.temperature_2m_min[.])      | \($d.precipitation_sum[.])        | \($d.wind_speed_10m_max[.])"' | column -t -s '|'
