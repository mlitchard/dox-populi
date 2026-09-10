import type { CreepRole } from "../generated/index";

declare global {
  interface CreepMemory {
    role: CreepRole;
  }

  interface Memory {
    // One log per creep of its recent API calls, keyed by creep name.
    trace?: Record<
      string,
      Array<{ t: number; action: string; rc: number | null }>
    >;
  }
}

export {};
