#!/bin/bash

echo "[INFO] Pod run-textgen started"
echo "ℹ️ Wait until the message 🎉 Provisioning done 🎉. is displayed"

# Hugging Face CLI output tuned for RunPod plain logs.
export NO_COLOR=1
export HF_HUB_VERBOSITY=warning
export HF_HUB_DISABLE_PROGRESS_BARS=0
export HF_HUB_DISABLE_TELEMETRY=1
export DO_NOT_TRACK=1
export HF_HUB_DISABLE_UPDATE_CHECK=1

# Enable SSH if PUBLIC_KEY is set
if [[ -n "$PUBLIC_KEY" ]]; then
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    service ssh start
    echo "✅ [SSH enabled]"
fi

# Export env variables
if [[ -n "${RUNPOD_GPU_COUNT:-}" ]]; then
   echo "ℹ️ Exporting runpod.io environment variables..."
   printenv | grep -E '^RUNPOD_|^PATH=|^_=' \
     | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment

   echo 'source /etc/rp_environment' >> ~/.bashrc
fi

# Move necessary files to workspace
echo "ℹ️ [Moving necessary files to workspace] enabling rebooting pod without data loss"
for script in textgen-on-workspace.sh readme-on-workspace.sh; do
    if [ -f "/$script" ]; then
        echo "Executing $script..."
        "/$script"
    else
        echo "⚠️ WARNING: Skipping $script (not found)"
    fi
done

# GPU detection
echo "ℹ️ Testing GPU/CUDA provisioning"

# GPU detection Runpod.io
HAS_GPU_RUNPOD=0
if [[ -n "${RUNPOD_GPU_COUNT:-}" && "${RUNPOD_GPU_COUNT:-0}" -gt 0 ]]; then
  HAS_GPU_RUNPOD=1
  echo "✅ [GPU DETECTED] Found via RUNPOD_GPU_COUNT=${RUNPOD_GPU_COUNT}"
else
  echo "⚠️ [NO GPU] No Runpod.io GPU detected."
fi  

# GPU detection nvidia-smi
HAS_GPU=0
if command -v nvidia-smi >/dev/null 2>&1; then
  if nvidia-smi >/dev/null 2>&1; then
    HAS_GPU=1
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | xargs | sed 's/,/, /g')
    echo "✅ [GPU DETECTED] Found via nvidia-smi → Model(s): ${GPU_MODEL}"
  else
    echo "⚠️ [NO GPU] nvidia-smi found but failed to run (driver or permission issue)"
  fi
else
  echo "⚠️ [NO GPU] No GPU found via nvidia-smi"
fi

# Start code-server (HTTP port 9000) 
if [[ "$HAS_GPU" -eq 1 || "$HAS_GPU_RUNPOD" -eq 1 ]]; then    
    echo "✅ Code-Server service starting"
	
    if [[ -n "$PASSWORD" ]]; then
        code-server /workspace --auth password --disable-update-check --disable-telemetry --host 0.0.0.0 --bind-addr 0.0.0.0:9000 &
    else
        echo "⚠️ PASSWORD is not set as an environment. Password file: /root/.config/code-server/config.yaml"
        code-server /workspace --disable-telemetry --disable-update-check --host 0.0.0.0 --bind-addr 0.0.0.0:9000 &
    fi
	
    echo "🎉 code-server service started"
else
    echo "⚠️ WARNING: No GPU available, Code Server not started to limit memory use"
fi

# Python, Torch CUDA check
HAS_CUDA=0
if command -v python >/dev/null 2>&1; then
  if python - << 'PY' >/dev/null 2>&1
import sys
try:
    import torch
    sys.exit(0 if torch.cuda.is_available() else 1)
except Exception:
    sys.exit(1)
PY
  then
    HAS_CUDA=1
  fi
else
  echo "⚠️ Python not found – assuming no CUDA"
fi

# --- Download helpers ---

