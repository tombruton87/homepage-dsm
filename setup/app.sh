# Homepage's hooks for the chassis core (sourced by run-core.sh). The core
# gives: say, env_get/env_set, rand, compose, cname, svc_up, fresh, now, MSG,
# VAR, APP, LOG, PKG_NAME, PKG_TITLE, HOST_UID/HOST_GID.
#
# Homepage is configured by YAML files. The package finds what's on this
# Synology (DSM, the other packages of this family, containers with web ports),
# keeps the dashboard's own model in $APP/.dashboard.json (hidden tiles, your
# links, the look), and writes services.yaml, settings.yaml and widgets.yaml
# from them — unless you switch to editing the YAML yourself.

HP=""; CFG=""; MODEL=""
GROUP_DSM="This Synology"; GROUP_APPS="Apps"; GROUP_CT="Containers"; GROUP_LINKS="Links"

app_validate() {   # key value → 0 if the value has the key's shape
  case "$1" in
    HP_TITLE|*_B64) [[ "$2" =~ ^[A-Za-z0-9_+-]*$ ]] && (( ${#2} <= 700 )) ;;   # free text, base64url (HP_TITLE: + for spaces)
    ITEM)   [[ "$2" =~ ^[a-z]+:[A-Za-z0-9._:-]{1,120}$ ]] ;;
    HIDE)   [[ "$2" =~ ^[01]$ ]] ;;
    THEME)  [[ "$2" =~ ^(dark|light)$ ]] ;;
    COLOR)  [[ "$2" =~ ^(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)$ ]] ;;
    SEARCH|CLOCK) [[ "$2" =~ ^[01]$ ]] ;;
    DSM_VOLUME) [[ "$2" =~ ^(volume_[0-9]{1,2})?$ ]] ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------ small helpers
