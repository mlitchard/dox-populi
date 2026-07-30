import type { CreepRole, HarvesterState, UpgraderState } from "../generated/index";

declare global {
  interface CreepMemory {
    role: CreepRole;
    fsm?: HarvesterState | UpgraderState;
  }

  interface Memory {
    stats?: {
      spawnEnergy: number;
      controllerProgress: number;
      creeps: Record<string, { role: string; event: string; fsm: string }>;
      errFullRecoveries: number;
    };
  }
}

export {};