run_hf_download() {
    local stall_timeout="${HF_DOWNLOAD_STALL_TIMEOUT:-300}"
    local kill_after="${HF_DOWNLOAD_KILL_AFTER:-30}"
    local hf_command
    local hf_dry_run_command
    local dry_run_output
    local total_size_value
    local total_size_unit
    local total_bytes=0
    local tmp_dir
    local fifo
    local pid
    local watchdog_pid
    local progress_pid
    local last_activity_file
    local activity_tmp_file
    local progress_activity_tmp_file
    local exit_code
    local download_dir=""
    local -a download_args=("$@")
    local arg_index

    for ((arg_index = 0; arg_index < ${#download_args[@]}; arg_index++)); do
        if [[ "${download_args[arg_index]}" == "--local-dir" ]] \
           && (( arg_index + 1 < ${#download_args[@]} )); then
            download_dir="${download_args[arg_index + 1]}"
            break
        fi
    done

    echo "ℹ️ [DOWNLOAD] Stall watchdog: ${stall_timeout}s"
    echo "ℹ️ [DOWNLOAD] Kill grace period: ${kill_after}s"

    # Safely quote all arguments passed to: hf download. Force human output so
    # progress remains enabled when captured through the pseudo-terminal.
    printf -v hf_command '%q ' hf download --format human "$@"

    # Determine the selected download size without transferring model data.
    printf -v hf_dry_run_command '%q ' hf download --dry-run --format human "$@"
    dry_run_output="$(eval "$hf_dry_run_command" 2>&1 || true)"
    if [[ "$dry_run_output" =~ totalling[[:space:]]+([0-9]+([.][0-9]+)?)([KMGTPE]?) ]]; then
        total_size_value="${BASH_REMATCH[1]}"
        total_size_unit="${BASH_REMATCH[3]}"
        total_bytes="$(awk -v value="$total_size_value" -v unit="$total_size_unit" '
            BEGIN {
                exponent = index("KMGTPE", unit)
                multiplier = 1
                for (i = 0; i < exponent; i++) multiplier *= 1000
                printf "%.0f", value * multiplier
            }
        ')"
        printf 'ℹ️ [DOWNLOAD] Total size: %.2f GB\n' "$(awk -v bytes="$total_bytes" 'BEGIN { print bytes / 1000000000 }')"
    else
        echo "⚠️ [DOWNLOAD] Total size could not be determined; continuing download."
    fi

    tmp_dir="$(mktemp -d)"
    fifo="${tmp_dir}/hf-output.fifo"
    last_activity_file="${tmp_dir}/last_activity"
    activity_tmp_file="${tmp_dir}/last_activity.tmp"
    progress_activity_tmp_file="${tmp_dir}/last_activity.progress.tmp"

    mkfifo "$fifo"
    date +%s > "$activity_tmp_file"
    mv -f "$activity_tmp_file" "$last_activity_file"

    cleanup() {
        [[ -n "${watchdog_pid:-}" ]] && kill "$watchdog_pid" 2>/dev/null || true
        [[ -n "${progress_pid:-}" ]] && kill "$progress_pid" 2>/dev/null || true
        [[ -n "${pid:-}" ]] && kill "$pid" 2>/dev/null || true
        rm -rf "$tmp_dir"
    }

    trap cleanup RETURN

    run_download_attempt() {
        local disable_xet="$1"
        local backend_name="$2"

        date +%s > "$activity_tmp_file"
        mv -f "$activity_tmp_file" "$last_activity_file"

        echo "ℹ️ [DOWNLOAD] Starting with ${backend_name}..."

        (
            script --quiet --return --flush \
                --command "HF_HUB_DISABLE_XET=${disable_xet} ${hf_command}" \
                /dev/null
        ) >"$fifo" 2>&1 &

        pid=$!

        # Xet does not always emit progress when output is captured. Report
        # growth of the destination and use only real byte growth as activity.
        if [[ -n "$download_dir" ]]; then
            (
                local baseline_bytes
                local previous_bytes
                local current_bytes
                local downloaded_bytes
                local downloaded_gb
                local speed_mbps
                local previous_sample_time
                local current_sample_time
                local elapsed_seconds
                local interval_bytes

                baseline_bytes="$(du -s -B1 "$download_dir" 2>/dev/null | awk '{print $1}')"
                baseline_bytes="${baseline_bytes:-0}"
                previous_bytes="$baseline_bytes"
                previous_sample_time="$(date +%s)"

                while kill -0 "$pid" 2>/dev/null; do
                    sleep 10
                    current_bytes="$(du -s -B1 "$download_dir" 2>/dev/null | awk '{print $1}')"
                    current_bytes="${current_bytes:-0}"
                    current_sample_time="$(date +%s)"

                    if (( current_bytes > previous_bytes )); then
                        downloaded_bytes=$((current_bytes - baseline_bytes))
                        interval_bytes=$((current_bytes - previous_bytes))
                        elapsed_seconds=$((current_sample_time - previous_sample_time))
                        (( elapsed_seconds < 1 )) && elapsed_seconds=1
                        downloaded_gb="$(awk -v bytes="$downloaded_bytes" 'BEGIN { printf "%.2f", bytes / 1000000000 }')"
                        speed_mbps="$(awk -v bytes="$interval_bytes" -v seconds="$elapsed_seconds" 'BEGIN { printf "%.1f", bytes / seconds / 1000000 }')"
                        if (( total_bytes > 0 )); then
                            printf '⬇️ [DOWNLOAD] Progress: %s / %.2f GB | %s MB/s\n' \
                                "$downloaded_gb" \
                                "$(awk -v bytes="$total_bytes" 'BEGIN { print bytes / 1000000000 }')" \
                                "$speed_mbps"
                        else
                            printf '⬇️ [DOWNLOAD] Progress: %s GB downloaded | %s MB/s\n' \
                                "$downloaded_gb" "$speed_mbps"
                        fi
                        date +%s > "$progress_activity_tmp_file"
                        mv -f "$progress_activity_tmp_file" "$last_activity_file"
                    else
                        echo "ℹ️ [DOWNLOAD] Waiting for transfer progress..."
                    fi

                    previous_bytes="$current_bytes"
                    previous_sample_time="$current_sample_time"
                done
            ) &
            progress_pid=$!
        fi

        (
            while kill -0 "$pid" 2>/dev/null; do
                sleep 10

                local now
                local last
                local inactive

                now="$(date +%s)"
                last="$(cat "$last_activity_file" 2>/dev/null || true)"

                if [[ ! "$last" =~ ^[0-9]+$ ]] || (( last > now )); then
                    continue
                fi

                inactive=$((now - last))

                if (( inactive >= stall_timeout )); then
                    echo
                    echo "⚠️ [DOWNLOAD] No activity for ${inactive}s."
                    echo "⚠️ [DOWNLOAD] ${backend_name} appears stalled."

                    kill -TERM "$pid" 2>/dev/null || true
                    sleep "$kill_after"

                    if kill -0 "$pid" 2>/dev/null; then
                        echo "⚠️ [DOWNLOAD] Process did not stop after ${kill_after}s; sending SIGKILL."
                        kill -KILL "$pid" 2>/dev/null || true
                    fi

                    exit 124
                fi
            done
        ) &

        watchdog_pid=$!

        while IFS= read -r line; do
            date +%s > "$activity_tmp_file"
            mv -f "$activity_tmp_file" "$last_activity_file"
            printf '%s\n' "$line"
        done < <(
            stdbuf -oL tr '\r' '\n' <"$fifo" \
                | sed -u -E \
                    -e '/^[[:space:]]*$/d' \
                    -e $'s/\033\\[[0-9;?]*[ -\\/]*[@-~]//g' \
                    -e 's/^([^:]+):[[:space:]]*([0-9]+)%\|[^|]*\|[[:space:]]*([^[:space:]]+).*/Downloading \1 \2% \3/'
        )

        wait "$pid"
        exit_code=$?

        kill "$watchdog_pid" 2>/dev/null || true
        wait "$watchdog_pid" 2>/dev/null || true
        [[ -n "${progress_pid:-}" ]] && kill "$progress_pid" 2>/dev/null || true
        [[ -n "${progress_pid:-}" ]] && wait "$progress_pid" 2>/dev/null || true

        pid=""
        watchdog_pid=""
        progress_pid=""

        return "$exit_code"
    }

    if run_download_attempt 0 "Xet"; then
        echo "✅ [DOWNLOAD] Download completed successfully with Xet."
        return 0
    else
        exit_code=$?
    fi

    echo "⚠️ [DOWNLOAD] Xet download stopped or failed with exit code ${exit_code}."
    echo "ℹ️ [DOWNLOAD] Retrying with Xet disabled (plain HTTP)..."

    if run_download_attempt 1 "plain HTTP"; then
        echo "✅ [DOWNLOAD] Download completed successfully using plain HTTP."
        return 0
    else
        exit_code=$?
    fi

    echo "❌ [DOWNLOAD] Plain HTTP download failed with exit code ${exit_code}."
    return "$exit_code"
}

download_model_HF_GGUF() {
  local model_var="$1" file_var="$2"
  local model="${!model_var:-}" file="${!file_var:-}"
  local target="/workspace/textgen/user_data/models"

  if [[ -n "$model" && -n "$file" ]]; then
    mkdir -p "$target"
    echo "ℹ️ [Download] GGUF model: $model ($file)"

    run_hf_download "$model" "$file" --local-dir "$target"

    local src="$target/$file"
    local dst="$target/$(basename "$file")"

    if [[ -f "$src" && "$src" != "$dst" ]]; then
      mv -f "$src" "$dst"
      find "$target" -type d -empty -delete
    fi

    sleep 1
  fi
}

download_mmproj_HF_GGUF() {
  local model_var="$1" file_var="$2"
  local model="${!model_var:-}" file="${!file_var:-}"
  local target="/workspace/textgen/user_data/mmproj"

  if [[ -n "$model" && -n "$file" ]]; then
    mkdir -p "$target"
    echo "ℹ️ [Download] GGUF mmproj: $model ($file)"

    run_hf_download "$model" "$file" --local-dir "$target"

    local src="$target/$file"
    local dst="$target/$(basename "$file")"

    if [[ -f "$src" && "$src" != "$dst" ]]; then
      mv -f "$src" "$dst"
      find "$target" -type d -empty -delete
    fi

    sleep 1
  fi
}

download_model_HF() {
  local model_var="$1" dest_dir_var="$2" include_var="${3:-}" exclude_var="${4:-}"
  local model="${!model_var:-}" dest_dir="${!dest_dir_var:-}" include="" exclude=""
  [[ -n "$include_var" ]] && include="${!include_var:-}"
  [[ -n "$exclude_var" ]] && exclude="${!exclude_var:-}"

  if [[ -n "$model" && ( -n "$dest_dir" || -n "$include" || -n "$exclude" ) ]]; then
    local local_dir="/workspace/textgen/user_data/models/"
    [[ -n "$dest_dir" ]] && local_dir="${local_dir}${dest_dir}/"

    local args=()
    echo "ℹ️ [Download] model repo: $model -> $local_dir"
    if [[ -n "$include" ]]; then
      echo "ℹ️ [Download] include filter: $include"
      args+=(--include "$include")
    fi
    if [[ -n "$exclude" ]]; then
      echo "ℹ️ [Download] exclude filter: $exclude"
      args+=(--exclude "$exclude")
    fi
    run_hf_download "$model" "${args[@]}" --local-dir "$local_dir"
    sleep 1
  fi
}

download_EXL_HF() {
  local model_var="$1" revision_var="$2" dest_dir_var="$3"
  local model="${!model_var:-}" revision="${!revision_var:-}" dest_dir="${!dest_dir_var:-}"
  if [[ -n "$model" && -n "$revision" && -n "$dest_dir" ]]; then
    echo "ℹ️ [Download] EXL repo: $model (rev: $revision) -> $dest_dir"
    run_hf_download "$model" --revision "$revision" --local-dir "/workspace/textgen/user_data/models/$dest_dir/"
    sleep 1
  fi
}

get_max_vram_gib() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo 0
    return
  fi

  nvidia-smi \
    --query-gpu=memory.total \
    --format=csv,noheader,nounits \
    | awk 'BEGIN{m=0} {if($1>m) m=$1} END{print int(m/1024)}'
}

select_textgen_startup_model() {
  TEXTGEN_STARTUP_MODEL="${TEXTGEN_MODEL:-}"
  TEXTGEN_STARTUP_MMPROJ="${TEXTGEN_MMPROJ:-}"

  # An explicit model always wins. Automatic selection can be disabled while
  # retaining the option to start an explicitly named model.
  if [[ -n "$TEXTGEN_STARTUP_MODEL" || "${TEXTGEN_AUTOLOAD_MODEL:-1}" == "0" ]]; then
    return
  fi

  local i
  local model_var
  local mmproj_var
  local model_file
  local mmproj_file

  # Prefer the profile selected from the detected VRAM. Keep the model and its
  # multimodal projector paired by their numeric index.
  if [[ -n "${HF_VRAM_PREFIX:-}" ]]; then
    for i in {1..6}; do
      model_var="${HF_VRAM_PREFIX}GGUF_FILE${i}"
      mmproj_var="${HF_VRAM_PREFIX}MMPROJ_GGUF_FILE${i}"
      model_file="${!model_var:-}"

      if [[ -n "$model_file" ]]; then
        TEXTGEN_STARTUP_MODEL="$(basename "$model_file")"
        mmproj_file="${!mmproj_var:-}"
        if [[ -z "$TEXTGEN_STARTUP_MMPROJ" && -n "$mmproj_file" ]]; then
          TEXTGEN_STARTUP_MMPROJ="$(basename "$mmproj_file")"
        fi
        echo "ℹ️ textgen startup model selected from ${model_var}"
        return
      fi
    done
  fi

  # Fall back to the first VRAM-independent GGUF model.
  for i in {1..6}; do
    model_var="HF_MODEL_GGUF_FILE${i}"
    mmproj_var="HF_MMPROJ_GGUF_FILE${i}"
    model_file="${!model_var:-}"

    if [[ -n "$model_file" ]]; then
      TEXTGEN_STARTUP_MODEL="$(basename "$model_file")"
      mmproj_file="${!mmproj_var:-}"
      if [[ -z "$TEXTGEN_STARTUP_MMPROJ" && -n "$mmproj_file" ]]; then
        TEXTGEN_STARTUP_MMPROJ="$(basename "$mmproj_file")"
      fi
      echo "ℹ️ textgen startup model selected from ${model_var}"
      return
    fi
  done

  # Full Transformers and EXL repositories are loaded by their destination
  # directory name.
  for i in {1..6}; do
    model_var="HF_MODEL_DIR${i}"
    if [[ -n "${!model_var:-}" ]]; then
      TEXTGEN_STARTUP_MODEL="${!model_var}"
      echo "ℹ️ textgen startup model selected from ${model_var}"
      return
    fi
  done

  for i in {1..6}; do
    model_var="HF_EXL_DIR${i}"
    if [[ -n "${!model_var:-}" ]]; then
      TEXTGEN_STARTUP_MODEL="${!model_var}"
      echo "ℹ️ textgen startup model selected from ${model_var}"
      return
    fi
  done
}

start_textgen() {
  local models_dir="/workspace/textgen/user_data/models"
  local mmproj_dir="/workspace/textgen/user_data/mmproj"
  local model_path=""
  local mmproj_path=""
  local -a textgen_args=(--listen)

  select_textgen_startup_model

  if [[ -n "${GRADIO_AUTH:-}" ]]; then
    textgen_args+=(--gradio-auth "$GRADIO_AUTH")
  else
    echo "⚠️ WARNING: GRADIO_AUTH (user:password) is not set as an environment variable"
  fi

  if [[ -n "$TEXTGEN_STARTUP_MODEL" ]]; then
    model_path="$TEXTGEN_STARTUP_MODEL"
    [[ "$model_path" != /* ]] && model_path="${models_dir}/${model_path}"

    if [[ -e "$model_path" ]]; then
      textgen_args+=(--model "$TEXTGEN_STARTUP_MODEL")
      echo "✅ textgen will load model: ${TEXTGEN_STARTUP_MODEL}"

      if [[ -n "$TEXTGEN_STARTUP_MMPROJ" ]]; then
        mmproj_path="$TEXTGEN_STARTUP_MMPROJ"
        [[ "$mmproj_path" != /* ]] && mmproj_path="${mmproj_dir}/${mmproj_path}"

        if [[ -f "$mmproj_path" ]]; then
          textgen_args+=(--mmproj "$mmproj_path")
          echo "✅ textgen will load mmproj: ${mmproj_path}"
        else
          echo "⚠️ Configured mmproj not found: ${mmproj_path}; starting without --mmproj"
        fi
      fi
    else
      echo "⚠️ Configured startup model not found: ${model_path}; starting without --model"
    fi
  else
    echo "ℹ️ No startup model configured; textgen will start without loading a model"
  fi

  echo "▶️ Gradio service starting (CUDA available)"
  cd /workspace/textgen/ || return 1
  python3 server.py "${textgen_args[@]}" &
  TEXTGEN_PID=$!

  sleep 5
  if kill -0 "$TEXTGEN_PID" 2>/dev/null; then
    echo "🎉 textgen started"
    return 0
  fi

  echo "❌ ERROR: textgen stopped during startup"
  return 1
}

if [[ "$HAS_CUDA" -eq 1 ]]; then  

	echo "📥 Provisioning models HF"

	MAX_VRAM_GIB="$(get_max_vram_gib)"
	VRAM_THRESHOLD="${VRAM_THRESHOLD:-36}"

	if (( MAX_VRAM_GIB > VRAM_THRESHOLD )); then
	  HF_VRAM_PREFIX="HF_MODEL_HVRAM_"
	  echo "🟢 High VRAM detected (${MAX_VRAM_GIB} GB > ${VRAM_THRESHOLD} GB via VRAM_THRESHOLD)"
	else
	  HF_VRAM_PREFIX="HF_MODEL_LVRAM_"
	  echo "🟡 Low VRAM detected (${MAX_VRAM_GIB} GB <= ${VRAM_THRESHOLD} GB via VRAM_THRESHOLD)"
	fi

	# VRAM-dependent GGUF files. Only the selected HVRAM or LVRAM profile is
	# downloaded; the generic variables below remain VRAM-independent.
	for i in {1..6}; do
	  download_model_HF_GGUF "${HF_VRAM_PREFIX}GGUF${i}" "${HF_VRAM_PREFIX}GGUF_FILE${i}"
	done

	# VRAM-dependent multimodal projectors.
	for i in {1..6}; do
	  download_mmproj_HF_GGUF "${HF_VRAM_PREFIX}MMPROJ_GGUF${i}" "${HF_VRAM_PREFIX}MMPROJ_GGUF_FILE${i}"
	done
	
	# VRAM-independent GGUF files.
	for i in {1..6}; do
	  download_model_HF_GGUF "HF_MODEL_GGUF${i}" "HF_MODEL_GGUF_FILE${i}"
	done
	
	# VRAM-independent multimodal projectors.
	for i in {1..6}; do
	  download_mmproj_HF_GGUF "HF_MMPROJ_GGUF${i}" "HF_MMPROJ_GGUF_FILE${i}"
	done
	
	# Full repos (into subdirs)
	for i in {1..6}; do
	  download_model_HF "HF_MODEL${i}" "HF_MODEL_DIR${i}" "HF_MODEL_INCLUDE${i}" "HF_MODEL_EXCLUDE${i}"
	done
	
	# EXL repos with explicit revision
	for i in {1..6}; do
	  download_EXL_HF "HF_EXL${i}" "HF_EXL_REVISION${i}" "HF_EXL_DIR${i}"
	done

    if start_textgen; then
      HAS_PROVISIONING=1
    else
      HAS_PROVISIONING=0
    fi
else
    HAS_PROVISIONING=0   
    echo "⚠️ Skipped provisioning and textgen startup: CUDA is unavailable"
fi

python - <<'PY'
import torch, platform, triton, os
print(f"Python: {platform.python_version()}")
print(f"PyTorch: {torch.__version__}")
print(f"Triton version: {triton.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"  ↳ CUDA runtime: {torch.version.cuda}")
    print(f"  ↳ GPU(s): {[torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())]}")
    print(f"  ↳ cuDNN: {torch.backends.cudnn.version()}")
    print(f"Torch build info: {torch.__config__.show()}")
PY

if [[ "$HAS_PROVISIONING" -eq 1 ]]; then 
    echo "🎉 Provisioning done 🎉"
		
	if [[ "$HAS_GPU_RUNPOD" -eq 1 ]]; then
	  echo "ℹ️ Connect to the following services from console menu or url"
	
	  if [[ -z "${RUNPOD_POD_ID:-}" ]]; then
	    echo "⚠️ RUNPOD_POD_ID not set — service URLs unavailable"
	  else
	    declare -A SERVICES=(
	      ["Code-Server"]=9000
	      ["textgen"]=7860
	    )
	
	    # Local health checks (inside the pod)
	    for service in "${!SERVICES[@]}"; do
	      port="${SERVICES[$service]}"
	      url="https://${RUNPOD_POD_ID}-${port}.proxy.runpod.net/"
	      local_url="http://127.0.0.1:${port}/"
	
	      echo "👉 🔗 Service ${service} : ${url}"
	
	      # Check service locally (no proxy dependency)
	      http_code="$(curl -sS -o /dev/null -m 2 --connect-timeout 1 -w "%{http_code}" "$local_url" || true)"
	
	      # Treat common “service is up but protected/redirect” codes as UP
	      if [[ "$http_code" =~ ^(200|301|302|401|403|404)$ ]]; then
	        echo "✅ ${service} is running (local ${local_url}, HTTP ${http_code})"
	      else
	        echo "❌ ${service} not responding yet (local ${local_url}, HTTP ${http_code})"
	      fi
	    done
	  fi
	fi
	
    if [[ -n "$PASSWORD" ]]; then
		echo "ℹ️ Code-Server login use PASSWORD set as env"
	else 
		echo "⚠️ Code-Server password not provided via env (PASSWORD) use generated."
		cat /root/.config/code-server/config.yaml        
    fi	
else
    echo "ℹ️ Running error diagnosis"

    if [[ "$HAS_GPU_RUNPOD" -eq 0 ]]; then
        echo "⚠️ Pod started without a runpod GPU"
    fi

    if [[ "$HAS_CUDA" -eq 0 ]]; then
        echo "❌ Pytorch CUDA driver error/mismatch/not available"
        if [[ "$HAS_GPU_RUNPOD" -eq 1 ]]; then
            echo "⚠️ [SOLUTION] Deploy pod on another region ⚠️"
        fi
    fi
fi

# Keep the container running
echo "ℹ️ End script"
exec sleep infinity

