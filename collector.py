#!/usr/bin/env python3
import os
import sys
import json
import glob
import datetime
import sqlite3
from pathlib import Path

# Prices in USD per 1 Million tokens
# (input_price_per_1M, output_price_per_1M, cached_price_per_1M)
PRICING_MAP = {
    "gemini-3.5-flash": (1.50, 9.00, 0.15),
    "gemini-3.7-flash": (0.75, 3.75, 0.075),
    "gemini-3.6-flash": (0.75, 3.75, 0.075),
    "gemini-3-flash-preview": (0.75, 3.75, 0.075),
    "gemini-2.5-flash": (0.075, 0.30, 0.01875),
    "gemini-3.1-pro": (2.00, 12.00, 0.20),
    "gemini-1.5-flash": (0.075, 0.30, 0.01875),
    "gemini-1.5-pro": (1.25, 5.00, 0.3125),
}

def calculate_bucket_cost(input_tokens, output_tokens, cached_tokens, model_name):
    matched = "gemini-3.5-flash"
    for p_model in PRICING_MAP:
        if p_model in model_name:
            matched = p_model
            break
            
    inp_p, out_p, cach_p = PRICING_MAP[matched]
    cost_usd = (input_tokens * inp_p + output_tokens * out_p + cached_tokens * cach_p) / 1000000.0
    return cost_usd * 0.90

def empty_bucket():
    return {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 0,
        "cacheCreationInputTokens": 0,
    }

