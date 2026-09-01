// Ambient declarations for the renderer packages: the published
// @screeps/renderer tarball ships no usable type definitions (its
// declared main.d.ts is absent from the tarball and stale in the
// repo), so the surface we use is declared here from the contract in
// docs/viewer-contract.md.
declare module "@screeps/renderer" {
  const pkg: {
    GameRenderer: {
      new (options: Record<string, unknown>): RendererInstance;
      compileMetadata(metadata: unknown): void;
      isWebGLSupported: boolean;
    };
  };
  export = pkg;
}

declare module "@screeps/renderer-metadata" {
  const metadata: { objects: Record<string, unknown> };
  export = metadata;
}

interface RendererInstance {
  init(container: HTMLElement): Promise<void>;
  setTerrain(terrain: Array<Record<string, unknown>>): Promise<void> | void;
  applyState(state: Record<string, unknown>, tickDuration: number): void;
  resize(): void;
  release(): void;
  zoomLevel: number;
  cameraPosition: { x: number; y: number };
  pan(x: number, y: number): void;
}
