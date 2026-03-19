#!/bin/bash
set -uo pipefail

CONFIG_FILE="./vm_clone.conf"

#Important note: The powershell scripts that you want to use with this script have to be modified with the below commented out code at the very end of the script. This line of code signals to the bash script that the script is completed and that the VM should be restarted.
#New-Item -ItemType File -Path "C:\automation\yourpowershellscriptfilename.ps1.done" -Force | Out-Null
#Once again, the above code should be added at the end of your powershell scripts. This line is supposed to be the last thing to be executed. AND YOUR POWERSHELL SCRITPS ARE NOT TO REBOOT BY THEMSELVES! The bash script will do all of the rebooting for them.  
#Also make sure that all powershell scripts have the same name everywhere. 



# Wait until guest exec works again (post-boot readiness)
wait_for_exec_ready() {
  local VMID="$1"
  echo "[INFO] Waiting for VMID $VMID to accept guest exec..."

  while true; do
    if qm guest exec "$VMID" -- cmd.exe /c exit 0 &>/dev/null; then
      echo "[INFO] Guest exec available on VMID $VMID"
      break
    fi
    echo "[INFO] guest exec not available yet, retrying in 5s..."
    sleep 5
  done
}

# Wait until a marker file exists inside the guest
wait_for_marker() {
  local VMID="$1"
  local MARKER="$2"

  echo "[INFO] Waiting for marker file: $MARKER"
  #weird shit going on with the powershell command, set it back to just -- powershell like in the other functions if it doesn't work. This is supposed to fix a very confusing problem that I encountered only once. I am not sure if it will. 
  while true; do
    OUTPUT=$(qm guest exec "$VMID" -- "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" \
    -NoProfile -Command "
      if (Test-Path '$MARKER') { Write-Output 'MARKER_PRESENT' }
    " 2>/dev/null || true)

    if echo "$OUTPUT" | grep -q "MARKER_PRESENT"; then
      echo "[INFO] Marker detected"
      break
    fi

    echo "[INFO] Marker not present yet, retrying..."
    sleep 5
  done

}

# Run provisioning script, wait for marker, then reboot deterministically
run_script_with_marker_handling() {
  local VMID="$1"
  local SCRIPT_NAME="$2"
  local SCRIPT_URL="$3"
  local SCRIPT_DIR="$4"
  
  

  local DEST="$SCRIPT_DIR\\$SCRIPT_NAME"
  local MARKER="$SCRIPT_DIR\\$SCRIPT_NAME.done"

  echo "[INFO] Waiting for system to be ready before running provisioning phase... (checking uptime) "
  #sleep 60  #This is going to help me avoid "Applying computer settings" screens. I am fully aware that this is unreliable, but making a check for this is rather impractical. Anyway, sleep > actually using brainpower to code a check.
  
  

  sleep 15 #buffer sleep in order to ensure that the uptime check below runs smoothly. Not sleep spamming! 
  #this thing runs a powershell command that returns the uptime as well as the exit codes in json format. The exit codes are irrelevant, so we extract the last number present, it being exactly what we require. Afterwards it echoes out the uptime and checks whether it's larger than a set number. If it is, the loop breaks, and if it's not, the loop continues.
  while true; do

    OUTPUT=$(qm guest exec "$VMID" -- powershell -NoProfile -Command \
      "(Get-Counter '\System\System Up Time').CounterSamples[0].CookedValue" \
      2>/dev/null)

    # Extract the LAST floating-point number from the JSON output
    UPTIME=$(echo "$OUTPUT" | grep -o '[0-9]\+\(\.[0-9]\+\)\?' | tail -n1)

    if [ -n "$UPTIME" ]; then
      UPTIME_INT=${UPTIME%.*}

      echo "[INFO] Current uptime: $UPTIME_INT seconds"

      if [ "$UPTIME_INT" -ge 60 ]; then
        break
      fi
    fi

    sleep 5
  done



  echo "[INFO] Running provisioning phase: $SCRIPT_NAME"
  # Fire-and-forget script execution
  qm guest exec "$VMID" -- powershell -NoProfile -ExecutionPolicy Bypass -Command "
    New-Item -ItemType Directory -Force -Path '$SCRIPT_DIR' | Out-Null
    Invoke-WebRequest -Uri '$SCRIPT_URL' -OutFile '$DEST' -UseBasicParsing
    & '$DEST'
  " &>/dev/null || true

  echo "[INFO] Downloaded and ran the powershell script..."

  # Wait until the script itself declares success
  wait_for_marker "$VMID" "$MARKER"

  echo "[INFO] Marker present, initiating controlled reboot..."

  # Trigger reboot explicitly (deterministic timing)
  qm guest exec "$VMID" -- powershell -Command "Restart-Computer -Force" &>/dev/null || true

  # Give the reboot a moment to start. This is needed. I am not spamming sleeps.
  sleep 30

  # Wait until guest exec works again
  wait_for_exec_ready "$VMID"

  echo "[INFO] Phase completed: $SCRIPT_NAME"
}


# Load and validate config

[[ -f "$CONFIG_FILE" ]] || { echo "Config file not found: $CONFIG_FILE"; exit 1; }
source "$CONFIG_FILE"

: "${TEMPLATE_VMID:?Missing TEMPLATE_VMID}"
: "${CLONE_COUNT:?Missing CLONE_COUNT}"
: "${GUEST_SCRIPT_DIR:?Missing GUEST_SCRIPT_DIR}"

echo "[INFO] Starting provisioning of $CLONE_COUNT clone(s)..."


# Main loop


for ((i=1; i<=CLONE_COUNT; i++)); do
  CLONE_NAME_VALUE="${CLONE_NAME[$i]:-}"

  if [[ -z "$CLONE_NAME_VALUE" ]]; then
    echo "[!!!] Missing CLONE_NAME[$i], skipping"
    continue
  fi

  echo
  echo "[INFO] Creating clone $i/$CLONE_COUNT: $CLONE_NAME_VALUE"

  NEW_VMID=$(pvesh get /cluster/nextid)

  CLONE_CMD=(qm clone "$TEMPLATE_VMID" "$NEW_VMID" --name "$CLONE_NAME_VALUE" --full 1)
  [[ -n "${STORAGE:-}" ]] && CLONE_CMD+=(--storage "$STORAGE")

  "${CLONE_CMD[@]}"
  qm start "$NEW_VMID"


  wait_for_exec_ready "$NEW_VMID"

  SCRIPT_LIST="${CLONE_SCRIPTS[$i]:-}"

  if [[ -z "$SCRIPT_LIST" ]]; then
    echo "[!!!] No scripts defined for $CLONE_NAME_VALUE, skipping provisioning"
    continue
  fi
  
  #
  while read -r LINE; do
    [[ -z "$LINE" ]] && continue

    SCRIPT_NAME="${LINE%%|*}"
    SCRIPT_URL="${LINE#*|}"

    run_script_with_marker_handling "$NEW_VMID" "$SCRIPT_NAME" "$SCRIPT_URL" "$GUEST_SCRIPT_DIR"

  done <<< "$SCRIPT_LIST"
  #

  echo "[SUCCESS] Clone provisioned successfully: $CLONE_NAME_VALUE (VMID $NEW_VMID)"
done

echo
echo "[SUCCESS] All clone provisioning completed successfully"