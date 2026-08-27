#!/usr/bin/env python3
import os
import sys
import json
import glob
import datetime
from pathlib import Path

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

    def empty_bucket():
        return {
            "inputTokens": 0,
            "outputTokens": 0,
            "cacheReadInputTokens": 0,
            "cacheCreationInputTokens": 0,
        }

    # Search for all Gemini CLI session json files in ~/.gemini/tmp/*/chats/*.json
    search_path = str(home / ".gemini" / "tmp" / "*" / "chats" / "*.json")
    for file_path_str in glob.glob(search_path):
        try:
            with open(file_path_str, "r") as f:
                data = json.load(f)
        except Exception:
            continue

        session_id = data.get("sessionId")
        if not session_id:
            continue

        messages = data.get("messages") or []
        for msg in messages:
            if isinstance(msg, dict) and msg.get("type") == "gemini":
                # Parse timestamp to date
                ts_str = msg.get("timestamp")
                if ts_str:
                    try:
                        # e.g., "2026-04-22T18:27:01.040Z"
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
                    continue

                model = str(msg.get("model") or "gemini-3-flash").rstrip("/").split("/")[-1]

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