def main():
    home = Path.home()
    usage_dir = home / ".local" / "state" / "omarchy" / "agents" / "usage"
    usage_dir.mkdir(parents=True, exist_ok=True)
    gemini_json_path = usage_dir / "gemini.json"

    # Read existing record if present to preserve historical tokens from deleted CLI sessions
    existing_record = {}
    if gemini_json_path.exists():
        try:
            with open(gemini_json_path, "r") as f:
                existing_record = json.load(f)
        except Exception:
            pass

    today_dt = datetime.date.today()
    recent_dates = [(today_dt - datetime.timedelta(days=i)).isoformat() for i in range(6, -1, -1)]
    today_str = today_dt.isoformat()

    recent = {day: {"date": day, "messageCount": 0} for day in recent_dates}
    
    # Pre-fill recent from existing record if available
    for rd in existing_record.get("recentDays") or []:
        d = rd.get("date")
        if d in recent and d != today_str:
            recent[d]["messageCount"] = rd.get("messageCount") or 0

    today_prompt_count = 0
    today_sessions = set()
    today_token_total = 0
    today_tokens_by_model = {}
    today_cost_by_model = {}

    scanned_prompts = 0
    sessions = set()
    active_days = set(existing_record.get("activeDates") or [])

    model_usage = {}
    for m_name, m_data in (existing_record.get("modelUsage") or {}).items():
        model_usage[m_name] = {
            "inputTokens": m_data.get("inputTokens") or 0,
            "outputTokens": m_data.get("outputTokens") or 0,
            "cacheReadInputTokens": m_data.get("cacheReadInputTokens") or 0,
            "cacheCreationInputTokens": m_data.get("cacheCreationInputTokens") or 0,
        }

    scanned_model_usage = {}
    processed_message_ids = set()

    def process_message(msg_id, session_id, dt, model, input_tokens, output_tokens, cached_tokens, cache_creation_tokens=0):
        nonlocal scanned_prompts, today_prompt_count, today_token_total
        
        if msg_id:
            if msg_id in processed_message_ids:
                return
            processed_message_ids.add(msg_id)

        day_str = dt.date().isoformat()
        total = input_tokens + output_tokens + cached_tokens + cache_creation_tokens

        if total <= 0:
            return

        sessions.add(session_id)
        active_days.add(day_str)
        scanned_prompts += 1

        bucket = scanned_model_usage.setdefault(model, empty_bucket())
        bucket["inputTokens"] += input_tokens
        bucket["outputTokens"] += output_tokens
        bucket["cacheReadInputTokens"] += cached_tokens
        bucket["cacheCreationInputTokens"] += cache_creation_tokens

        if day_str in recent:
            recent[day_str]["messageCount"] += total

        if day_str == today_str:
            today_prompt_count += 1
            today_sessions.add(session_id)
            today_token_total += total
            today_tokens_by_model[model] = today_tokens_by_model.get(model, 0) + total
            
            cost = calculate_bucket_cost(input_tokens, output_tokens, cached_tokens, model)
            today_cost_by_model[model] = today_cost_by_model.get(model, 0.0) + cost

    # 1. Search for Gemini CLI session files in ~/.gemini/tmp/*/chats/*
    for ext in ("*.json", "*.jsonl"):
        search_path = str(home / ".gemini" / "tmp" / "*" / "chats" / ext)
        for file_path_str in glob.glob(search_path):
            try:
                if file_path_str.endswith(".jsonl"):
                    session_id = None
                    with open(file_path_str, "r") as f:
                        for line in f:
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                data = json.loads(line)
                            except Exception:
                                continue
                            if "sessionId" in data:
                                session_id = data["sessionId"]
                            if isinstance(data, dict):
                                messages = []
                                if data.get("type") == "gemini":
                                    messages = [data]
                                elif "$set" in data and isinstance(data["$set"], dict) and "messages" in data["$set"]:
                                    messages = data["$set"]["messages"]
                                for msg in messages:
                                    if isinstance(msg, dict) and msg.get("type") == "gemini":
                                        msg_id = msg.get("id")
                                        ts_str = msg.get("timestamp")
                                        if ts_str:
                                            try:
                                                dt = datetime.datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                                            except Exception:
                                                dt = datetime.datetime.now(datetime.timezone.utc)
                                        else:
                                            dt = datetime.datetime.now(datetime.timezone.utc)
                                        tokens = msg.get("tokens") or {}
                                        inp = int(tokens.get("input") or 0)
                                        out = int(tokens.get("output") or 0) + int(tokens.get("thoughts") or 0) + int(tokens.get("tool") or 0)
                                        cach = int(tokens.get("cached") or 0)
                                        model = str(msg.get("model") or "gemini-3.5-flash").rstrip("/").split("/")[-1]
                                        process_message(msg_id, session_id or "unknown_session", dt, model, inp, out, cach)
                else:
                    with open(file_path_str, "r") as f:
                        data = json.load(f)
                    session_id = data.get("sessionId") or "unknown_session"
                    messages = data.get("messages") or []
                    for msg in messages:
                        if isinstance(msg, dict) and msg.get("type") == "gemini":
                            msg_id = msg.get("id")
                            ts_str = msg.get("timestamp")
                            if ts_str:
                                try:
                                    dt = datetime.datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                                except Exception:
                                    dt = datetime.datetime.now(datetime.timezone.utc)
                            else:
                                dt = datetime.datetime.now(datetime.timezone.utc)
                            tokens = msg.get("tokens") or {}
                            inp = int(tokens.get("input") or 0)
                            out = int(tokens.get("output") or 0) + int(tokens.get("thoughts") or 0) + int(tokens.get("tool") or 0)
                            cach = int(tokens.get("cached") or 0)
                            model = str(msg.get("model") or "gemini-3.5-flash").rstrip("/").split("/")[-1]
                            process_message(msg_id, session_id, dt, model, inp, out, cach)
            except Exception:
                continue

    # 2. Search for Opencode messages in ~/.local/share/opencode/opencode.db
    opencode_db = home / ".local" / "share" / "opencode" / "opencode.db"
    if opencode_db.exists():
        try:
            conn = sqlite3.connect(f"file:{opencode_db}?mode=ro", uri=True)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            rows = cursor.execute("SELECT id, session_id, time_created, data FROM message").fetchall()
            for r in rows:
                data_raw = r["data"]
                if not data_raw:
                    continue
                try:
                    data = json.loads(data_raw)
                except Exception:
                    continue
                
                role = data.get("role")
                provider = data.get("providerID")
                model = data.get("modelID") or data.get("model") or "gemini-3.6-flash"
                if isinstance(model, dict):
                    model = model.get("modelID") or model.get("model") or "gemini-3.6-flash"
                
                if role == "assistant" and (provider == "google" or (model and "gemini" in str(model))):
                    msg_id = r["id"]
                    session_id = r["session_id"]
                    time_info = data.get("time") or {}
                    created_ms = time_info.get("created") or r["time_created"]
                    dt = datetime.datetime.fromtimestamp(created_ms / 1000.0, tz=datetime.timezone.utc)
                    
                    tokens = data.get("tokens") or {}
                    inp = int(tokens.get("input") or 0)
                    out = int(tokens.get("output") or 0) + int(tokens.get("reasoning") or 0)
                    cache_dict = tokens.get("cache") or {}
                    cach_read = int(cache_dict.get("read") or 0)
                    cach_write = int(cache_dict.get("write") or 0)
                    
                    model_name = str(model).rstrip("/").split("/")[-1]
                    process_message(msg_id, session_id, dt, model_name, inp, out, cach_read, cach_write)
            conn.close()
        except Exception:
            pass

    # Merge scanned model usage into base model_usage
    for m_name, scanned_b in scanned_model_usage.items():
        base_b = model_usage.setdefault(m_name, empty_bucket())
        base_b["inputTokens"] = max(base_b["inputTokens"], scanned_b["inputTokens"])
        base_b["outputTokens"] = max(base_b["outputTokens"], scanned_b["outputTokens"])
        base_b["cacheReadInputTokens"] = max(base_b["cacheReadInputTokens"], scanned_b["cacheReadInputTokens"])
        base_b["cacheCreationInputTokens"] = max(base_b["cacheCreationInputTokens"], scanned_b["cacheCreationInputTokens"])

    total_spent_eur = sum(
        calculate_bucket_cost(b["inputTokens"], b["outputTokens"], b["cacheReadInputTokens"], m_name)
        for m_name, b in model_usage.items()
    )
    today_spent_eur = sum(today_cost_by_model.values())

    # 3. Read agent config for Google AI Studio prepayment/billing info
    gemini_cfg_path = home / ".config" / "omarchy" / "agents" / "gemini.json"
    balance_obj = None
    
    if gemini_cfg_path.exists():
        try:
            with open(gemini_cfg_path, "r") as f:
                cfg = json.load(f)
                funded = cfg.get("fundedAmount")
                current = cfg.get("currentBalance")
                curr = cfg.get("currency") or "EUR"
                
                if funded is not None and current is not None:
                    spent = float(funded) - float(current)
                    balance_obj = {
                        "remaining": float(current),
                        "funded": float(funded),
                        "spent": spent,
                        "currency": curr,
                        "estimated": False
                    }
        except Exception:
            pass

    tot_prompts = max(existing_record.get("totalPrompts") or 0, scanned_prompts)
    tot_sessions = max(existing_record.get("totalSessions") or 0, len(sessions))
    has_data = tot_prompts > 0 or len(model_usage) > 0

    if balance_obj:
        tier_label = f"Prepaid · {balance_obj['remaining']:.2f} {balance_obj['currency']} verbleibend ({today_spent_eur:.2f} € heute)"
    else:
        tier_label = f"Pay-as-you-go · {today_spent_eur:.2f} € heute ({total_spent_eur:.2f} € gesamt)" if today_spent_eur > 0 else f"Pay-as-you-go · {total_spent_eur:.2f} € gesamt"

    record = {
        "schemaVersion": 1,
        "id": "gemini",
        "name": "Gemini",
        "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "ready": has_data,
        "hasLocalStats": True,
        "tierLabel": tier_label if has_data else "",
        "usageStatusText": "",
        "authHelpText": "",
        "limits": [],
        "todayPrompts": today_prompt_count,
        "todaySessions": len(today_sessions),
        "todayTotalTokens": today_token_total,
        "todayTokensByModel": today_tokens_by_model,
        "recentDays": [recent[day] for day in recent_dates],
        "modelUsage": model_usage,
        "totalPrompts": tot_prompts,
        "totalSessions": tot_sessions,
        "activeDays": len(active_days),
        "activeDates": sorted(list(active_days)),
        "balance": balance_obj
    }

    try:
        with open(gemini_json_path, "w") as f:
            json.dump(record, f, separators=(",", ":"), sort_keys=True)
        print(f"Successfully wrote Gemini usage to {gemini_json_path}")
    except Exception as e:
        print(f"Error writing usage file: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
