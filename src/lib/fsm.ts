import { AppError } from "./errors";

export type StateMachineTransitions<
	State extends string,
	Event extends string,
> = {
	[K in State]?: {
		[E in Event]?: State;
	};
};

export function defineMachine<State extends string, Event extends string>(
	transitions: StateMachineTransitions<State, Event>,
) {
	return function transition(currentState: State, event: Event): State {
		const nextState = transitions[currentState]?.[event];
		if (!nextState) {
			throw new AppError(
				"PRECONDITION_FAILED",
				`Illegal move: cannot transition from ${currentState} via ${event}`,
			);
		}
		return nextState;
	};
}
