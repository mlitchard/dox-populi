// The shapes of everything the shell stores in Screeps Memory. Both
// bundles, colony (main.ts) and invader (invader.ts), compile against
// this one declaration.
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
      combat: {
        hostileMoves: number;
        damageTaken: number;
        hostilesDowned: number;
        hostiles: Record<string, { x: number; y: number; hits: number }>;
        hits: Record<string, number>;
      };
    };
    // Keyed by tower id: each tower's FSM state.
    towers?: Record<string, { fsm: TowerState }>;

    // Keyed by tower id: true while that tower's refill is in progress.
    towerRefill?: Record<string, boolean>;

    // Keyed by raider creep name: each raider's FSM state. Written by
    // invader.ts.
    raiders?: Record<string, { fsm: InvaderState }>;
    // One log per actor of its recent changes, keyed by creep name or
    // tower id, kept for debugging. Written by both main.ts and invader.ts.
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
