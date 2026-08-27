# OmaGemi

OmaGemi (`stolli.omagemi`) is a lightweight, highly secure, and native **Omarchy service plugin** (headless singleton) that integrates local Google Gemini CLI usage and token metrics directly into the native Omarchy status bar **Agents** widget.

It automates the process of reading your Gemini CLI's project-specific session files and compiling them into a compliant usage record (`gemini.json`), which is then dynamically displayed as a first-class tab in your status bar alongside Claude Code and Codex.

---

## Architecture & Integration

*   **Service Kind:** Implemented as a native Omarchy `service` kind. It runs headless within the `omarchy-shell` process.
*   **Daemonless Periodicity:** Utilizes QML's native `Timer` and `Process` components to trigger the local python collector every 5 minutes—eliminating the need for system-level cron jobs or persistent external systemd processes.
*   **Dynamic Discovery:** Capitalizes on the Agents status bar widget's dynamic discovery mechanism (it scans `~/.local/state/omarchy/agents/usage/` for any `.json` file and renders it automatically).

---

## File Structure

```text
stolli.omagemi/
├── .gitignore          # Rigorous git exclusions for absolute safety
├── LICENSE             # MIT License
├── manifest.json       # Omarchy plugin metadata mapping our service entry point
├── README.md           # Documentation and architecture
├── Service.qml         # Headless QML service executing the collector periodically
└── collector.py        # Independent Python 3 script that aggregates Gemini session logs
```

---

## Security & Safety Audit

This plugin was designed under rigorous security standards suitable for sensitive development environments:

1.  **100% Local Execution:** The Python collector and QML service operate entirely on your local machine. No external APIs are called, and no telemetry is transmitted over the internet.
2.  **Zero Credential Access:** The script **never** reads, accesses, or exposes any API keys, `.env` files, or passwords. It only reads local session history metadata.
3.  **Read-Only Session Parsing:** Only localized Gemini CLI statistics (timestamps, models used, and token counts) are parsed from the `~/.gemini/tmp/` directory. No proprietary code files or actual prompt texts are read, stored, or output.
4.  **No Symlinks or Unsafe System Access:** Adheres fully to the unsandboxed plugin environment constraints by referencing files safely using standard python libraries.

---

## Installation

To install this plugin locally under your active Omarchy shell:

1.  Clone this repository to your local Omarchy plugins directory:
    ```bash
    mkdir -p ~/.config/omarchy/plugins/stolli.omagemi
    cp -r * ~/.config/omarchy/plugins/stolli.omagemi/
    ```

2.  Make the Python collector script executable:
    ```bash
    chmod +x ~/.config/omarchy/plugins/stolli.omagemi/collector.py
    ```

3.  Validate the plugin using the Omarchy CLI tool:
    ```bash
    omarchy plugin validate ~/.config/omarchy/plugins/stolli.omagemi/
    ```

4.  Restart the Omarchy status bar to load the new service:
    ```bash
    omarchy restart shell
    ```

---

## License

This project is licensed under the [MIT License](LICENSE).
