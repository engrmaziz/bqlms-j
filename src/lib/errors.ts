export type AppErrorCode =
	| "UNAUTHENTICATED"
	| "FORBIDDEN"
	| "NOT_FOUND"
	| "VALIDATION"
	| "CONFLICT"
	| "RATE_LIMITED"
	| "PRECONDITION_FAILED"
	| "QUOTA_EXCEEDED"
	| "UPSTREAM_UNAVAILABLE"
	| "INTERNAL";

export class AppError extends Error {
	public readonly code: AppErrorCode;
	public readonly status: number;
	public readonly details?: unknown;

	constructor(code: AppErrorCode, message: string, details?: unknown) {
		super(message);
		this.name = "AppError";
		this.code = code;
		this.status = mapCodeToStatus(code);
		this.details = details;
	}
}

function mapCodeToStatus(code: AppErrorCode): number {
	switch (code) {
		case "UNAUTHENTICATED":
			return 401;
		case "FORBIDDEN":
			return 403;
		case "NOT_FOUND":
			return 404;
		case "VALIDATION":
			return 400;
		case "CONFLICT":
			return 409;
		case "RATE_LIMITED":
			return 429;
		case "PRECONDITION_FAILED":
			return 412;
		case "QUOTA_EXCEEDED":
			return 402; // Using 402 Payment Required or 429 based on standard, mapping to 402 as standard quota mapping is loose
		case "UPSTREAM_UNAVAILABLE":
			return 502;
		case "INTERNAL":
			return 500;
	}
}
