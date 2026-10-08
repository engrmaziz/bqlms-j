import type { AppError } from "./errors";

export type Success<T> = {
	ok: true;
	value: T;
};

export type Failure<E> = {
	ok: false;
	error: E;
};

export type Result<T, E = AppError> = Success<T> | Failure<E>;

export function ok<T>(value: T): Success<T> {
	return { ok: true, value };
}

export function fail<E>(error: E): Failure<E> {
	return { ok: false, error };
}