b64d() { local s=${1//-/+}; s=${s//_//}; while (( ${#s} % 4 )); do s="$s="; done; printf '%s' "$s" | base64 -d 2>/dev/null; }
env_set_q() { local v=${2//\\/\\\\}; v=${v//\"/\\\"}; v=${v//\$/\$\$}; env_set "$1" "\"$v\""; }
env_get_q() { local v; v=$(env_get "$1"); v=${v#\"}; v=${v%\"}; v=${v//\$\$/\$}; v=${v//\\\"/\"}; printf '%s' "${v//\\\\/\\}"; }
yq() { local v=${1//\\/\\\\}; v=${v//\"/\\\"}; printf '"%s"' "$(tr -d '\000-\037' <<< "$v")"; }   # a YAML double-quoted string
model() { cat "$MODEL" 2>/dev/null || echo '{}'; }
model_set() { local j; j=$(jq -c "$@" <<< "$(model)") && printf '%s\n' "$j" > "$MODEL.tmp" && mv "$MODEL.tmp" "$MODEL"; }
dsm_ports() {   # → "http https" ports of DSM's own web interface
  local h s; h=$(sed -n 's/^admin_port="\([0-9]*\)"/\1/p' /etc/synoinfo.conf 2>/dev/null || true); s=$(sed -n 's/^secure_admin_port="\([0-9]*\)"/\1/p' /etc/synoinfo.conf 2>/dev/null || true)
  echo "${h:-5000} ${s:-5001}"
}
web_scheme() {   # host port → https | http | "" (nothing answers)
  curl -sk -o /dev/null --max-time 3 "https://$1:$2/" 2>/dev/null && { echo https; return; }
  curl -s -o /dev/null --max-time 3 "http://$1:$2/" 2>/dev/null && { echo http; return; }
  echo ""
}
authority() { sed -E 's#^[a-z]+://##; s#/.*$##' <<< "$1"; }   # URL → host[:port]

# ------------------------------------------------------------ lifecycle hooks
app_first_env() {
  env_set HP_IMAGE ghcr.io/gethomepage/homepage:latest
  local title; title=$(tr '+' ' ' <<< "${HP_TITLE:-}")
  MODEL="$APP/.dashboard.json"
  jq -n --arg t "${title:-My Synology}" '{title: $t, theme: "dark", color: "slate", search: true, clock: true, hidden: [], links: [], manual: false}' > "$MODEL"
}
app_load_env() { HP=$(cname server); CFG="$APP/config"; MODEL="$APP/.dashboard.json"; }
app_before_up() {
  mkdir -p "$CFG" "$APP/images"
  [[ -s "$MODEL" ]] || jq -n '{title: "My Synology", theme: "dark", color: "slate", search: true, clock: true, hidden: [], links: [], manual: false}' > "$MODEL"
  allowed_hosts
  discover; write_config
}
allowed_hosts() {   # Homepage answers only for host:port values it was given: this address, and the NAS's own
  local a; a="$(authority "$(env_get APP_URL)"),$(env_get LAN_IP):$(env_get HTTP_PORT)"
  [[ "$(env_get ALLOWED_HOSTS)" == "$a" ]] || { env_set ALLOWED_HOSTS "$a"; return 0; }
  return 1
}
app_after_up() { local i; for i in $(seq 1 30); do app_health && break; sleep 2; done; regen; }   # the page was built before it read our settings
renew_env() { compose up -d server >> "$LOG" 2>&1; app_after_up; }   # Homepage reads the DSM password from its environment: recreate it with the new one
app_health() { [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$(env_get HTTP_PORT)/api/healthcheck" 2>/dev/null)" == 200 ]]; }
app_version() { docker inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$HP" 2>/dev/null | tr -cd '0-9A-Za-z.-' | head -c 20; }

# ------------------------------------------------------------ what's on this Synology
known_app() {   # container name → "Title|icon|description" for this family's packages (and a few common ones)
  case "$1" in
    freescout-app) echo "FreeScout|freescout.png|Help desk and shared mailbox" ;;
    vaultwarden-proxy) echo "Vaultwarden|vaultwarden.png|Passwords" ;;
    uptimekuma-server) echo "Uptime Kuma|uptime-kuma.png|Is everything up?" ;;
    docuseal-proxy) echo "DocuSeal|docuseal.png|Documents to sign" ;;
    ntfy-server) echo "ntfy|ntfy.png|Notifications" ;;
    bookstack-app) echo "BookStack|bookstack.png|Wiki and how-tos" ;;
    navidrome-server) echo "Navidrome|navidrome.png|Music" ;;
    speedtest-app) echo "Speedtest Tracker|speedtest-tracker.png|Internet speed" ;;
    *) return 1 ;;
  esac
}
discover() {   # → $VAR/found.json: [{key, group, name, href, icon, description, monitor, widget?}]
  local ip dp dps name ports port hp cp scheme k info title icon desc slug items="[]" seen=" "
  ip=$(env_get LAN_IP); read -r dp dps < <(dsm_ports)
  items=$(jq -c --arg ip "$ip" --arg p "$dps" --arg ph "$dp" '. + [{key: "dsm:dsm", group: "'"$GROUP_DSM"'", name: "DSM", href: ("https://" + $ip + ":" + $p), icon: "synology-dsm.png",
      description: "This Synology", monitor: ("http://" + $ip + ":" + $ph)}]' <<< "$items")
  while IFS=$'\t' read -r name ports; do
    [[ -n "$name" ]] || continue
    case "$name" in "$PKG_NAME"-*|*-setup|*-setup-e2e|*-db|*-e2e-*) continue ;; esac
    # the first TCP port published on all addresses (not one bound to 127.0.0.1 only) that answers as a web page
    port=""; scheme=""
    while read -r hp cp; do
      case "$cp" in 3306|5432|6379|27017|11211|1883|5672|1433|9042|5060|25|587|993) continue ;; esac   # databases, brokers, mail, SIP
      [[ "$seen" == *" $hp "* ]] && continue
      scheme=$(web_scheme "$ip" "$hp")
      [[ -n "$scheme" ]] || known_app "$name" >/dev/null || continue   # not a web page (an app of ours may just be starting)
      port=$hp; break
    done < <(grep -oE '(0\.0\.0\.0|\[::\]):[0-9]+->[0-9]+/tcp' <<< "$ports" | sed -E 's/^.*:([0-9]+)->([0-9]+)\/tcp$/\1 \2/' | awk '!s[$0]++')
    [[ -n "$port" ]] || continue
    seen="$seen$port "; [[ -n "$scheme" ]] || scheme=http
    if info=$(known_app "$name"); then
      IFS='|' read -r title icon desc <<< "$info"; k="app:$name"
      items=$(jq -c --arg k "$k" --arg n "$title" --arg h "$scheme://$ip:$port" --arg i "$icon" --arg d "$desc" \
        '. + [{key: $k, group: "'"$GROUP_APPS"'", name: $n, href: $h, icon: $i, description: $d, monitor: $h}]' <<< "$items")
      if [[ "$name" == uptimekuma-server ]]; then   # its widget shows a status page's numbers, when there is one
        slug=$(docker exec "$name" sqlite3 -readonly /app/data/kuma.db "SELECT slug FROM status_page WHERE published = 1 ORDER BY id LIMIT 1" 2>/dev/null)
        [[ "$slug" =~ ^[A-Za-z0-9_-]+$ ]] && items=$(jq -c --arg k "$k" --arg u "$scheme://$ip:$port" --arg s "$slug" 'map(if .key == $k then .widget = {type: "uptimekuma", url: $u, slug: $s} else . end)' <<< "$items")
      fi
    else
      k="ct:$name"
      items=$(jq -c --arg k "$k" --arg n "$name" --arg h "$scheme://$ip:$port" '. + [{key: $k, group: "'"$GROUP_CT"'", name: $n, href: $h, icon: "docker.png", description: "", monitor: $h}]' <<< "$items")
    fi
  done < <(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | sort)
  printf '%s\n' "$items" > "$VAR/found.json.tmp" && mv "$VAR/found.json.tmp" "$VAR/found.json"
  touch "$VAR/.discovered"
}

