import type { CreepRole, CreepState, TowerState } from "../generated/index";
import type { InvaderState } from "../generated/invader";

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
      towersBuilt: number;
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
      towers: Record<
        string,
        {
          event: string;
          fsm: string;
          action: string;
          energy: number;
        }
      >;
      hostiles: number;
      damaged: number;
    };
    // Tower FSM state, keyed by tower id — towers have no built-in memory.
    towers?: Record<string, { fsm: TowerState }>;
    // Raider FSM state, keyed by creep name — lives in NPC user 2's
    // memory, written only by shell/invader.ts (the enemy bundle). The
    // colony shell never touches it; the field coexists here because both
    // bundles share one global Memory declaration.
    raiders?: Record<string, { fsm: InvaderState }>;
    trace?: Record<
      string,
      Array<{
        t: number;
        event: string;
        fsm: string;
        action: string;
        rc: number | null;
      }>
    >;
  }
}

export {};
