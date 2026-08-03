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
      // Cumulative combat observation, diffed against the previous
      // tick's snapshot (the births/deaths pattern). hostiles/hits ARE
      // the snapshot: hostile positions+hits by id, own-object hit
      // points by creep name / structure id.
      combat: {
        hostileMoves: number;
        damageTaken: number;
        hostilesDowned: number;
        hostiles: Record<string, { x: number; y: number; hits: number }>;
        hits: Record<string, number>;
      };
    };
    // Tower FSM state, keyed by tower id — towers have no built-in memory.
    towers?: Record<string, { fsm: TowerState }>;
    // Refill-hysteresis latch bit per tower id (spec: towerContext
    // energyTarget/refillTarget law) — true while a refill campaign runs.
    towerRefill?: Record<string, boolean>;
    // Raider FSM state, keyed by creep name — lives in the seeded
    // "raiders" NPC user's memory, written only by shell/invader.ts
    // (the enemy bundle). The
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
