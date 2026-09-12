import {
  validUpgraderState,
  upgraderTransition,
  upgraderContext,
} from "../generated/index";
import type { UpgraderState } from "../generated/index";
import { emitEvent } from "machine";
import type { Step } from "machine";

export const machine: Step = (state, creep, obs) => {
  let s: UpgraderState;
  try {
    s = validUpgraderState(state);
  } catch {
    return null;
  }
  const event = emitEvent(creep, obs);
  return { event, next: upgraderTransition(s, event, upgraderContext).target };
};
