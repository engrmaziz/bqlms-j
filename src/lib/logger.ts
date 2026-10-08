import pino from "pino";
import { requestContext } from "./request-context";

export const logger = pino({
	level: process.env.NODE_ENV === "test" ? "silent" : "info",
	formatters: {
		level: (label) => {
			return { level: label };
		},
	},
	redact: {
		paths: ["authorization", "cookie", "password", "token"],
		censor: "[REDACTED]",
	},
	mixin() {
		const context = requestContext.getStore();
		return context ? { reqId: context.requestId, userId: context.userId } : {};
	},
});
