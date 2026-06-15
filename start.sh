#!/bin/bash

echo "[INFO] Pod run-textgen started"
echo "ℹ️ Wait until the message 🎉 Provisioning done 🎉. is displayed"

# Hugging Face CLI output tuned for RunPod plain logs.
export NO_COLOR=1
export HF_HUB_VERBOSITY=warning
export HF_HUB_DISABLE_PROGRESS_BARS=1
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

# Start textgen (HTTP port 7860)

if [[ "$HAS_CUDA" -eq 1 ]]; then  	
    echo "✅ Gradio service starting (CUDA available)"

	cd /workspace/textgen/
	
	if [[ -n "$GRADIO_AUTH" ]]; then
       python3 server.py --gradio-auth "$GRADIO_AUTH" --listen &
	else
	   echo "⚠️ WARNING: GRADIO_AUTH (user:password) is not set as an environment variable"
	   python3 server.py --listen &
	fi
	
	sleep 5
	
	# Confirmation	
	echo "🎉 textgen started"
	
else
    echo "❌ ERROR: PyTorch CUDA driver mismatch or unavailable, Gradio not started"
fi

# --- Download helpers ---

download_model_HF_GGUF() {
  local model_var="$1" file_var="$2"
  local model="${!model_var:-}" file="${!file_var:-}"
  local target="/workspace/textgen/user_data/models"

  if [[ -n "$model" && -n "$file" ]]; then
    mkdir -p "$target"
    echo "ℹ️ [Download] GGUF model: $model ($file)"

    hf download "$model" "$file" --local-dir "$target"

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

    hf download "$model" "$file" --local-dir "$target"

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
    hf download "$model" "${args[@]}" --local-dir "$local_dir"
    sleep 1
  fi
}

download_EXL_HF() {
  local model_var="$1" revision_var="$2" dest_dir_var="$3"
  local model="${!model_var:-}" revision="${!revision_var:-}" dest_dir="${!dest_dir_var:-}"
  if [[ -n "$model" && -n "$revision" && -n "$dest_dir" ]]; then
    echo "ℹ️ [Download] EXL repo: $model (rev: $revision) -> $dest_dir"
    hf download "$model" --revision "$revision" --local-dir "/workspace/textgen/user_data/models/$dest_dir/"
    sleep 1
  fi
}

if [[ "$HAS_CUDA" -eq 1 ]]; then  

	echo "📥 Provisioning models HF"
	
	# GGUF (single files)
	for i in {1..6}; do
	  download_model_HF_GGUF "HF_MODEL_GGUF${i}" "HF_MODEL_GGUF_FILE${i}"
	done
	
	# mmproj (single files)
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
	
    HAS_PROVISIONING=1
else
    HAS_PROVISIONING=0   
    echo "⚠️ Skipped Provisioning: models downloaded as Gradio is not started"
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

