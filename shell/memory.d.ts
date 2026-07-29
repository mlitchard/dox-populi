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
    };
  }
}

export {};
