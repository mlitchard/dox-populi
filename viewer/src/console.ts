// Console block under the room view. Three tabs: "live" streams the
// running script's output (log lines and loop errors) from the user's
// console socket channel, "console" is a typed expression at the
// bottom with its echo and result above, "code" shows the modules
// currently uploaded to the server.

import { Api } from "./protocol";

export interface ConsolePayload {
  messages?: { log?: string[]; results?: string[] };
  error?: string;
}

interface ConsoleUi {
  live: HTMLElement;
  log: HTMLElement;
  form: HTMLFormElement;
  input: HTMLInputElement;
  repl: HTMLElement;
  code: HTMLElement;
  tabLive: HTMLButtonElement;
  tabConsole: HTMLButtonElement;
  tabCode: HTMLButtonElement;
}

export class GameConsole {
  constructor(
    private readonly ui: ConsoleUi,
    private readonly api: Api,
  ) {
    ui.form.addEventListener("submit", (ev) => {
      ev.preventDefault();
      const expression = ui.input.value.trim();
      if (!expression) return;
      this.append(ui.log, "in", `> ${expression}`);
      ui.input.value = "";
      this.api.console(expression).catch((err: Error) => {
        this.append(ui.log, "err", err.message);
      });
    });
    ui.tabLive.addEventListener("click", () => this.show("live"));
    ui.tabConsole.addEventListener("click", () => this.show("repl"));
    ui.tabCode.addEventListener("click", () => {
      void this.showCode();
    });
  }

  receive(payload: ConsolePayload): void {
    for (const line of payload.messages?.log ?? []) {
      this.append(this.ui.live, "out", line);
    }
    if (payload.error) this.append(this.ui.live, "err", payload.error);
    for (const line of payload.messages?.results ?? []) {
      this.append(this.ui.log, "out", line);
    }
  }

  private show(which: "live" | "repl" | "code"): void {
    const { ui } = this;
    ui.live.style.display = which === "live" ? "block" : "none";
    ui.repl.style.display = which === "repl" ? "block" : "none";
    ui.code.style.display = which === "code" ? "block" : "none";
    ui.tabLive.classList.toggle("active", which === "live");
    ui.tabConsole.classList.toggle("active", which === "repl");
    ui.tabCode.classList.toggle("active", which === "code");
    if (which === "repl") ui.input.focus();
  }

  private async showCode(): Promise<void> {
    this.show("code");
    this.ui.code.textContent = "loading…";
    try {
      const modules = await this.api.code();
      const parts = Object.entries(modules).map(
        ([name, src]) => `// module: ${name}\n${src}`,
      );
      this.ui.code.textContent = parts.length
        ? parts.join("\n\n")
        : "no code uploaded";
    } catch (err) {
      this.ui.code.textContent = (err as Error).message;
    }
  }

  private append(pane: HTMLElement, kind: "in" | "out" | "err", text: string): void {
    const line = document.createElement("div");
    line.className = kind;
    line.textContent = text;
    pane.appendChild(line);
    pane.scrollTop = pane.scrollHeight;
  }
}
