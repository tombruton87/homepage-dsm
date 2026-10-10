# Homepage's actions, validated by the CGI before they become a request file. Free text travels base64url.
b64u() { printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '='; }
app_cgi_post() {   # action body → sets $lines, or error
  local a=$1 body=$2 item v n u g i t th c s cl vol
  case "$a" in
    rescan|dsmoff) lines="ACTION='$a'" ;;
    toggle|linkdel) item=$(decode "$(param item "$body")"); [[ "$item" =~ ^[a-z]+:[A-Za-z0-9._:-]{1,120}$ ]] || error "400 Bad Request" "Pick a tile."
      lines="ACTION='$a'
ITEM='$item'"
      if [[ "$a" == toggle ]]; then v=$(param hide "$body"); [[ "$v" =~ ^[01]$ ]] || error "400 Bad Request" "Show or hide."; lines="$lines
HIDE='$v'"; fi ;;
    manual) v=$(param on "$body"); [[ "$v" =~ ^[01]$ ]] || error "400 Bad Request" "On or off."; lines="ACTION='manual'
HIDE='$v'" ;;
    linkadd) n=$(decode "$(param name "$body")"); u=$(decode "$(param url "$body")"); g=$(decode "$(param group "$body")"); i=$(decode "$(param icon "$body")")
      [[ -n "$n" && ${#n} -le 60 ]] || error "400 Bad Request" "A name, up to 60 characters."
      [[ "$u" =~ ^https?://[^[:space:]\"\']{1,300}$ ]] || error "400 Bad Request" "An address starting with http:// or https://."
      (( ${#g} <= 40 )) || error "400 Bad Request" "A shorter group name."
      [[ -z "$i" || "$i" =~ ^[A-Za-z0-9._/-]{1,100}$ ]] || error "400 Bad Request" "An icon name like router.png or mdi-router."
      lines="ACTION='linkadd'
NAME_B64='$(b64u "$n")'
URL_B64='$(b64u "$u")'
GROUP_B64='$(b64u "$g")'
ICON_B64='$(b64u "$i")'" ;;
    look) t=$(decode "$(param title "$body")"); th=$(param theme "$body"); c=$(param color "$body"); s=$(param search "$body"); cl=$(param clock "$body")
      [[ -n "$t" && ${#t} -le 60 ]] || error "400 Bad Request" "A title, up to 60 characters."
      [[ "$th" =~ ^(dark|light)$ && "$c" =~ ^[a-z]{3,8}$ && "$s" =~ ^[01]$ && "$cl" =~ ^[01]$ ]] || error "400 Bad Request" "Pick a theme and a colour."
      lines="ACTION='look'
TITLE_B64='$(b64u "$t")'
THEME='$th'
COLOR='$c'
SEARCH='$s'
CLOCK='$cl'" ;;
    dsmtest|dsmset) u=$(decode "$(param user "$body")"); i=$(decode "$(param pass "$body")"); vol=$(param volume "$body")
      [[ -n "$u" && ${#u} -le 64 && ${#i} -le 200 ]] || error "400 Bad Request" "A DSM username."
      [[ "$vol" =~ ^(volume_[0-9]{1,2})?$ ]] || error "400 Bad Request" "A volume like volume_1, or empty."
      lines="ACTION='$a'
DSM_USER_B64='$(b64u "$u")'
DSM_PASS_B64='$(b64u "$i")'
DSM_VOLUME='$vol'" ;;
  esac
}
