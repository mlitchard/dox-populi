// The pieces every role module reads: the room observation shape, the
// step contract, and the event builders.
import type { CreepEvent, CreepState, ThreatLevel } from "../generated/index";

// The structures that receive creep energy deliveries. This set gives
// the spec's SinksOpen/SinksFull facts and energySink target their
// meaning.
export type EnergySink = StructureSpawn | StructureExtension | StructureTower;

// What the shell observed in a room this tick. Every creep and tower
// in the room reads the same snapshot for events and targeting.
export interface RoomObs {
  sinks: EnergySink[];
  sinksAllFull: boolean;
  hasSites: boolean;
  hostiles: Creep[];
  damaged: AnyStructure[];
}

// The worker machines emit CreepEvent; the defender emits ThreatLevel.
export interface StepResult {
  event: string;
  next: CreepState;
}

// One machine's try at a creep tick; null means the state is outside
// this machine's union.
export type Step = (
  state: CreepState,
  creep: Creep,
  obs: RoomObs
) => StepResult | null;

// Builds the event name from three answers: the creep's store level
// (empty, mid, full), whether every sink is full, and whether any
// construction site exists. The return type makes any name outside
// the generated CreepEvent union a compile error.
export function emitEvent(creep: Creep, obs: RoomObs): CreepEvent {
  const used = creep.store.getUsedCapacity(RESOURCE_ENERGY);
  const free = creep.store.getFreeCapacity(RESOURCE_ENERGY);
  const store = used === 0 ? "empty" : free === 0 ? "full" : "mid";
  const sinks = obs.sinksAllFull ? "SinksFull" : "SinksOpen";
  const sites = obs.hasSites ? "Site" : "NoSite";
  return `${store}${sinks}${sites}`;
}

// The single threat reading. Three consumers: the defender's event,
// the first fact of the tower event, and the spawn policy's
// desired-count key.
export function threatLevel(obs: RoomObs): ThreatLevel {
  return obs.hostiles.length > 0 ? "hostile" : "calm";
}
