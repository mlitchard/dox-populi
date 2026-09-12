import {
  validBuilderState,
  builderTransition,
  builderContext,
} from "../generated/index";
import type { BuilderState } from "../generated/index";
import { emitEvent } from "machine";
import type { Step } from "machine";

export const machine: Step = (state, creep, obs) => {
  let s: BuilderState;
  try {
    s = validBuilderState(state);
  } catch {
    return null;
  }
  const event = emitEvent(creep, obs);
  return { event, next: builderTransition(s, event, builderContext).target };
};
