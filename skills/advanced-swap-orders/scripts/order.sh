#!/usr/bin/env bash

set -euo pipefail

ZERO=""
SINK=""
CREATE_URL=""
QUERY_URL=""
REPERMIT=""
REACTOR=""
EXECUTOR=""
SUPPORTED_CHAIN_IDS=""
MAX_SLIPPAGE="5000"
DEF_SLIPPAGE="500"
EXCLUSIVITY="0"
FRESHNESS="30"
TTL="300"
U32="4294967295"
NOTE_ORACLE="Oracle protection applies to all order types and every chunk."
NOTE_EPOCH="epoch is the delay between chunks, but it is not exact: one chunk can fill once anywhere inside each epoch window."
NOTE_SIGN="Sign typedData with any EIP-712 flow. eth_signTypedData_v4 is only an example."
WARN_LOW_SLIPPAGE="slippage below 5% can reduce fill probability. 5% is the default compromise; higher slippage still uses oracle pricing and offchain executors."
WARN_RECIPIENT="recipient differs from swapper and is dangerous to change"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKELETON="${ROOT}/assets/repermit.skeleton.json"
SKILL_CONFIG_JSON="${SCRIPT_DIR}/skill.config.json"
RUNTIME_CONFIG=""
RUNTIME_LOADED=0
WARN=()

