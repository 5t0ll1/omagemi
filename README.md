# OmaGemi

OmaGemi (`oma.gemi`) is a lightweight, highly secure, and native **Omarchy plugin** that aggregates Google Gemini usage (from local **Gemini CLI** and **OpenCode**) and provides a dynamic Gemini icon directly in the native Omarchy status bar.

It automates the process of aggregating session history and token counts across Gemini CLI session files (`~/.gemini/tmp/`) and OpenCode database logs (`~/.local/share/opencode/opencode.db`), compiling them into a compliant usage record (`gemini.json`) for the status bar **Agents** widget, while displaying a beautiful, context-aware Gemini icon.

---

## Architecture & Integration

*   **Dual-Kind Plugin:** Implemented as a native Omarchy `service` (headless singleton) and `bar-widget` (status bar module).
*   **Daemonless Periodicity:** Utilizes QML's native `Timer` and `Process` components in `Service.qml` to trigger the local python collector every 5 minutes—eliminating the need for system-level cron jobs or persistent external systemd processes.
*   **Dual-Source Integration:** Aggregates Gemini token usage from both traditional Gemini CLI session files and OpenCode sessions (`~/.local/share/opencode/opencode.db`), preserving historical totals and updating daily pay-per-day usage automatically.
*   **Topbar Gemini Icon:** Shows the beautiful Nerd Font Gemini sparkles icon (`󰭎`) in the right-hand bar.
*   **Dynamic Visibility:** The topbar icon is only visible if there is active Gemini usage (`gemini.json` is ready).
*   **Seamless Panel Integration:** 
    *   **Left click** toggles the standard polished `omarchy.agents` panel directly, allowing you to view detailed charts, model breakdowns, and limits without duplicating code or rendering a separate custom panel!
    *   **Right click** forces an instant background refresh of agent limits and usage data.

---

## File Structure

```text
oma.gemi/
├── .gitignore          # Rigorous git exclusions for absolute safety
├── BarWidget.qml       # Beautiful topbar widget displaying the Gemini icon and tooltip
├── LICENSE             # MIT License
├── manifest.json       # Omarchy plugin metadata mapping our service and widget entry points
├── README.md           # Documentation and architecture
├── Service.qml         # Headless QML service executing the collector periodically
└── collector.py        # Independent Python 3 script that aggregates Gemini session logs
```

---

## Security & Safety Audit

This plugin was designed under rigorous security standards suitable for sensitive development environments:

1.  **100% Local Execution:** The Python collector and QML components operate entirely on your local machine. No external APIs are called, and no telemetry is transmitted over the internet.
2.  **Zero Credential Access:** The script **never** reads, accesses, or exposes any API keys, `.env` files, or passwords. It only reads local session history metadata.
3.  **Read-Only Session Parsing:** Only localized Gemini statistics (timestamps, models used, and token counts) are parsed from `~/.gemini/tmp/` and SQLite `~/.local/share/opencode/opencode.db` (opened in read-only mode). No proprietary code files or actual prompt texts are stored or output.
4.  **No Symlinks or Unsafe System Access:** Adheres fully to the unsandboxed plugin environment constraints by referencing files safely using standard python libraries.

---

## Installation & Activation

To install this plugin locally under your active Omarchy shell:

1.  Clone/copy this repository to your local Omarchy plugins directory:
    ```bash
    mkdir -p ~/.config/omarchy/plugins/oma.gemi
    cp -r * ~/.config/omarchy/plugins/oma.gemi/
    ```

2.  Make the Python collector script executable:
    ```bash
    chmod +x ~/.config/omarchy/plugins/oma.gemi/collector.py
    ```

3.  Validate the plugin using the Omarchy CLI tool:
    ```bash
    omarchy plugin validate ~/.config/omarchy/plugins/oma.gemi/
    ```

4.  Enable the plugin and add the widget to your bar:
    ```bash
    omarchy plugin enable oma.gemi --section right
    ```

5.  Restart the Omarchy status bar to load the new service and bar widget:
    ```bash
    omarchy restart shell
    ```

---

## License

This project is licensed under the [MIT License](LICENSE).