# ------------------------------------------------------------ Homepage's YAML
write_config() {   # services.yaml, settings.yaml, widgets.yaml (and empty bookmarks/docker), from what was found and the model
  [[ "$(model | jq -r '.manual // false')" == true ]] && return 0
  local m tiles g n first dsmw ip dp
  m=$(model); ip=$(env_get LAN_IP); read -r dp _ < <(dsm_ports)
  tiles=$(jq -c --argjson m "$m" '(. + ($m.links // [] | map(. + {group: (.group // "'"$GROUP_LINKS"'"), monitor: .href})))
            | map(select((.key as $k | ($m.hidden // []) | index($k)) | not))' "$VAR/found.json" 2>/dev/null || echo "[]")
  if [[ -n "$(env_get_q DSM_USER)" ]]; then   # DSM's stats on its tile
    tiles=$(jq -c --arg u "http://$ip:$dp" 'map(if .key == "dsm:dsm" then .widget = {type: "diskstation", url: $u} else . end)' <<< "$tiles")
  fi
  local groups=("$GROUP_DSM" "$GROUP_APPS" "$GROUP_LINKS") extra
  while IFS= read -r extra; do [[ -n "$extra" ]] && groups+=("$extra"); done < <(jq -r --arg a "$GROUP_DSM" --arg b "$GROUP_APPS" --arg c "$GROUP_LINKS" --arg d "$GROUP_CT" \
    'map(.group) | unique | map(select(. != $a and . != $b and . != $c and . != $d)) | .[]' <<< "$tiles")   # your own groups, after the standard ones
  groups+=("$GROUP_CT")
  {
    echo "# Written by the Homepage package in DSM — edits here are replaced. To edit by hand, switch to it in the Homepage window first."
    for g in "${groups[@]}"; do
      [[ "$(jq --arg g "$g" 'map(select(.group == $g)) | length' <<< "$tiles")" -gt 0 ]] || continue
      echo "- $(yq "$g"):"
      jq -r --arg g "$g" '.[] | select(.group == $g) | @base64' <<< "$tiles" | while read -r row; do
        local t; t=$(base64 -d <<< "$row")
        echo "    - $(yq "$(jq -r .name <<< "$t")"):"
        echo "        href: $(yq "$(jq -r .href <<< "$t")")"
        [[ -n "$(jq -r '.icon // ""' <<< "$t")" ]] && echo "        icon: $(yq "$(jq -r .icon <<< "$t")")"
        [[ -n "$(jq -r '.description // ""' <<< "$t")" ]] && echo "        description: $(yq "$(jq -r .description <<< "$t")")"
        echo "        siteMonitor: $(yq "$(jq -r .monitor <<< "$t")")"
        case "$(jq -r '.widget.type // ""' <<< "$t")" in
          uptimekuma) printf '        widget:\n          type: uptimekuma\n          url: %s\n          slug: %s\n' "$(yq "$(jq -r .widget.url <<< "$t")")" "$(yq "$(jq -r .widget.slug <<< "$t")")" ;;
          diskstation) printf '        widget:\n          type: diskstation\n          url: %s\n          username: %s\n          password: %s\n' "$(yq "$(jq -r .widget.url <<< "$t")")" "$(yq "$(env_get_q DSM_USER)")" '"{{HOMEPAGE_VAR_DSM_PASS}}"'
                       [[ -n "$(env_get DSM_VOLUME)" ]] && printf '          volume: %s\n' "$(env_get DSM_VOLUME)" ;;
        esac
      done
    done
  } > "$CFG/services.yaml.tmp" && mv "$CFG/services.yaml.tmp" "$CFG/services.yaml"
  chmod 644 "$CFG/services.yaml"   # the DSM password isn't in it: Homepage reads it from its environment
  {
    echo "# Written by the Homepage package in DSM."
    echo "title: $(yq "$(jq -r '.title // "My Synology"' <<< "$m")")"
    echo "theme: $(jq -r '.theme // "dark"' <<< "$m")"
    echo "color: $(jq -r '.color // "slate"' <<< "$m")"
    echo "headerStyle: clean"
    echo "statusStyle: dot"
    echo "layout:"
    for g in "${groups[@]}"; do echo "  $(yq "$g"):"; echo "    style: row"; echo "    columns: 4"; done
  } > "$CFG/settings.yaml.tmp" && mv "$CFG/settings.yaml.tmp" "$CFG/settings.yaml"
  {
    echo "# Written by the Homepage package in DSM."
    [[ "$(jq -r '.clock != false' <<< "$m")" == true ]] && printf -- '- datetime:\n    text_size: xl\n    format:\n      dateStyle: long\n      timeStyle: short\n'
    [[ "$(jq -r '.search != false' <<< "$m")" == true ]] && printf -- '- search:\n    provider: duckduckgo\n    target: _blank\n'
    true
  } > "$CFG/widgets.yaml.tmp" && mv "$CFG/widgets.yaml.tmp" "$CFG/widgets.yaml"
  [[ -s "$CFG/bookmarks.yaml" ]] || echo "# Homepage bookmarks (the window keeps your links on the dashboard itself)." > "$CFG/bookmarks.yaml"
  [[ -s "$CFG/docker.yaml" ]] || echo "# No Docker socket: the package checks each tile's address instead." > "$CFG/docker.yaml"
  printf '%s\n' "$tiles" > "$VAR/tiles.json"
  regen
}
regen() {   # Homepage builds its page once: after settings change it has to be told to build it again
  svc_up server 2>/dev/null || return 0
  curl -s -o /dev/null --max-time 30 "http://127.0.0.1:$(env_get HTTP_PORT)/api/revalidate" 2>/dev/null || true
}

# ------------------------------------------------------------ what the window shows
app_status() {
  svc_up server || { echo '{"up": false}'; return 0; }
  jq -n -c --argjson found "$(cat "$VAR/found.json" 2>/dev/null || echo '[]')" --argjson m "$(model)" --arg url "$(env_get APP_URL)" \
     --arg dsm_user "$(env_get_q DSM_USER)" --arg dsm_vol "$(env_get DSM_VOLUME)" --arg found_at "$(stat -c %Y "$VAR/.discovered" 2>/dev/null || echo 0)" \
     --arg cfg "homepage/config" --arg allowed "$(env_get ALLOWED_HOSTS)" \
     '{up: true, url: $url, found: $found, found_at: ($found_at | tonumber), title: $m.title, theme: $m.theme, color: $m.color, search: $m.search, clock: $m.clock,
       hidden: ($m.hidden // []), links: ($m.links // []), manual: ($m.manual // false), dsm: {user: $dsm_user, volume: $dsm_vol}, config_dir: $cfg, allowed: $allowed}' 2>/dev/null || echo '{"up": true}'
}
app_tick() {   # look again every 10 minutes: apps come and go
  fresh "$VAR/.discovered" 600 && return 0
  local before; before=$(md5sum < "$VAR/found.json" 2>/dev/null)
  discover
  [[ "$(md5sum < "$VAR/found.json")" == "$before" ]] || { write_config; say "the dashboard was updated: what's on this Synology changed"; }
  return 0
}
app_settings() { allowed_hosts && say "Homepage now answers for $(env_get ALLOWED_HOSTS)"; return 0; }   # the core recreates the container
app_logs() { :; }
app_backup() {   # dir — the model and Homepage's configuration folder
  cp "$MODEL" "$1/dashboard.json" 2>/dev/null || echo '{}' > "$1/dashboard.json"
  tar -C "$APP" -czf "$1/config.tar.gz" config images 2>>"$LOG" || { say "✗ the configuration folder didn't tar"; return 1; }
}
app_restore() {   # dir
  [[ -f "$1/config.tar.gz" ]] || { MSG="That backup has no configuration."; return 1; }
  rm -rf "$APP/config" "$APP/images"; tar -C "$APP" -xzf "$1/config.tar.gz" 2>>"$LOG" || { MSG="The configuration didn't unpack."; return 1; }
  [[ -s "$1/dashboard.json" ]] && cp "$1/dashboard.json" "$MODEL"
}
app_storage() { jq -n -c --arg c "$(du -sm "$APP/config" 2>/dev/null | cut -f1)" --arg i "$(du -sm "$APP/images" 2>/dev/null | cut -f1)" '{config: ($c | tonumber? // 0), images: ($i | tonumber? // 0)}'; }
app_report() {
  echo "== dashboard"; model | jq -c 'del(.links) + {links: (.links | length)}'
  echo; echo "== found"; jq -r '.[] | .group + "  " + .name + "  " + (.widget.type // "")' "$VAR/found.json" 2>/dev/null
  echo; echo "== allowed hosts: $(env_get ALLOWED_HOSTS); DSM stats: $([[ -n "$(env_get_q DSM_USER)" ]] && echo on || echo off)"
  :
}

# ------------------------------------------------------------ actions
dsm_login() {   # user pass → 0 when DSM accepts them (its own Web API, as the widget will call it)
  local ip dp out; ip=$(env_get LAN_IP); read -r dp _ < <(dsm_ports)
  out=$(curl -s --max-time 10 -G "http://$ip:$dp/webapi/entry.cgi" --data-urlencode api=SYNO.API.Auth --data-urlencode version=6 --data-urlencode method=login \
        --data-urlencode "account=$1" --data-urlencode "passwd=$2" --data-urlencode session=homepage --data-urlencode format=sid 2>/dev/null)
  DSM_OUT=$out; jq -e '.success == true' <<< "$out" >/dev/null 2>&1
}
dsm_why() {   # DSM's error code → words
  case "$(jq -r '.error.code // empty' <<< "${DSM_OUT:-}" 2>/dev/null)" in
    400) echo "DSM says the username or password is wrong" ;; 401) echo "that account is disabled" ;; 402) echo "that account isn't allowed to use DSM" ;;
    403|404|406) echo "that account needs a 2-step verification code — make one without it, just for this" ;; 407) echo "DSM has blocked this address after failed tries" ;;
    "") echo "DSM didn't answer at $(env_get LAN_IP)" ;; *) echo "DSM said error $(jq -r .error.code <<< "$DSM_OUT")" ;;
  esac
}
app_act() {   # action (request vars are set)
  local n u g i
  case "$1" in
    rescan) discover; write_config; regen; MSG="Looked again: $(jq length "$VAR/found.json") things on this Synology." ;;
    toggle)
      if [[ "${HIDE:-1}" == 1 ]]; then model_set --arg k "$ITEM" '.hidden = ((.hidden // []) + [$k] | unique)'; else model_set --arg k "$ITEM" '.hidden = ((.hidden // []) - [$k])'; fi
      write_config; MSG="$([[ "${HIDE:-1}" == 1 ]] && echo Hidden || echo Shown) on the dashboard." ;;
    linkadd)
      n=$(b64d "${NAME_B64:-}"); u=$(b64d "${URL_B64:-}"); g=$(b64d "${GROUP_B64:-}"); i=$(b64d "${ICON_B64:-}")
      [[ -n "$n" && "$u" =~ ^https?://[^[:space:]]+$ ]] || { MSG="A link needs a name and an http(s):// address."; return 1; }
      model_set --arg n "$n" --arg u "$u" --arg g "${g:-$GROUP_LINKS}" --arg i "$i" --arg k "link:$(date +%s)$RANDOM" '.links = ((.links // []) + [{key: $k, name: $n, href: $u, group: $g, icon: $i, description: ""}])'
      write_config; MSG="\"$n\" is on the dashboard." ;;
    linkdel)
      model_set --arg k "$ITEM" '.links = ((.links // []) | map(select(.key != $k)))'; write_config; MSG="The link was removed." ;;
    look)
      local t; t=$(b64d "${TITLE_B64:-}")
      model_set --arg t "${t:-My Synology}" --arg th "${THEME:-dark}" --arg c "${COLOR:-slate}" --argjson s "${SEARCH:-1}" --argjson cl "${CLOCK:-1}" '.title = $t | .theme = $th | .color = $c | .search = ($s == 1) | .clock = ($cl == 1)'
      write_config; MSG="The dashboard's look was saved — reload Homepage to see it." ;;
    dsmtest|dsmset)
      u=$(b64d "${DSM_USER_B64:-}"); i=$(b64d "${DSM_PASS_B64:-}"); [[ -z "$i" ]] && i=$(env_get_q DSM_PASS)
      [[ -n "$u" && -n "$i" ]] || { MSG="A DSM username and password, please."; return 1; }
      dsm_login "$u" "$i" || { MSG="That didn't sign in: $(dsm_why)."; return 1; }
      if [[ "$1" == dsmtest ]]; then MSG="DSM accepted $u."; return 0; fi
      env_set_q DSM_USER "$u"; env_set_q DSM_PASS "$i"; env_set DSM_VOLUME "${DSM_VOLUME:-}"; renew_env; write_config
      MSG="The DSM tile shows this Synology's stats now (as $u)." ;;
    dsmoff) env_set_q DSM_USER ""; env_set_q DSM_PASS ""; renew_env; write_config; MSG="The DSM tile no longer signs in to DSM." ;;
    manual)
      model_set --argjson on "${HIDE:-0}" '.manual = ($on == 1)'
      if [[ "${HIDE:-0}" == 1 ]]; then chmod a+rw "$CFG"/*.yaml 2>/dev/null; regen; MSG="The YAML in homepage → config is yours now: the package won't change it. Edit it in File Station (Text Editor)."
      else write_config; MSG="The package writes the dashboard again (your hand edits to services.yaml, settings.yaml and widgets.yaml were replaced)."; fi ;;
    *) MSG="Unknown request."; return 1 ;;
  esac
}
