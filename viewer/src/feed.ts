// Websocket client for the private server's room feed
// (docs/viewer-contract.md): plain WebSocket, text auth frame, JSON
// [channel, payload] channel messages, optional gz:-prefixed
// zlib-deflated frames.

export interface FeedHandlers {
  onChannel(channel: string, payload: unknown, firstForChannel: boolean): void;
  onTokenRotated(token: string): void;
  onClosed(): void;
}

async function inflate(frame: string): Promise<string> {
  const bytes = Uint8Array.from(atob(frame.slice(3)), (c) => c.charCodeAt(0));
  const stream = new Blob([bytes])
    .stream()
    .pipeThrough(new DecompressionStream("deflate"));
  return await new Response(stream).text();
}

export class Feed {
  private ws?: WebSocket;
  private seenChannels = new Set<string>();
  private subscriptions = new Set<string>();

  constructor(
    private readonly url: string,
    private readonly handlers: FeedHandlers,
  ) {}

  connect(token: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url);
      this.ws = ws;
      ws.onopen = () => ws.send(`auth ${token}`);
      ws.onerror = () => reject(new Error(`websocket failed: ${this.url}`));
      ws.onclose = () => this.handlers.onClosed();
      ws.onmessage = async (ev) => {
        let msg = String(ev.data);
        if (msg.startsWith("gz:")) msg = await inflate(msg);
        if (msg.startsWith("[")) {
          const [channel, payload] = JSON.parse(msg) as [string, unknown];
          const first = !this.seenChannels.has(channel);
          this.seenChannels.add(channel);
          this.handlers.onChannel(channel, payload, first);
          return;
        }
        const [word, ...rest] = msg.split(" ");
        if (word === "auth") {
          if (rest[0] === "ok") {
            this.handlers.onTokenRotated(rest[1]);
            for (const channel of this.subscriptions) {
              ws.send(`subscribe ${channel}`);
            }
            resolve();
          } else {
            reject(new Error("websocket auth failed"));
          }
        }
        // Other control frames (protocol, time, package) need nothing.
      };
    });
  }

  subscribe(channel: string): void {
    this.subscriptions.add(channel);
    this.seenChannels.delete(channel);
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(`subscribe ${channel}`);
    }
  }

  close(): void {
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.close();
    }
  }
}
