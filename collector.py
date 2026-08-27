#!/usr/bin/env python3
import os
import sys
import json
import glob
import datetime
from pathlib import Path

def calculate_cost(model_usage):
    # Prices are in USD per 1 Million tokens
    # Map model family patterns to (input_price_per_1M, output_price_per_1M, cached_price_per_1M)
    pricing_map = {
        "gemini-3.5-flash": (1.50, 9.00, 0.15),
        "gemini-3.7-flash": (0.75, 3.75, 0.075),
        "gemini-3.6-flash": (0.75, 3.75, 0.075),
        "gemini-3.1-pro": (2.00, 12.00, 0.20),
        "gemini-1.5-flash": (0.075, 0.30, 0.01875),
        "gemini-1.5-pro": (1.25, 5.00, 0.3125),
    }
    
    total_spent_usd = 0.0
    for model_name, tokens in model_usage.items():
        matched = "gemini-3.5-flash"
        for p_model in pricing_map:
            if p_model in model_name:
                matched = p_model
                break
        
        inp_p, out_p, cach_p = pricing_map[matched]
        
        inp = tokens.get("inputTokens") or 0
        out = tokens.get("outputTokens") or 0
        cach = tokens.get("cacheReadInputTokens") or 0
        
        cost = (inp * inp_p + out * out_p + cach * cach_p) / 1000000.0
        total_spent_usd += cost
        
    # Convert USD to EUR (assuming standard conversion rate of ~0.90)
    return total_spent_usd * 0.90

def main():
    home = Path.home()
    usage_dir = home / ".local" / "state" / "omarchy" / "agents" / "usage"
    usage_dir.mkdir(parents=True, exist_ok=True)
    gemini_json_path = usage_dir / "gemini.json"

    # Get today and last 7 days in YYYY-MM-DD
    today_dt = datetime.date.today()
    recent_dates = [(today_dt - datetime.timedelta(days=i)).isoformat() for i in range(6, -1, -1)]
    today_str = today_dt.isoformat()

    recent = {day: {"date": day, "messageCount": 0} for day in recent_dates}
    
    today_prompt_count = 0
    today_sessions = set()
    today_token_total = 0
    today_tokens_by_model = {}
    
    total_prompts = 0
    sessions = set()
    active_days = set()
    model_usage = {}
    processed_message_ids = set()

    def empty_bucket():
        return {
            "inputTokens": 0,
            "outputTokens": 0,
            "cacheReadInputTokens": 0,
            "cacheCreationInputTokens": 0,
        }

    def process_message(msg, session_id):
        nonlocal total_prompts, today_prompt_count, today_token_total
        
        # Deduplicate using message ID to prevent double-counting across different jsonl lines
        msg_id = msg.get("id")
        if msg_id:
            if msg_id in processed_message_ids:
                return
            processed_message_ids.add(msg_id)

        ts_str = msg.get("timestamp")
        if ts_str:
            try:
                # Parse timestamp to local date
                dt = datetime.datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                day_str = dt.date().isoformat()
            except Exception:
                day_str = today_str
        else:
            day_str = today_str

        tokens = msg.get("tokens") or {}
        input_tokens = int(tokens.get("input") or 0)
        output_tokens = int(tokens.get("output") or 0)
        cached_tokens = int(tokens.get("cached") or 0)
        thoughts_tokens = int(tokens.get("thoughts") or 0)
        tool_tokens = int(tokens.get("tool") or 0)
        total = input_tokens + output_tokens + cached_tokens + thoughts_tokens + tool_tokens

        if total <= 0:
            return

        model = str(msg.get("model") or "gemini-3.5-flash").rstrip("/").split("/")[-1]

        sessions.add(session_id)
        active_days.add(day_str)
        total_prompts += 1

        # Update modelUsage
        bucket = model_usage.setdefault(model, empty_bucket())
        bucket["inputTokens"] += input_tokens
        bucket["outputTokens"] += output_tokens
        bucket["cacheReadInputTokens"] += cached_tokens

        if day_str in recent:
            recent[day_str]["messageCount"] += total

        if day_str == today_str:
            today_prompt_count += 1
            today_sessions.add(session_id)
            today_token_total += total
            today_tokens_by_model[model] = today_tokens_by_model.get(model, 0) + total

    # Search for all Gemini CLI session files in ~/.gemini/tmp/*/chats/*
    for ext in ("*.json", "*.jsonl"):
        search_path = str(home / ".gemini" / "tmp" / "*" / "chats" / ext)
        for file_path_str in glob.glob(search_path):
            try:
                if file_path_str.endswith(".jsonl"):
                    # Process JSON Lines format
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
                                        process_message(msg, session_id or "unknown_session")
                else:
                    # Process standard JSON format
                    with open(file_path_str, "r") as f:
                        data = json.load(f)
                    session_id = data.get("sessionId")
                    if not session_id:
                        continue
                    messages = data.get("messages") or []
                    for msg in messages:
                        if isinstance(msg, dict) and msg.get("type") == "gemini":
                            process_message(msg, session_id)
            except Exception:
                continue

    # Calculate balance details
    funded_budget = float(os.environ.get("GEMINI_FUNDED_BUDGET") or 25.0)
    currency = os.environ.get("GEMINI_CURRENCY") or "EUR"
    
    # Calculate local spent
    spent = calculate_cost(model_usage)
    if currency != "EUR":
        # Adjust spent if currency is USD (pricing is calculated in USD, converted to EUR by default)
        # Convert EUR back to USD
        spent = spent / 0.90
        
    remaining = max(0.0, funded_budget - spent)

    # Ensure there is some basic metadata even if no usage is found
    has_data = total_prompts > 0
    record = {
        "schemaVersion": 1,
        "id": "gemini",
        "name": "Gemini",
        "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "ready": has_data,
        "hasLocalStats": True,
        "tierLabel": "Pay-as-you-go" if has_data else "",
        "usageStatusText": "" if has_data else "No usage recorded yet",
        "authHelpText": "",
        "limits": [],
        "todayPrompts": today_prompt_count,
        "todaySessions": len(today_sessions),
        "todayTotalTokens": today_token_total,
        "todayTokensByModel": today_tokens_by_model,
        "recentDays": [recent[day] for day in recent_dates],
        "modelUsage": model_usage,
        "totalPrompts": total_prompts,
        "totalSessions": len(sessions),
        "activeDays": len(active_days),
        "activeDates": sorted(list(active_days)),
        "balance": {
            "funded": funded_budget,
            "spent": round(spent, 4),
            "remaining": round(remaining, 4),
            "currency": currency,
            "estimated": True
        }
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
