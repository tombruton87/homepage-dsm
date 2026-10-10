# Homepage's CGI checks (sourced by chassis/tests/test-api.sh).
expect "linkadd good" 202 "$(post "$me" linkadd 'action=linkadd&name=Router&url=http%3A%2F%2F192.168.1.1&group=Network&icon=router.png')"; rm -f "$CHASSIS_VAR/request"
expect "linkadd bad url" 400 "$(post "$me" linkadd 'action=linkadd&name=Router&url=javascript%3Aalert(1)')"
expect "linkadd bad icon" 400 "$(post "$me" linkadd 'action=linkadd&name=Router&url=http%3A%2F%2Fx&icon=%22%3E')"
expect "toggle good" 202 "$(post "$me" toggle 'action=toggle&item=ct%3Aweb&hide=1')"; request_is "toggle request" "ACTION='toggle'
ITEM='ct:web'
HIDE='1'
BY='$me'"
expect "toggle bad" 400 "$(post "$me" toggle 'action=toggle&item=ct%3Aweb%3B%20rm&hide=1')"
expect "look bad colour" 400 "$(post "$me" look 'action=look&title=x&theme=dark&color=%3Cb%3E&search=1&clock=1')"
