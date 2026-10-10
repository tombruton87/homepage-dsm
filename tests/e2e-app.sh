# Homepage's steps for the chassis harness (chassis/tests/e2e.sh <appdir> act).
app_e2e_answers() { printf "HP_TITLE='Our+house'\n"; }
b64u() { printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '='; }
wait_for() { local i; for i in $(seq 1 "$2"); do touch "$VAR/watching"; jq -e "$1" "$VAR/status.json" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
services() { curl -s "http://127.0.0.1:$PORT/api/services"; }   # what Homepage itself parsed from the YAML
app_e2e_act() {
  local fail=0 url="http://127.0.0.1:$PORT" key lk
  log "homepage"
  echo "  (health: HTTP $(curl -s -o /dev/null -w '%{http_code}' "$url/api/healthcheck"), version $(jq -r .version "$VAR/status.json"))"
  curl -s "$url/" | grep -qE '<title[^>]*>Our house</title>' && echo "  ok   the wizard's title is on the page" || { echo "  FAIL title: $(curl -s "$url/" | grep -oE '<title[^>]*>[^<]*</title>')"; fail=1; }
  [[ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example:1234' "$url/api/healthcheck")" != 200 && "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example:1234' "$url/")" == 400 ]] \
    && echo "  ok   an unknown host name is refused (Homepage's host check is on)" || echo "  (unknown host: HTTP $(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example:1234' "$url/"))"
  services | jq -e 'map(select(.name == "This Synology")) | .[0].services | map(select(.name == "DSM")) | .[0].href | test(":5001$")' >/dev/null && echo "  ok   Homepage shows the DSM tile, at DSM's own port" || { echo "  FAIL dsm tile: $(services | head -c 200)"; fail=1; }
  # Something to find: a container named like the Speedtest Tracker package, and an ordinary one.
  docker rm -f speedtest-app e2eweb-demo e2enotweb-demo >/dev/null 2>&1
  docker run -d --name e2enotweb-demo -p 18433:7000 alpine sh -c 'while :; do echo junk | nc -l -p 7000; done' >/dev/null
  docker run -d --name speedtest-app -p 18431:80 nginx:alpine >/dev/null; docker run -d --name e2eweb-demo -p 18432:80 nginx:alpine >/dev/null; sleep 2
  request "ACTION='rescan'" || fail=1
  services | jq -e '(map(select(.name == "Apps")) | .[0].services | map(.name) | index("Speedtest Tracker")) and (map(select(.name == "Containers")) | .[0].services | map(.name) | index("e2eweb-demo"))' >/dev/null \
    && echo "  ok   found: Speedtest Tracker under Apps, e2eweb-demo under Containers" || { echo "  FAIL discovery: $(services | jq -c 'map({name, s: [.services[].name]})')"; fail=1; }
  services | jq -e '[.. | objects | select(.name? == "e2enotweb-demo")] | length == 0' >/dev/null && echo "  ok   a port that isn't a web page is left out" || { echo "  FAIL non-web port listed"; fail=1; }
  services | jq -e '.. | objects | select(.name? == "e2eweb-demo") | .siteMonitor | startswith("http")' >/dev/null && echo "  ok   tiles carry a site monitor (up/down, response time)" || { echo "  FAIL siteMonitor"; fail=1; }
  request "ACTION='toggle'" "ITEM='ct:e2eweb-demo'" "HIDE='1'" || fail=1
  services | jq -e '[.. | objects | select(.name? == "e2eweb-demo")] | length == 0' >/dev/null && echo "  ok   hidden" || { echo "  FAIL still shown"; fail=1; }
  request "ACTION='toggle'" "ITEM='ct:e2eweb-demo'" "HIDE='0'" >/dev/null || fail=1
  request "ACTION='linkadd'" "NAME_B64='$(b64u 'Router "home"')'" "URL_B64='$(b64u 'http://192.168.1.1/?a=1&b=2')'" "GROUP_B64='$(b64u Network)'" "ICON_B64='$(b64u router.png)'" || fail=1
  services | jq -e 'map(select(.name == "Network")) | .[0].services[0] | .name == "Router \"home\"" and .href == "http://192.168.1.1/?a=1&b=2"' >/dev/null \
    && echo "  ok   a link of your own, in your own group, quotes and & intact" || { echo "  FAIL link: $(services | jq -c 'map(select(.name == "Network"))')"; fail=1; }
  lk=$(jq -r '.app.links[0].key' "$VAR/status.json"); request "ACTION='linkdel'" "ITEM='$lk'" || fail=1
  services | jq -e 'map(select(.name == "Network")) | length == 0' >/dev/null && echo "  ok   removed" || { echo "  FAIL link not removed"; fail=1; }
  request "ACTION='look'" "TITLE_B64='$(b64u 'Home & office')'" "THEME='light'" "COLOR='emerald'" "SEARCH='0'" "CLOCK='1'" || fail=1
  sleep 2; curl -s "$url/" | grep -qE '<title[^>]*>Home &amp; office</title>' && grep -q '^color: emerald' "$APP/config/settings.yaml" && ! grep -q 'search:' "$APP/config/widgets.yaml" \
    && echo "  ok   look: title, light theme, emerald, no search box" || { echo "  FAIL look: $(curl -s "$url/" | grep -o '<title>[^<]*</title>')"; fail=1; }
  request "ACTION='dsmtest'" "DSM_USER_B64='$(b64u homepage)'" "DSM_PASS_B64='$(b64u x)'" "DSM_VOLUME=''" >/dev/null && { echo "  FAIL dsm test passed without a DSM"; fail=1; } || echo "  ok   no DSM here: $(jq -r .last.message "$VAR/status.json" | cut -c1-60)"
  # Editing by hand: the package leaves the YAML alone, and takes it back when asked.
  request "ACTION='manual'" "HIDE='1'" || fail=1
  echo '- Mine:
    - Hand made:
        href: "http://example.com"' > "$APP/config/services.yaml"
  request "ACTION='rescan'" >/dev/null; local i; for i in $(seq 1 15); do services | jq -e 'map(.name) == ["Mine"]' >/dev/null && break; sleep 1; done
  services | jq -e 'map(.name) == ["Mine"]' >/dev/null && echo "  ok   hand edits survive a look-again" || { echo "  FAIL manual: $(services | jq -c 'map(.name)'); file: $(head -c 120 "$APP/config/services.yaml" | tr '\n' ' ')"; fail=1; }
  request "ACTION='manual'" "HIDE='0'" >/dev/null; services | jq -e 'map(.name) | index("This Synology")' >/dev/null && echo "  ok   …and the package writes it again when asked" || { echo "  FAIL back to package"; fail=1; }
  ! grep -q 'search:' "$APP/config/widgets.yaml" && echo "  ok   the search box stays off when the package writes again" || { echo "  FAIL search came back"; fail=1; }
  docker rm -f speedtest-app e2eweb-demo e2enotweb-demo >/dev/null 2>&1
  # A new address: Homepage is told to answer for it.
  request "ACTION='settings'" "APP_URL='http://homepage.lan:$PORT'" "HTTP_PORT='$PORT'" "SSL_PROXY='0'" "APP_TZ='Europe/London'" || fail=1
  [[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: homepage.lan:$PORT" "$url/")" == 200 ]] && echo "  ok   answers for homepage.lan:$PORT after the address changed" || { echo "  FAIL allowed host"; fail=1; }
  (( fail == 0 )) && echo "  homepage: all passed" || echo "  homepage: something FAILED"
  return $fail
}
