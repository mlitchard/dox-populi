// Ambient declarations for the renderer packages: the published
// @screeps/renderer tarball ships no usable type definitions (its
// declared main.d.ts is absent from the tarball and stale in the
// repo), so the surface we use is declared here from the contract in
// docs/viewer-contract.md.
declare module "@screeps/renderer" {
  const pkg: unknown;
  export = pkg;
}

declare module "@screeps/renderer-metadata" {
  const metadata: unknown;
  export = metadata;
}

interface GameRendererClass {
  new (options: Record<string, unknown>): RendererInstance;
  compileMetadata(metadata: unknown): void;
  isWebGLSupported: boolean;
}

interface RendererInstance {
  init(container: HTMLElement): Promise<void>;
  setTerrain(terrain: Array<Record<string, unknown>>): Promise<void> | void;
  applyState(state: Record<string, unknown>, tickDuration: number): void;
  resize(newSize?: { width: number; height: number }): void;
  release(): void;
  zoomLevel: number;
  pan(x: number, y: number): void;
  zoomTo(value: number, x: number, y: number): void;
  app: {
    stage: {
      position: { x: number; y: number };
      scale: { x: number; y: number };
    };
  };
}