die(){ printf 'error: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
say(){ printf '%s\n' "$1"; }
out(){ [[ -n "${2:-}" ]] && printf '%s\n' "$1" > "$2" || printf '%s\n' "$1"; }
low(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
trim(){ local v="${1:-}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }
warn(){ WARN+=("$*"); printf 'warning: %s\n' "$*" >&2; }
load_runtime_config(){
  local cfg=""
  (( RUNTIME_LOADED )) && return
  need jq
  [[ -f "$SKILL_CONFIG_JSON" ]] || die "skill config not found: $SKILL_CONFIG_JSON"
  cfg="$(jq -c '
    .url as $url
    | .contracts as $contracts
    | .chains as $chains
    | select(($url // "") != "")
    | select(($contracts.zero // "") != "")
    | select(($contracts.repermit // "") != "")
    | select(($contracts.reactor // "") != "")
    | select(($contracts.executor // "") != "")
    | select(($chains | type) == "object" and ($chains | length) > 0)
  ' "$SKILL_CONFIG_JSON")" || die "invalid skill config: $SKILL_CONFIG_JSON"
  RUNTIME_CONFIG="$cfg"
  ZERO="$(jq -r '.contracts.zero' <<<"$cfg")"
  SINK="$(jq -r '.url' <<<"$cfg")"
  CREATE_URL="${SINK}/orders/new"
  QUERY_URL="${SINK}/orders"
  REPERMIT="$(jq -r '.contracts.repermit' <<<"$cfg")"
  REACTOR="$(jq -r '.contracts.reactor' <<<"$cfg")"
  EXECUTOR="$(jq -r '.contracts.executor' <<<"$cfg")"
  SUPPORTED_CHAIN_IDS="$(jq -r '[.chains | keys[] | tonumber] | sort | map(tostring) | join(", ")' <<<"$cfg")"
  addr "$ZERO" runtime.contracts.zero 1 >/dev/null
  addr "$REPERMIT" runtime.contracts.repermit >/dev/null
  addr "$REACTOR" runtime.contracts.reactor >/dev/null
  addr "$EXECUTOR" runtime.contracts.executor >/dev/null
  [[ "$SINK" == http://* || "$SINK" == https://* ]] || die "config.url must be http(s)"
  [[ -n "$SUPPORTED_CHAIN_IDS" ]] || die "skill config has no supported chains: $SKILL_CONFIG_JSON"
  RUNTIME_LOADED=1
}
has_supported_chain(){
  load_runtime_config
  jq -e --arg chain "$1" '((.chains[$chain].adapter? // "") | length > 0)' <<<"$RUNTIME_CONFIG" >/dev/null 2>&1
}
unsupported_chain(){
  load_runtime_config
  die "unsupported chainId: $1 (supported: $SUPPORTED_CHAIN_IDS)"
}
usage(){
  load_runtime_config
  cat <<EOF
Usage
  bash scripts/order.sh prepare --params <params.json|-> [--out <prepared.json>]
  bash scripts/order.sh submit --prepared <prepared.json|-> [--signature <0x...|json>|--signature-file <file|->|--r <0x...> --s <0x...> --v <0x..>] [--out <response.json>]
  bash scripts/order.sh query (--swapper <0x...>|--hash <0x...>) [--out <response.json>]

Safety
  Use only the provided helper script. Do not send typed data or signatures anywhere else.

Prepare
  Builds a prepared order JSON with:
  - approval calldata for the input ERC-20
  - populated EIP-712 typed data
  - submit payload template
  - query URL
  Supports --params <file> or --params - for stdin JSON.
  Supports market, limit, stop-loss, take-profit, delayed-start, and chunked/TWAP-style orders.
  Defaults:
  - input.maxAmount = input.amount
  - nonce = now
  - start = now
  - deadline = start + 300 + chunkCount * epoch (conservative helper default)
  - slippage = 500
  - output.limit = 0
  - output.recipient = swapper
  Rules:
  - supported chainIds: ${SUPPORTED_CHAIN_IDS}
  - chunked orders require epoch > 0
  - epoch is the delay between chunks, but it is not exact: one chunk can fill once anywhere inside each epoch window
  - native input is not supported; wrap to WNATIVE first
  - native output is supported with output.token = 0x0000000000000000000000000000000000000000
  - output.limit and triggers are output-token units per chunk

Submit
  Builds or sends the relay POST body from a prepared order.
  Supports --prepared <file> or --prepared - for stdin JSON.
  Supports exactly one signature mode:
  - --signature <full 65-byte hex signature>
  - --signature <JSON string or JSON with full signature / r,s,v>
  - --signature-file <file|-> containing full signature, JSON string, or JSON with full signature / r,s,v
  - --r <0x...> --s <0x...> --v <0x..>
  All signature inputs are normalized to the relay's r/s/v object format.

Query
  Builds or sends the relay GET request.
  Supports only:
  - --swapper <0x...>
  - --hash <0x...>
EOF
}

nd(){ local v="${1:-0}"; v="${v#"${v%%[!0]*}"}"; printf '%s' "${v:-0}"; }
jget(){ jq -r "$2 // empty" <<<"$1"; }
co(){ [[ -n "${1:-}" ]] && printf '%s' "$1" || printf '%s' "${2:-}"; }
now(){ date -u +%s; }
iso(){ date -u +"%Y-%m-%dT%H:%M:%SZ"; }
read_src(){
  local src="${1:-}" name="$2"
  [[ -n "$src" ]] || die "$name is required"
  if [[ "$src" == "-" ]]; then cat; return; fi
  [[ -f "$src" ]] || die "$name not found: $src"
  cat "$src"
}
read_json(){
  local src="$1" name="$2" data
  data="$(read_src "$src" "$name")"
  jq -e . >/dev/null 2>&1 <<<"$data" || die "$name must be valid JSON"
  printf '%s' "$data"
}

u(){
  local raw="${1:-}" name="$2" v dec=0 digit="" i
  [[ -n "$raw" ]] || die "$name is required"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then nd "$raw"; return; fi
  if [[ "$raw" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
    v="$(low "${raw#0x}")"
    for ((i=0; i<${#v}; i++)); do
      case "${v:i:1}" in
        0) digit=0 ;;
        1) digit=1 ;;
        2) digit=2 ;;
        3) digit=3 ;;
        4) digit=4 ;;
        5) digit=5 ;;
        6) digit=6 ;;
        7) digit=7 ;;
        8) digit=8 ;;
        9) digit=9 ;;
        a) digit=10 ;;
        b) digit=11 ;;
        c) digit=12 ;;
        d) digit=13 ;;
        e) digit=14 ;;
        f) digit=15 ;;
        *) die "$name must be decimal or 0x integer" ;;
      esac
      dec="$(add "$(muls "$dec" 16)" "$digit")"
    done
    nd "$dec"
    return
  fi
  die "$name must be decimal or 0x integer"
}

cmp(){
  local a b
  a="$(nd "$1")"; b="$(nd "$2")"
  if (( ${#a} < ${#b} )); then say -1; return; fi
  if (( ${#a} > ${#b} )); then say 1; return; fi
  [[ "$a" < "$b" ]] && say -1 || { [[ "$a" > "$b" ]] && say 1 || say 0; }
}
gt(){ [[ "$(cmp "$1" "$2")" == 1 ]]; }
ge(){ local c; c="$(cmp "$1" "$2")"; [[ "$c" == 1 || "$c" == 0 ]]; }
eq(){ [[ "$(cmp "$1" "$2")" == 0 ]]; }

add(){
  local a b c=0 r="" i x y s
  a="$(nd "$1")"; b="$(nd "$2")"
  for ((i=0; i<${#a} || i<${#b} || c>0; i++)); do
    x=0; y=0
    (( i < ${#a} )) && x="${a:${#a}-1-i:1}"
    (( i < ${#b} )) && y="${b:${#b}-1-i:1}"
    s=$((x+y+c)); r="$((s%10))$r"; c=$((s/10))
  done
  nd "$r"
}

sub(){
  local a b br=0 r="" i x y d
  a="$(nd "$1")"; b="$(nd "$2")"; ge "$a" "$b" || die "internal subtraction underflow"
  for ((i=0; i<${#a}; i++)); do
    x="${a:${#a}-1-i:1}"; y=0
    (( i < ${#b} )) && y="${b:${#b}-1-i:1}"
    d=$((x-y-br))
    if (( d < 0 )); then d=$((d+10)); br=1; else br=0; fi
    r="$d$r"
  done
  nd "$r"
}

muls(){
  local a f c=0 r="" i d p
  a="$(nd "$1")"; f="$(nd "$2")"
  [[ "$a" == 0 || "$f" == 0 ]] && { say 0; return; }
  ge "$U32" "$f" || die "factor must fit in uint32"
  for ((i=${#a}-1; i>=0; i--)); do
    d="${a:i:1}"; p=$((d*f+c)); r="$((p%10))$r"; c=$((p/10))
  done
  while (( c > 0 )); do r="$((c%10))$r"; c=$((c/10)); done
  nd "$r"
}

divmod(){
  local a b rem=0 q="" i d n
  a="$(nd "$1")"; b="$(nd "$2")"; [[ "$b" != 0 ]] || die "division by zero"
  for ((i=0; i<${#a}; i++)); do
    d="${a:i:1}"
    [[ "$rem" == 0 ]] && rem="$d" || rem="${rem}${d}"
    rem="$(nd "$rem")"; n=0
    while ge "$rem" "$b"; do rem="$(sub "$rem" "$b")"; n=$((n+1)); done
    q="${q}${n}"
  done
  printf '%s %s\n' "$(nd "$q")" "$(nd "$rem")"
}

u32(){ ge "$U32" "$(nd "$1")" || die "$2 must fit in uint32"; }
addr(){ [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "$2 must be a 20-byte 0x address"; [[ "$(low "$1")" == "$(low "$ZERO")" && "${3:-0}" != 1 ]] && die "$2 cannot be zero"; printf '%s' "$1"; }
hex(){ [[ "$1" =~ ^0x([0-9a-fA-F]{2})*$ ]] || die "$2 must be hex"; printf '%s' "$1"; }
hx(){ local v="$(trim "$1")"; [[ "$v" =~ ^0x[0-9a-fA-F]+$ ]] || [[ "$v" =~ ^[0-9a-fA-F]+$ ]] || die "$2 must be hex"; [[ "$v" =~ ^0x ]] || v="0x$v"; local raw="${v#0x}"; (( ${#raw} == $3 )) || die "$2 must be $3 hex chars"; printf '0x%s' "$raw"; }
dec_digit_hex(){
  case "$(nd "${1:-0}")" in
    0) printf '0' ;;
    1) printf '1' ;;
    2) printf '2' ;;
    3) printf '3' ;;
    4) printf '4' ;;
    5) printf '5' ;;
    6) printf '6' ;;
    7) printf '7' ;;
    8) printf '8' ;;
    9) printf '9' ;;
    10) printf 'a' ;;
    11) printf 'b' ;;
    12) printf 'c' ;;
    13) printf 'd' ;;
    14) printf 'e' ;;
    15) printf 'f' ;;
    *) die "internal hex digit out of range" ;;
  esac
}
dec_to_hex(){
  local dec="$(nd "${1:-0}")" out="" parts q rem
  [[ "$dec" =~ ^[0-9]+$ ]] || die "${2:-value} must be decimal"
  [[ "$dec" == 0 ]] && { printf '0'; return; }
  while [[ "$dec" != 0 ]]; do
    parts="$(divmod "$dec" 16)"; q="${parts%% *}"; rem="${parts##* }"
    out="$(dec_digit_hex "$rem")${out}"
    dec="$q"
  done
  printf '%s' "$out"
}
pad_hex_64(){
  local raw="$(low "${1#0x}")" out=""
  [[ "$raw" =~ ^[0-9a-f]+$ ]] || die "${2:-value} must be hex"
  (( ${#raw} <= 64 )) || die "${2:-value} must fit in uint256"
  printf -v out '%064s' "$raw"
  out="${out// /0}"
  printf '0x%s' "$out"
}
approve_calldata(){
  local spender amount amount_hex spender_hex
  spender="$(addr "$1" approve.spender)"
  amount="$(nd "${2:-0}")"
  [[ "$amount" =~ ^[0-9]+$ ]] || die "approve.amount must be decimal"
  amount_hex="$(pad_hex_64 "$(dec_to_hex "$amount" approve.amount)" approve.amount)"
  spender_hex="$(pad_hex_64 "$spender" approve.spender)"
  printf '0x095ea7b3%s%s' "${spender_hex#0x}" "${amount_hex#0x}"
}
sigv(){
  local raw="$(trim "${1:-}")" name="${2:-signature.v}" dec="" hexv=""
  [[ -n "$raw" ]] || die "$name is required"
  if [[ "$raw" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
    hexv="${raw:2}"
  elif [[ "$raw" =~ ^[0-9]+$ ]]; then
    dec="$raw"
  elif [[ "$raw" =~ ^[0-9a-fA-F]+$ ]]; then
    hexv="$raw"
  else
    die "$name must be 0, 1, 27, 28, or equivalent hex"
  fi
  if [[ -n "$hexv" ]]; then
    dec="$((16#$(low "$hexv")))"
  fi
  case "$(nd "$dec")" in
    0) printf '0x1b' ;;
    1) printf '0x1c' ;;
    27) printf '0x1b' ;;
    28) printf '0x1c' ;;
    *) die "$name must be 0, 1, 27, 28, or equivalent hex" ;;
  esac
}
adapter(){
  local chain="$1" adapt=""
  load_runtime_config
  adapt="$(jq -r --arg chain "$chain" '.chains[$chain].adapter // empty' <<<"$RUNTIME_CONFIG")"
  [[ -n "$adapt" ]] || unsupported_chain "$chain"
  addr "$adapt" "runtime.chains[$chain].adapter"
}
uri(){ jq -nr --arg v "$1" '$v|@uri'; }
warnings_json(){ ((${#WARN[@]})) && jq -n '$ARGS.positional' --args "${WARN[@]}" || say '[]'; }
json_or_text(){ jq -e . "$1" >/dev/null 2>&1 && jq . "$1" || jq -Rs . < "$1"; }

typed(){
  local adapt
  adapt="$(adapter "$1")"
  jq \
    --argjson chainId "$1" \
    --arg swapper "$2" \
    --arg nonce "$3" \
    --arg start "$4" \
    --arg deadline "$5" \
    --arg epoch "$6" \
    --arg slippage "$7" \
    --arg inputToken "$8" \
    --arg inputAmount "$9" \
    --arg inputMaxAmount "${10}" \
    --arg outputToken "${11}" \
    --arg outputLimit "${12}" \
    --arg outputTriggerLower "${13}" \
    --arg outputTriggerUpper "${14}" \
    --arg outputRecipient "${15}" \
    --arg adapter "$adapt" \
    --arg exclusivity "$EXCLUSIVITY" \
    --arg freshness "$FRESHNESS" \
    --arg repermit "$REPERMIT" \
    --arg reactor "$REACTOR" \
    --arg executor "$EXECUTOR" \
    --arg zero "$ZERO" '
      .domain.chainId = $chainId
      | .domain.verifyingContract = $repermit
      | .message.permitted.token = $inputToken
      | .message.permitted.amount = $inputMaxAmount
      | .message.spender = $reactor
      | .message.nonce = $nonce
      | .message.deadline = $deadline
      | .message.witness.reactor = $reactor
      | .message.witness.executor = $executor
      | .message.witness.exchange.adapter = $adapter
      | .message.witness.exchange.ref = $zero
      | .message.witness.exchange.share = 0
      | .message.witness.exchange.data = "0x"
      | .message.witness.swapper = $swapper
      | .message.witness.nonce = $nonce
      | .message.witness.start = $start
      | .message.witness.deadline = $deadline
      | .message.witness.chainid = $chainId
      | .message.witness.exclusivity = ($exclusivity | tonumber)
      | .message.witness.epoch = ($epoch | tonumber)
      | .message.witness.slippage = ($slippage | tonumber)
      | .message.witness.freshness = ($freshness | tonumber)
      | .message.witness.input.token = $inputToken
      | .message.witness.input.amount = $inputAmount
      | .message.witness.input.maxAmount = $inputMaxAmount
      | .message.witness.output.token = $outputToken
      | .message.witness.output.limit = $outputLimit
      | .message.witness.output.triggerLower = $outputTriggerLower
      | .message.witness.output.triggerUpper = $outputTriggerUpper
      | .message.witness.output.recipient = $outputRecipient
    ' "$SKELETON"
}

sig_json(){
  local payload="$(trim "$1")" r="" s="" v="" full="" kind=""
  [[ -n "$payload" ]] || die "signature input is empty"
  if jq -e . >/dev/null 2>&1 <<<"$payload"; then
    if [[ "$(jq -r 'type' <<<"$payload")" == "string" ]]; then
      payload="$(jq -r . <<<"$payload")"
    else
      full="$(jq -r '
        if type=="object" and has("signature") and (.signature|type)=="string" then .signature
        elif type=="object" then .full // empty
        else empty
        end
      ' <<<"$payload")"
      if [[ -z "$full" ]]; then
        r="$(jq -r 'if type=="object" and has("signature") and (.signature|type)=="object" then .signature.r // empty else .r // empty end' <<<"$payload")"
        s="$(jq -r 'if type=="object" and has("signature") and (.signature|type)=="object" then .signature.s // empty else .s // empty end' <<<"$payload")"
        v="$(jq -r 'if type=="object" and has("signature") and (.signature|type)=="object" then .signature.v // empty else .v // empty end' <<<"$payload")"
        [[ -n "$r" && -n "$s" && -n "$v" ]] || die "signature JSON must contain a full signature string or r, s, v"
        kind="rsv"
      else
        payload="$full"
      fi
    fi
  fi
  if [[ -n "$r" || -n "$s" || -n "$v" ]]; then
    r="$(hx "$r" signature.r 64)"
    s="$(hx "$s" signature.s 64)"
    v="$(sigv "$v" signature.v)"
    full="${r}${s#0x}${v#0x}"
  else
    [[ "$payload" =~ ^0x[0-9a-fA-F]{130}$ || "$payload" =~ ^[0-9a-fA-F]{130}$ ]] || die "signature must be full hex, a JSON string, or r/s/v JSON"
    [[ "$payload" =~ ^0x ]] || payload="0x${payload}"
    full="$payload"
    r="0x${payload:2:64}"
    s="0x${payload:66:64}"
    v="$(sigv "0x${payload:130:2}" signature.v)"
    [[ -n "$kind" ]] || kind="full"
  fi
  jq -n --arg kind "$kind" --arg full "$full" --arg r "$r" --arg s "$s" --arg v "$v" '{kind:$kind,full:$full,signature:{r:$r,s:$s,v:$v}}'
}

prepare(){
  local params="" out_file="" params_json="" now_ts chain swapper nonce start deadline epoch slippage
  local in_token in_amount in_max requested_in_max out_token out_limit out_low out_up recipient parts chunk_count rem kind
  load_runtime_config
  while (($#)); do case "$1" in --params) params="${2:-}"; shift 2 ;; --out) out_file="${2:-}"; shift 2 ;; *) die "unknown prepare arg: $1" ;; esac; done
  need jq
  params_json="$(read_json "$params" params)"
  now_ts="$(now)"
  chain="$(u "$(jget "$params_json" '.chainId // .chainID')" chainId)"
  has_supported_chain "$chain" || unsupported_chain "$chain"
  swapper="$(addr "$(jget "$params_json" '.swapper // .account // .signer')" swapper)"
  nonce="$(u "$(co "$(jget "$params_json" '.nonce')" "$now_ts")" nonce)"
  start="$(u "$(co "$(jget "$params_json" '.start')" "$now_ts")" start)"
  epoch="$(u "$(co "$(jget "$params_json" '.epoch')" 0)" epoch)"
  slippage="$(u "$(co "$(jget "$params_json" '.slippage')" "$DEF_SLIPPAGE")" slippage)"
  in_token="$(addr "$(jget "$params_json" '.input.token // .inputToken')" input.token)"
  in_amount="$(u "$(jget "$params_json" '.input.amount // .inputAmount')" input.amount)"
  in_max="$(u "$(co "$(jget "$params_json" '.input.maxAmount // .inputMaxAmount')" "$in_amount")" input.maxAmount)"
  out_token="$(addr "$(jget "$params_json" '.output.token // .outputToken')" output.token 1)"
  out_limit="$(u "$(co "$(jget "$params_json" '.output.limit // .outputLimit')" 0)" output.limit)"
  out_low="$(u "$(co "$(jget "$params_json" '.output.triggerLower // .outputTriggerLower')" 0)" output.triggerLower)"
  out_up="$(u "$(co "$(jget "$params_json" '.output.triggerUpper // .outputTriggerUpper')" 0)" output.triggerUpper)"
  recipient="$(addr "$(co "$(jget "$params_json" '.output.recipient // .recipient')" "$swapper")" output.recipient)"
  u32 "$epoch" epoch; u32 "$slippage" slippage
  eq "$start" 0 && die "start must be non-zero"
  eq "$in_amount" 0 && die "input.amount must be non-zero"
  gt "$in_amount" "$in_max" && die "input.amount cannot exceed input.maxAmount"
  [[ "$(low "$in_token")" == "$(low "$out_token")" ]] && die "input.token and output.token must differ"
  [[ "$(cmp "$out_up" 0)" != 0 && "$(cmp "$out_low" "$out_up")" == 1 ]] && die "output.triggerLower cannot exceed output.triggerUpper"
  gt "$slippage" "$MAX_SLIPPAGE" && die "slippage cannot exceed $MAX_SLIPPAGE"
  [[ "$(cmp "$epoch" 0)" != 0 && "$(cmp "$FRESHNESS" "$epoch")" != -1 ]] && die "freshness must be < epoch when epoch != 0"
  requested_in_max="$in_max"
  parts="$(divmod "$in_max" "$in_amount")"; chunk_count="${parts%% *}"; rem="${parts##* }"
  if ! eq "$rem" 0; then
    in_max="$(sub "$in_max" "$rem")"
    warn "input.maxAmount is not divisible by input.amount; rounding down from $requested_in_max to $in_max to keep fixed chunk sizes"
  fi
  ! eq "$in_amount" "$in_max" && eq "$epoch" 0 && die "chunked orders require epoch > 0"
  if eq "$in_amount" "$in_max"; then kind=single; else kind=chunked; fi
  if [[ -n "$(jget "$params_json" '.deadline')" ]]; then
    deadline="$(u "$(jget "$params_json" '.deadline')" deadline)"
  else
    deadline="$(add "$start" "$TTL")"
    gt "$epoch" 0 && deadline="$(add "$deadline" "$(muls "$chunk_count" "$epoch")")"
  fi
  if gt "$start" "$now_ts"; then gt "$deadline" "$start" || die "deadline must be after start"; else gt "$deadline" "$now_ts" || die "deadline must be after current time"; fi
  [[ "$(cmp "$slippage" "$DEF_SLIPPAGE")" == -1 ]] && warn "$WARN_LOW_SLIPPAGE"
  [[ "$(low "$recipient")" != "$(low "$swapper")" ]] && warn "$WARN_RECIPIENT"
  local typed_data typed_compact approval_data prepared
  approval_data="$(hex "$(approve_calldata "$REPERMIT" "$in_max")" approval.tx.data)"
  typed_data="$(typed "$chain" "$swapper" "$nonce" "$start" "$deadline" "$epoch" "$slippage" "$in_token" "$in_amount" "$in_max" "$out_token" "$out_limit" "$out_low" "$out_up" "$recipient")"
  typed_compact="$(jq -c . <<<"$typed_data")"
  prepared="$(
    jq -n \
      --arg preparedAt "$(iso)" \
      --arg chunkCount "$chunk_count" \
      --arg chunkInputAmount "$in_amount" \
      --arg epochNote "$NOTE_EPOCH" \
      --arg kind "$kind" \
      --arg epoch "$epoch" \
      --arg start "$start" \
      --arg deadline "$deadline" \
      --arg limit "$out_limit" \
      --arg swapper "$swapper" \
      --arg note "$NOTE_ORACLE" \
      --arg signNote "$NOTE_SIGN" \
      --arg query "$QUERY_URL" \
      --arg create "$CREATE_URL" \
      --arg inToken "$in_token" \
      --arg inMax "$in_max" \
      --arg spender "$REPERMIT" \
      --arg approval "$approval_data" \
      --argjson warnings "$(warnings_json)" \
      --argjson typedData "$typed_compact" '
        {
          meta:{
            preparedAt:$preparedAt,
            kind:$kind,
            chunkCount:$chunkCount,
            chunkInputAmount:$chunkInputAmount,
            start:$start,
            deadline:$deadline,
            epoch:$epoch,
            epochScheduling:$epochNote,
            limit:$limit,
            oracleProtection:$note
          },
          warnings:$warnings,
          approval:{token:$inToken,spender:$spender,amount:$inMax,tx:{to:$inToken,data:$approval,value:"0x0"}},
          typedData:$typedData,
          signing:{signer:$swapper,note:$signNote},
          submit:{url:$create,body:{order:$typedData.message,signature:{r:null,s:null,v:null},status:"pending"}},
          query:{url:$query}
        }'
  )"
  out "$prepared" "$out_file"
}

submit(){
  local prepared="" prepared_json="" sig="" sig_file="" r="" s="" v="" out_file="" payload mode_count=0 normalized request reqf bodyf respf code result
  load_runtime_config
  while (($#)); do
    case "$1" in
      --prepared) prepared="${2:-}"; shift 2 ;;
      --signature) sig="${2:-}"; shift 2 ;;
      --signature-file) sig_file="${2:-}"; shift 2 ;;
      --r) r="${2:-}"; shift 2 ;;
      --s) s="${2:-}"; shift 2 ;;
      --v) v="${2:-}"; shift 2 ;;
      --out) out_file="${2:-}"; shift 2 ;;
      *) die "unknown submit arg: $1" ;;
    esac
  done
  need jq
  [[ "$prepared" == "-" && "$sig_file" == "-" ]] && die "submit supports only one stdin source"
  prepared_json="$(read_json "$prepared" prepared)"
  [[ -n "$sig" ]] && mode_count=$((mode_count+1))
  [[ -n "$sig_file" ]] && mode_count=$((mode_count+1))
  [[ -n "$r" || -n "$s" || -n "$v" ]] && mode_count=$((mode_count+1))
  (( mode_count == 1 )) || die "submit needs exactly one of --signature, --signature-file, or --r/--s/--v"
  if [[ -n "$sig_file" ]]; then
    payload="$(read_src "$sig_file" signature-file)"
    normalized="$(sig_json "$payload")"
  elif [[ -n "$sig" ]]; then
    normalized="$(sig_json "$sig")"
  else
    [[ -n "$r" && -n "$s" && -n "$v" ]] || die "--r --s --v must be used together"
    normalized="$(sig_json "$(jq -n --arg r "$r" --arg s "$s" --arg v "$v" '{r:$r,s:$s,v:$v}')")"
  fi
  request="$(
    jq -n \
      --argjson prepared "$(jq -c . <<<"$prepared_json")" \
      --argjson sig "$normalized" \
      --arg url "$CREATE_URL" '
        {
          url: ($prepared.submit.url // $url),
          body: {
            order: (
              if $prepared.submit.body.order then $prepared.submit.body.order
              elif $prepared.typedData.message then $prepared.typedData.message
              elif ($prepared.domain and $prepared.types and $prepared.message) then $prepared.message
              else error("missing order payload")
              end
            ),
            signature: $sig.signature,
            status: ($prepared.submit.body.status // "pending")
          },
          signatureInput: $sig.kind
        }'
  )"
  need curl
  reqf="$(mktemp)"; bodyf="$(mktemp)"; respf="$(mktemp)"
  printf '%s\n' "$request" > "$reqf"
  jq '.body' "$reqf" > "$bodyf"
  code="$(curl -sS -o "$respf" -w '%{http_code}' -X POST -H 'content-type: application/json' --data-binary @"$bodyf" "$(jq -r '.url' "$reqf")")"
  result="$(jq -n --argjson request "$(jq -c . "$reqf")" --arg code "$code" --argjson response "$(json_or_text "$respf")" '{ok:(($code|tonumber)>=200 and ($code|tonumber)<300),status:($code|tonumber),url:$request.url,request:$request,response:$response}')"
  out "$result" "$out_file"
  [[ "$code" -ge 200 && "$code" -lt 300 ]]
}

query(){
  local swapper="" hash="" out_file="" url result respf code
  load_runtime_config
  while (($#)); do
    case "$1" in
      --swapper) swapper="${2:-}"; shift 2 ;;
      --hash) hash="${2:-}"; shift 2 ;;
      --out) out_file="${2:-}"; shift 2 ;;
      *) die "unknown query arg: $1" ;;
    esac
  done
  [[ -n "$swapper" || -n "$hash" ]] || die "query needs --swapper or --hash"
  url="$QUERY_URL"
  if [[ -n "$swapper" ]]; then swapper="$(addr "$swapper" swapper)"; url="${url}?swapper=$(uri "$swapper")"; fi
  if [[ -n "$hash" ]]; then [[ "$hash" =~ ^0x[0-9a-fA-F]{64}$ ]] || die "hash must be 32-byte 0x hex"; [[ "$url" == *\?* ]] && url="${url}&hash=$(uri "$hash")" || url="${url}?hash=$(uri "$hash")"; fi
  need jq
  need curl
  respf="$(mktemp)"
  code="$(curl -sS -o "$respf" -w '%{http_code}' "$url")"
  result="$(jq -n --arg url "$url" --arg code "$code" --argjson response "$(json_or_text "$respf")" '{ok:(($code|tonumber)>=200 and ($code|tonumber)<300),status:($code|tonumber),url:$url,response:$response}')"
  out "$result" "$out_file"
  [[ "$code" -ge 200 && "$code" -lt 300 ]]
}

main(){
  local cmd="${1:-}"
  [[ -n "$cmd" && "$cmd" != help && "$cmd" != --help && "$cmd" != -h ]] || { usage; [[ -n "$cmd" ]] && exit 0 || exit 1; }
  shift || true
  case "$cmd" in
    prepare) prepare "$@" ;;
    submit) submit "$@" ;;
    query) query "$@" ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
