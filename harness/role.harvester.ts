import {
  validHarvesterState,
  harvesterTransition,
  harvesterContext,
} from "../generated/index";
import type { HarvesterState } from "../generated/index";
import { emitEvent } from "machine";
import type { Step } from "machine";

export const machine: Step = (state, creep, obs) => {
  let s: HarvesterState;
  try {
    s = validHarvesterState(state);
  } catch {
    return null;
  }
  const event = emitEvent(creep, obs);
  return { event, next: harvesterTransition(s, event, harvesterContext).target };
};
