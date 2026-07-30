import type { CreepRole, CreepState } from "../generated/index";

declare global {
  interface CreepMemory {
    role: CreepRole;
    fsm?: CreepState;
  }

  interface Memory {
    stats?: {
      spawnEnergy: number;
      controllerProgress: number;
      controllerLevel: number;
      extensionsBuilt: number;
      extensionProgress: number;
      spawning: string | null;
      roleCounts: Record<string, number>;
      births: number;
      deaths: number;
      creeps: Record<
        string,
        {
          role: string;
          event: string;
          fsm: string;
          action: string;
          parts: number;
        }
      >;
    };
  }
}

export {};
