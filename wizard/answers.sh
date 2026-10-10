    echo "HP_TITLE='$(printf '%s' "${wizard_hp_title:-My Synology}" | tr -cd 'A-Za-z0-9 _-' | sed 's/^ *//; s/ *$//' | tr -s ' ' '+' | head -c 60)'"
