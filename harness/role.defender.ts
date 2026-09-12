import {
  validDefenderState,
  defenderTransition,
  defenderContext,
} from "../generated/index";
import type { DefenderState } from "../generated/index";
import { threatLevel } from "machine";
import type { Step } from "machine";

export const machine: Step = (state, _creep, obs) => {
  let s: DefenderState;
  try {
    s = validDefenderState(state);
  } catch {
    return null;
  }
  const event = threatLevel(obs);
  return { event, next: defenderTransition(s, event, defenderContext).target };
};
