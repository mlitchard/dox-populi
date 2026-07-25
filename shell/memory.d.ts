import type { CreepRole } from "../generated/index";

declare global {
  interface CreepMemory {
    role: CreepRole;
  }
}

export {};
